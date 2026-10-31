import Foundation
import OCFoundation
import OCModels
import OCNetworking
import OCPushCore
import OCSecurity

extension ReadStore {
    public func familyPermissions(_ sessionID: String) -> [PermissionRequest] {
        let ids = Set(family(sessionID).map(\.id)).union([sessionID])
        return ids.flatMap { permissions[$0] ?? [] }.sorted { $0.id < $1.id }
    }
    public func familyForms(_ sessionID: String) -> [FormInfo] {
        let ids = Set(family(sessionID).map(\.id)).union([sessionID])
        return ids.flatMap { forms[.session($0)] ?? [] }.sorted { $0.id < $1.id }
    }
    public func permissionForTool(_ callID: String, sessionID: String) -> PermissionRequest? {
        permissions[sessionID]?.first { $0.source?.id == callID }
    }
    public func permissionNeedsAuthentication(_ request: PermissionRequest, decision: PermissionDecision) -> Bool {
        decision == .always || (decision == .once && PermissionRisk.assess(request) == .high)
    }
    /// Runs the device-owner gate on its own so a sheet can stay open until it resolves.
    /// The completion receives a DeviceAuthenticationError on failure.
    public func authenticatePermission(_ request: PermissionRequest, decision: PermissionDecision,
                                       completion: @escaping @MainActor (Result<Void, DeviceAuthenticationError>) -> Void) {
        owned { [weak self] in
            guard let self else { return }
            do { try await self.authenticate(request, decision: decision); completion(.success(())) }
            catch { completion(.failure(DeviceAuthenticationError(error))) }
        }
    }
    /// Pass `authenticated` only after `authenticatePermission` succeeded for this decision.
    public func respondToPermission(_ request: PermissionRequest, decision: PermissionDecision, message: String? = nil, authenticated: Bool = false) {
        if decision == .once { approvalStarts[request.sessionID] = clock.now(); lastApprovalRoundTrip = nil }
        approvalErrors[request.id] = nil
        owned { [weak self] in
            guard let self else { return }
            do { try await self.replyPermission(request, decision: decision, message: message, authenticated: authenticated) }
            catch let failure where failure is DeviceAuthenticationError || failure is CancellationError {
                // A cancelled prompt is silent; other gate failures explain themselves on the request.
                self.approvalErrors[request.id] = DeviceAuthenticationError(failure).message
            } catch { self.approvalErrors[request.id] = localized("Reply could not be sent. Try again.") }
        }
    }
    public func replyPermission(_ request: PermissionRequest, decision: PermissionDecision, message: String? = nil, authenticated: Bool = false) async throws {
        guard permissions[request.sessionID]?.contains(where: { $0.id == request.id }) == true,
              !replyingPermissions.contains(request.id) else { return }
        replyingPermissions.insert(request.id)
        defer { replyingPermissions.remove(request.id) }
        if !authenticated { try await authenticate(request, decision: decision) }
        // Authentication can outlive a request settled on another client.
        guard permissions[request.sessionID]?.contains(where: { $0.id == request.id }) == true else { return }
        let removed = decision == .reject ? permissions[request.sessionID] ?? [] : [request]
        if decision == .once && approvalStarts[request.sessionID] == nil { approvalStarts[request.sessionID] = clock.now() }
        let ids = Set(removed.map(\.id))
        hiddenPermissions.formUnion(ids)
        permissions[request.sessionID]?.removeAll { ids.contains($0.id) }; updateAttention()
        do {
            let api = try await writeAPI()
            try await api.send(WriteEndpoints.permission(request.sessionID, request: request.id, decision: decision, message: nonempty(message)))
            approvalErrors[request.id] = nil
            if decision == .reject {
                // A settled 404 acknowledges this request, not an attempted rejection
                // of its siblings. Rehydrate any requests the server still owns.
                hiddenPermissions.subtract(ids.subtracting([request.id]))
                scheduleRefresh(request.sessionID)
            }
        } catch {
            hiddenPermissions.subtract(ids.subtracting(settledPermissions))
            for item in removed where !settledPermissions.contains(item.id) && !(permissions[item.sessionID]?.contains { $0.id == item.id } ?? false) {
                permissions[item.sessionID, default: []].append(item)
            }
            updateAttention(); throw error
        }
    }
    public func respondToForm(_ form: FormInfo, answer: [String: JSONValue]?, reason: String? = nil, directory: String? = nil) {
        if answer != nil { answerStarts[form.id] = clock.now(); lastAnswerRoundTrip = nil }
        approvalErrors[form.id] = nil
        owned { [weak self] in
            guard let self else { return }
            do { try await self.replyForm(form, answer: answer, reason: reason, directory: directory) }
            catch { self.approvalErrors[form.id] = localized("Answers could not be sent. Review and try again.") }
        }
    }
    public func replyForm(_ form: FormInfo, answer: [String: JSONValue]?, reason: String? = nil, directory: String? = nil) async throws {
        let owner: FormOwner
        var directory = directory
        if form.sessionID == "global" {
            guard let entry = forms.first(where: { owner, values in
                guard case .global = owner else { return false }
                return values.contains { $0.id == form.id }
            }), case .global(let key) = entry.key,
               let location = try? JSONDecoder().decode(JSONValue.self, from: Data(key.utf8)),
               let resolved = location.arrayValue?.first?.stringValue else { throw WriteStoreError.requestUnavailable }
            owner = entry.key
            directory = resolved
        } else { owner = .session(form.sessionID) }
        guard forms[owner]?.contains(where: { $0.id == form.id }) == true else { return }
        if let answer, !FormValidation.errors(form, answers: answer).isEmpty { throw WriteStoreError.requestUnavailable }
        hiddenForms[owner, default: []].insert(form.id)
        forms[owner]?.removeAll { $0.id == form.id }; updateAttention()
        do {
            let api = try await writeAPI()
            if let answer { try await api.send(WriteEndpoints.formReply(form.sessionID, form: form.id, answer: FormValidation.activeAnswers(form, answers: answer), directory: directory)) }
            else { try await api.send(WriteEndpoints.dismissForm(form.sessionID, form: form.id, reason: nonempty(reason), directory: directory)) }
            formDrafts.removeValue(forKey: form.id)
            approvalErrors[form.id] = nil
        } catch {
            if !(settledForms[owner]?.contains(form.id) ?? false) {
                hiddenForms[owner]?.remove(form.id)
                forms[owner, default: []].append(form)
            }
            updateAttention(); throw error
        }
    }
    private func authenticate(_ request: PermissionRequest, decision: PermissionDecision) async throws {
        guard permissionNeedsAuthentication(request, decision: decision) else { return }
        try await biometricGate.authenticate(reason: authenticationReason(request, decision: decision))
    }
    /// Names the action and its first resource so the system prompt says what is being allowed.
    func authenticationReason(_ request: PermissionRequest, decision: PermissionDecision) -> String {
        guard let resource = request.resources.first?.trimmingCharacters(in: .whitespacesAndNewlines), !resource.isEmpty else {
            return decision == .always ? localized("Always allow \(request.action) in this project", comment: "Authentication reason; %@ is a tool action")
                : localized("Allow high-risk \(request.action)", comment: "Authentication reason; %@ is a tool action")
        }
        let shown: String = resource.count > 60 ? resource.prefix(59) + "…" : resource
        return decision == .always ? localized("Always allow \(request.action) in this project: \(shown)", comment: "Authentication reason; first %@ is a tool action, second its resource")
            : localized("Allow high-risk \(request.action): \(shown)", comment: "Authentication reason; first %@ is a tool action, second its resource")
    }
    private func nonempty(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }
}

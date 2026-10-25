import Foundation
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync

private actor TestBiometricGate: BiometricAuthenticating {
    let succeeds: Bool
    var calls = 0
    init(succeeds: Bool) { self.succeeds = succeeds }
    func authenticate(reason: String) throws {
        calls += 1
        if !succeeds { throw CancellationError() }
    }
}
private func permission(_ id: String, session: String = "s") -> PermissionRequest {
    .init(raw: .object(["id": .string(id), "sessionID": .string(session), "action": .string("read"), "resources": .array([.string("/p/file")]), "save": .array([.string("/p/*")]), "source": .object(["type": .string("tool"), "id": .string("tool")])]))
}

@Test @MainActor func globalFormUsesItsResolvedWorkspaceLocation() async throws {
    let store = ReadStore(serverID: "server")
    let form = FormInfo(raw: .object(["id": .string("global-form"), "sessionID": .string("global"), "fields": .array([])]))
    let owner = FormOwner.global(location: Location(directory: "/workspace/project", workspaceID: "workspace").key)
    store.forms[owner] = [form]
    store.client = { readAPI { request in
        let url = try #require(request.url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "location[directory]", value: "/workspace/project")) == true)
        return .object([:])
    } }
    try await store.replyForm(form, answer: [:])
    #expect(store.forms[owner]?.isEmpty == true)
    await store.stop()
}
@Test @MainActor func alwaysRequiresAuthenticationAndRejectRemovesSessionSiblings() async throws {
    let store = ReadStore(serverID: "server"), first = permission("p1"), sibling = permission("p2"), child = permission("child", session: "child")
    store.seed(info: readInfo(), permissions: [first, sibling]); store.seed(info: readInfo("child", parent: "s"), permissions: [child])
    let gate = TestBiometricGate(succeeds: false); store.biometricGate = gate
    store.client = { readAPI { _ in .object([:]) } }
    await #expect(throws: CancellationError.self) { try await store.replyPermission(first, decision: .always) }
    #expect(await gate.calls == 1); #expect(store.permissions["s"]?.count == 2)
    #expect(store.familyPermissions("s").count == 3)
    #expect(store.permissionForTool("tool", sessionID: "s") != nil)
    #expect(store.permissionForTool("tool", sessionID: "unrelated") == nil)
    #expect(store.permissionForTool("tool", sessionID: "child")?.id == "child")
    store.client = { readAPI { request in
        await MainActor.run { #expect(store.permissions["s"]?.isEmpty == true); #expect(store.permissions["child"]?.count == 1) }
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["decision"] == .string("reject")); #expect(body["message"] == .string("Use the fixture instead."))
        return .object([:])
    } }
    try await store.replyPermission(first, decision: .reject, message: "Use the fixture instead.")
    #expect(store.permissions["s"]?.isEmpty == true)
    await store.stop()
}
@Test @MainActor func failedApprovalRestoresUnsettledRequestsButNotServerResolvedOnes() async throws {
    let store = ReadStore(serverID: "server"), first = permission("p1"), sibling = permission("p2")
    store.seed(info: readInfo(), permissions: [first, sibling])
    store.client = { readAPI { _ in
        let event = try readEvent("permission.replied", data: ["requestID": .string("p2")])
        await MainActor.run { store.apply(event) }
        throw URLError(.timedOut)
    } }
    do { try await store.replyPermission(first, decision: .reject) } catch APIError.transport {}
    #expect(store.permissions["s"]?.map(\.id) == ["p1"])
    await store.stop()
}
@Test @MainActor func optimisticRepliesStayHiddenFromRacingSnapshots() async throws {
    let store = ReadStore(serverID: "server"), request = permission("p")
    let form = FormInfo(raw: .object(["id": .string("f"), "sessionID": .string("s"), "fields": .array([.object(["type": .string("boolean"), "key": .string("answer"), "required": .bool(true)])])]))
    store.seed(info: readInfo(), permissions: [request], forms: [form])
    store.client = { readAPI { _ in .object([:]) } }
    try await store.replyPermission(request, decision: .once)
    try await store.replyForm(form, answer: ["answer": .bool(false)])
    store.applyRequests([request], forms: [form], owner: "s", overlay: FetchOverlay())
    #expect(store.permissions["s"]?.isEmpty == true && store.forms[.session("s")]?.isEmpty == true)
    await store.stop()
}

private actor ScriptedGate: BiometricAuthenticating {
    let failure: DeviceAuthenticationError?
    var reasons: [String] = []
    init(failure: DeviceAuthenticationError?) { self.failure = failure }
    func authenticate(reason: String) throws {
        reasons.append(reason)
        if let failure { throw failure }
    }
}
@MainActor private func settle(_ store: ReadStore, until done: () -> Bool) async {
    for _ in 0..<500 where !done() { try? await Task.sleep(for: .milliseconds(2)) }
}
@Test @MainActor func cancelledAuthenticationIsSilentAndOtherFailuresStayOnTheRequest() async throws {
    let store = ReadStore(serverID: "server"), request = permission("p1")
    store.seed(info: readInfo(), permissions: [request])
    store.client = { readAPI { _ in .object([:]) } }
    let cancelled = ScriptedGate(failure: .cancelled); store.biometricGate = cancelled
    store.respondToPermission(request, decision: .always)
    for _ in 0..<500 {
        if await cancelled.reasons.count == 1 && store.replyingPermissions.isEmpty { break }
        try await Task.sleep(for: .milliseconds(2))
    }
    #expect(await cancelled.reasons == ["Always allow read in this project: /p/file"])
    #expect(store.approvalErrors.isEmpty && store.writeError == nil)
    #expect(store.permissions["s"]?.map(\.id) == ["p1"])
    store.biometricGate = ScriptedGate(failure: .passcodeNotSet)
    store.respondToPermission(request, decision: .always)
    await settle(store) { store.approvalErrors["p1"] != nil }
    #expect(store.approvalErrors["p1"] == DeviceAuthenticationError.passcodeNotSet.message)
    #expect(store.writeError == nil)
    await store.stop()
}
@Test @MainActor func sheetAuthenticationRunsOnceThenRepliesWithoutAskingAgain() async throws {
    let store = ReadStore(serverID: "server"), request = permission("p1")
    store.seed(info: readInfo(), permissions: [request])
    store.client = { readAPI { _ in .object([:]) } }
    let gate = ScriptedGate(failure: nil); store.biometricGate = gate
    #expect(store.permissionNeedsAuthentication(request, decision: .always))
    #expect(!store.permissionNeedsAuthentication(request, decision: .once))
    var outcome: Result<Void, DeviceAuthenticationError>?
    store.authenticatePermission(request, decision: .always) { outcome = $0 }
    await settle(store) { outcome != nil }
    guard case .success = outcome else { Issue.record("Authentication should succeed"); return }
    store.respondToPermission(request, decision: .always, authenticated: true)
    await settle(store) { store.permissions["s"]?.isEmpty == true }
    #expect(await gate.reasons.count == 1)
    #expect(store.approvalErrors.isEmpty)
    await store.stop()
}
@Test @MainActor func failedRepliesAreScopedToTheirRequest() async throws {
    let store = ReadStore(serverID: "server"), request = permission("p1")
    let form = FormInfo(raw: .object(["id": .string("f"), "sessionID": .string("s"), "fields": .array([])]))
    store.seed(info: readInfo(), permissions: [request], forms: [form])
    store.client = { readAPI { _ in throw URLError(.timedOut) } }
    store.respondToPermission(request, decision: .once)
    store.respondToForm(form, answer: [:])
    await settle(store) { store.approvalErrors.count == 2 }
    #expect(store.approvalErrors["p1"] == "Reply could not be sent. Try again.")
    #expect(store.approvalErrors["f"] == "Answers could not be sent. Review and try again.")
    #expect(store.writeError == nil)
    #expect(store.permissions["s"]?.map(\.id) == ["p1"])
    await store.stop()
}
@Test @MainActor func authenticationReasonNamesTheActionAndTruncatesTheResource() {
    let store = ReadStore(serverID: "server")
    var request = permission("p1"); request["action"] = .string("shell"); request["resources"] = .array([.string(String(repeating: "a", count: 80))])
    let reason = store.authenticationReason(request, decision: .once)
    #expect(reason.hasPrefix("Allow high-risk shell: ") && reason.hasSuffix("…") && reason.count == "Allow high-risk shell: ".count + 60)
    request["resources"] = .array([])
    #expect(store.authenticationReason(request, decision: .always) == "Always allow shell in this project")
}

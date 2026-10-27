import Foundation
import OCFoundation
import OCModels
import OCNetworking
import OCPushCore
import OCShared

@MainActor public final class NotificationActionHandler {
    public struct Connection: Sendable {
        public var fetch: @Sendable (String) async throws -> JSONValue
        public var reply: @Sendable (String, JSONValue) async throws -> Void
        public init(fetch: @escaping @Sendable (String) async throws -> JSONValue,
                    reply: @escaping @Sendable (String, JSONValue) async throws -> Void) { self.fetch = fetch; self.reply = reply }
    }
    public typealias Connect = @MainActor @Sendable (String) async throws -> Connection
    /// Returns false when the notification was already replied to.
    public typealias Queue = @MainActor @Sendable (ShownNotification, String) async throws -> Bool
    private let store: PushSnapshotStore
    private let clock: NetworkClock
    private let connect: Connect
    private let queue: Queue
    public init(store: PushSnapshotStore, clock: NetworkClock = .init(), connect: @escaping Connect, queue: @escaping Queue) {
        self.store = store; self.clock = clock; self.connect = connect; self.queue = queue
    }
    public func handle(shownID: String, receipt: String?, route: String? = nil, action: NotificationAction.ID, text: String? = nil) async -> String {
        guard action != .open else { return "Open" }
        let shown = try? store.shown(shownID)
        let routed = route.flatMap(URL.init(string:)).flatMap(DeepLink.init(url:))?.serverID.uuidString
        var audit = NotificationAuditEntry(server: shown?.server ?? routed ?? "", requestID: shownID,
            action: action.rawValue, result: "Started; outcome not yet confirmed", date: clock.date())
        do { try store.append(audit) } catch { return "Could not save the notification audit. Open the app to review" }
        var result = "Open the app to review"
        do {
            if let shown, receipt != shown.receipt.uuidString {
                result = "The request changed. Open the app to review"
            } else if let shown {
                result = try await withActionDeadline(seconds: .seconds(28), clock: clock) { [self] in
                    try await perform(shown, action: action, text: text)
                }
            }
        } catch APIError.server(_, 404, _) { result = "Already handled" }
        catch { result = "Couldn't reach your server" }
        do {
            audit.result = result
            try store.append(audit)
        } catch { return result + ". Could not save the notification audit." }
        return result
    }
    private func perform(_ shown: ShownNotification, action: NotificationAction.ID, text: String?) async throws -> String {
        guard shown.expiresAt > clock.date(), try store.server(keyID: shown.keyID) == shown.server else { return "Open the app to review" }
        if action == .reply, ["finished", "failed"].contains(shown.kind) {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Open the app to reply" }
            try Task.checkCancellation()
            return try await queue(shown, text) ? "Reply queued" : "Already replied"
        }
        guard try store.preferences().lockScreenApprovals, let session = shown.sessionID, let expected = shown.digest,
              ["permission", "question"].contains(shown.kind) else { return "Open the app to review" }
        let connection = try await connect(shown.server)
        let path = "/api/session/\(session)/\(shown.kind == "permission" ? "permission" : "form")/\(shown.id)"
        let raw = try await connection.fetch(path)
        let digest = try shown.kind == "permission" ? PushDigest.permission(raw: raw) : PushDigest.form(raw: raw)
        guard digest == expected else { return "The request changed. Open the app to review" }
        let body: JSONValue
        let feedback: String
        if shown.kind == "permission" {
            let request = PermissionRequest(raw: raw)
            switch action {
            case .allow:
                guard PermissionRisk.assess(request) != .high else { return "Open the app to review this high-risk request" }
                body = .object(["decision": .string("once")]); feedback = "Approved"
            case .reject, .rejectWithNote:
                var fields: [String: JSONValue] = ["decision": .string("reject")]
                if action == .rejectWithNote, let text, !text.isEmpty { fields["message"] = .string(text) }
                body = .object(fields); feedback = "Rejected"
            default: return "Open the app to review"
            }
        } else {
            let form = FormInfo(raw: raw)
            guard action == .answer, form.fields.count == 1, case .string(let field) = form.fields[0],
                  field.options.isEmpty || field.custom, let text else { return "Open the app to answer" }
            let answer = [field.key: JSONValue.string(text)]
            guard FormValidation.errors(form, answers: answer).isEmpty else { return "Open the app to review your answer" }
            body = .object(["answer": .object(answer)]); feedback = "Answered"
        }
        // Recheck after network waits; a replacement or expiry may have invalidated the alert.
        guard shown.expiresAt > clock.date(), try store.preferences().lockScreenApprovals, try store.shown(shown.id) == shown else { return "Already handled" }
        try Task.checkCancellation()
        try await connection.reply(path + "/reply", body)
        return feedback
    }
}

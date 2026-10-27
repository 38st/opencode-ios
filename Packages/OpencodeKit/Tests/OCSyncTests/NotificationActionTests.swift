import Clocks
import OCActivity
import Foundation
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCPushCore
import OCShared
@testable import OCSync

private actor ActionProbe {
    var replies = 0
    func replied() { replies += 1 }
}
@MainActor @Suite struct NotificationActionTests {
    @Test(arguments: ["match", "mismatch", "gone", "offline", "high", "missing", "expired", "replaced"])
    func approvals(scenario: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PushSnapshotStore(directory: root), probe = ActionProbe()
        try store.register(keyID: "kid_test", server: "server")
        let request: JSONValue = .object(["id": .string("per_1"), "sessionID": .string("ses_1"),
            "action": .string(scenario == "high" ? "external_directory" : "read"), "resources": .array([.string("file")])])
        if scenario != "missing" {
            let shown = ShownNotification(id: "per_1", keyID: "kid_test", server: "server", sessionID: "ses_1", rootSessionID: "ses_1",
                kind: "permission", digest: scenario == "mismatch" ? "different" : try PushDigest.permission(raw: request),
                summary: "file", expiresAt: .now.addingTimeInterval(scenario == "expired" ? -1 : 60), displayedAt: .now)
            _ = try store.record(shown, pending: 1)
        }
        let handler = NotificationActionHandler(store: store, connect: { _ in
            if scenario == "offline" { throw URLError(.cannotConnectToHost) }
            return .init(fetch: { _ in
                if scenario == "gone" { throw APIError.server(tag: "PermissionNotFoundError", status: 404, body: .null) }
                return request
            }, reply: { _, _ in await probe.replied() })
        }, queue: { _, _ in Issue.record("Approval must not queue a prompt"); return false })
        let receipt = scenario == "replaced" ? UUID().uuidString : try store.shown("per_1")?.receipt.uuidString
        let result = await handler.handle(shownID: "per_1", receipt: receipt, action: .allow)
        let expected = ["match": "Approved", "mismatch": "The request changed. Open the app to review", "gone": "Already handled",
            "offline": "Couldn't reach your server", "high": "Open the app to review this high-risk request",
            "missing": "Open the app to review", "expired": "Open the app to review",
            "replaced": "The request changed. Open the app to review"]
        #expect(result == expected[scenario])
        #expect(await probe.replies == (scenario == "match" ? 1 : 0))
        #expect(try store.audit().count == 1)
    }
    @Test func deadlineCancelsWithoutSending() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PushSnapshotStore(directory: root), clock = TestClock()
        try store.register(keyID: "kid_test", server: "server")
        _ = try store.record(.init(id: "per_1", keyID: "kid_test", server: "server", sessionID: "ses_1", rootSessionID: "ses_1",
            kind: "permission", digest: "abc", summary: "file", expiresAt: .now.addingTimeInterval(60), displayedAt: .now), pending: 1)
        let handler = NotificationActionHandler(store: store, clock: .init(sleep: { try await clock.sleep(for: $0) }), connect: { _ in
            try await clock.sleep(for: .seconds(60)); throw CancellationError()
        }, queue: { _, _ in true })
        let task = Task { await handler.handle(shownID: "per_1", receipt: try? store.shown("per_1")?.receipt.uuidString, action: .allow) }
        await clock.advance(by: .seconds(28))
        #expect(await task.value == "Couldn't reach your server")
    }
    @Test func presenceTiming() async {
        let clock = TestClock()
        var values: [Bool] = []
        let presence = PresenceCoordinator(clock: .init(sleep: { try await clock.sleep(for: $0) })) { values.append($0) }
        await presence.setForeground(true)
        #expect(values == [true])
        await clock.advance(by: .seconds(29))
        #expect(values == [true])
        await clock.advance(by: .seconds(1))
        #expect(values == [true, true])
        await presence.setForeground(false)
        await clock.advance(by: .seconds(60))
        #expect(values == [true, true, false])
    }
    @Test func liveActivityLifecycle() {
        let now = Date(), state = OCActivity.SessionActivityAttributes.ContentState(startedAt: 0, updatedAt: 0)
        var lifecycle = LiveActivityLifecycle()
        #expect(lifecycle.advance(enabled: true, foreground: true, state: state, now: now) == .start)
        #expect(lifecycle.advance(enabled: true, foreground: false, state: state, now: now) == .none)
        #expect(lifecycle.advance(enabled: true, foreground: true, state: state, now: now) == .update)
        #expect(lifecycle.advance(enabled: true, foreground: true, state: state, now: now.addingTimeInterval(27000)) == .restart)
        var final = state; final.phase = "succeeded"
        #expect(lifecycle.advance(enabled: true, foreground: true, state: final, now: now) == .end(now.addingTimeInterval(900)))
    }
}

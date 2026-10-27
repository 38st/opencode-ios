import Foundation
import Testing
import OCShared
@Test func pushSnapshotsAreAtomicAndServerScoped() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PushSnapshotStore(directory: root)
    try store.register(keyID: "key_one", server: "one")
    #expect(try store.setPending(2, server: "one") == 2)
    #expect(try store.setPending(3, server: "two") == 5)
    let now = Date()
    let shown = ShownNotification(id: "per_1", keyID: "key_one", server: "one", sessionID: "ses_1", rootSessionID: "ses_1",
        kind: "permission", digest: "abc", summary: "file", expiresAt: now.addingTimeInterval(60), displayedAt: now)
    #expect(try store.record(shown, pending: 1) == 4)
    #expect(try store.shown("per_1") == shown)
    try store.prune(now: now.addingTimeInterval(61))
    #expect(try store.shown("per_1") == nil)
    try store.remove(server: "one")
    #expect(try store.server(keyID: "key_one") == nil)
    #expect(try store.badge() == 3)
    #expect(throws: (any Error).self) { try store.shown("../secret") }
}

@Test func notificationRouteKeepsTheRequestSession() throws {
    let shown = ShownNotification(id: "per_child", keyID: "key", server: UUID().uuidString,
        sessionID: "ses_child", rootSessionID: "ses_root", kind: "permission", digest: "digest",
        summary: "A child request", expiresAt: .now.addingTimeInterval(60), displayedAt: .now)
    let url = try #require(shown.url)
    let link = try #require(DeepLink(url: url))
    #expect(link.sessionID == "ses_child")
    #expect(link.requestID == "per_child")
}

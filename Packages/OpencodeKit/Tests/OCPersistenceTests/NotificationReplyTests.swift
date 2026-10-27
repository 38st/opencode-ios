import Foundation
import Testing
import OCModels
@testable import OCPersistence

@Test func notificationReplyReceiptSurvivesAcknowledgementAndRelaunch() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "cache.sqlite")
    let writer = try PersistenceWriter(url: file)
    let original = OutboxEntry(id: "msg_1", serverID: "server", sessionID: "ses_1", body: Data("original".utf8))
    #expect(try await writer.admitNotificationReply(original, notificationID: "notification") == true)
    #expect(try await OutboxStore(writer: writer).entries(serverID: "server").first?.body == original.body)
    try await OutboxStore(writer: writer).remove(id: original.id)
    let restored = try PersistenceWriter(url: file)
    let duplicate = OutboxEntry(id: "msg_2", serverID: "server", sessionID: "ses_1", body: Data("changed".utf8))
    #expect(try await restored.admitNotificationReply(duplicate, notificationID: "notification") == false)
    #expect(try await OutboxStore(writer: restored).entries(serverID: "server").isEmpty)
}

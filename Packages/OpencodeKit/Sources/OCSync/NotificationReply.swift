import Foundation
import OCModels
import OCNetworking
import OCPersistence
import OCShared

extension ReadStore {
    /// False when this notification was already replied to: the text is dropped, never queued twice.
    @discardableResult func queueNotificationReply(_ shown: ShownNotification, text: String) async throws -> Bool {
        guard let cache, let session = shown.sessionID else { throw WriteStoreError.persistenceUnavailable }
        let id = try await mintMessage(session)
        let entry = OutboxEntry(id: id, serverID: serverID, sessionID: session,
            body: try PromptInput(text: text, delivery: .queue).body(id: id), createdAt: clock.date())
        let inserted = try await cache.writer.admitNotificationReply(entry, notificationID: shown.id)
        if inserted {
            outboxEntries[id] = entry; materializeOutbox(entry)
            phonePromptSent(session)
        }
        guard inserted else { return false }
        // The background notification is allowed to drain this durable admission without opening SSE.
        if let client, let outboxDrain {
            guard let api = try? await client() else { return true }
            // A failed opportunistic send leaves the original bytes in the durable outbox.
            _ = try? await withActionDeadline(seconds: .seconds(3)) { [weak self] in
                try await outboxDrain.drain(using: api) { [weak self] id, result in await self?.acknowledgeResponse(id, result: result) }
            }
        }
        return true
    }
}

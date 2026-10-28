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
        await drainNow(deadline: .seconds(3))
        return true
    }
    /// Sends the outbox now, without the event stream: a notification action or an intent can run while the app is in
    /// the background and its servers are suspended. A failed attempt leaves the admissions, bytes unchanged, in the
    /// outbox for the next pass.
    func drainNow(deadline: Duration, clock: NetworkClock = .init()) async {
        guard let client, let outboxDrain, let api = try? await client() else { return }
        _ = try? await withActionDeadline(seconds: deadline, clock: clock) { [weak self] in
            try await outboxDrain.drain(using: api) { [weak self] id, result in await self?.acknowledgeResponse(id, result: result) }
        }
    }
}

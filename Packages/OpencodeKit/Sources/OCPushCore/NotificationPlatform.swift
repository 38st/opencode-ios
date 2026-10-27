import Foundation
import OCFoundation
import OCModels
import OCSecurity
import OCShared
#if canImport(UserNotifications)
import UserNotifications
public extension NotificationPresentation {
    /// The pending count reached zero: the icon badge must be cleared without touching delivered notifications.
    var clearsBadge: Bool { badge == 0 }
    func apply(to content: UNMutableNotificationContent) {
        content.title = title; content.subtitle = subtitle; content.body = body
        content.categoryIdentifier = category
        if !thread.isEmpty { content.threadIdentifier = thread }
        content.relevanceScore = relevance
        // iOS withdraws every delivered notification of the app when one arrives with badge 0, so a zero
        // count never goes on the content; `clearsBadge` callers reset the icon with `setBadgeCount` instead.
        if let badge, badge > 0 { content.badge = NSNumber(value: badge) } else { content.badge = nil }
        // Routing always comes from the authenticated plaintext.
        content.userInfo.removeValue(forKey: "shownID"); content.userInfo.removeValue(forKey: "route")
        content.userInfo.removeValue(forKey: "shownReceipt")
        if let receipt { content.userInfo["shownReceipt"] = receipt }
        if let shownID { content.userInfo["shownID"] = shownID }
        if let url { content.userInfo["route"] = url.absoluteString }
    }
}
#endif
public extension NotificationContentBuilder {
    /// The deep link of a raw envelope, with no side effect on the store.
    static func route(data: Data, store: PushSnapshotStore, keys: PushKeyStore) async -> URL? {
        guard let envelope = try? JSONDecoder().decode(JSONValue.self, from: data), let parsed = try? PushEnvelope(json: envelope),
              let key = try? await keys.key(keyID: parsed.keyID), let sender = key.serverPublicKey,
              let server = try? store.server(keyID: parsed.keyID), server == key.server.rawValue.uuidString,
              let opened = try? PushSealing.open(envelope, now: .now, key: { _ in .init(privateKey: key.privateKey, senderPublicKey: sender) }),
              opened.payload.server == server, let serverID = UUID(uuidString: server) else { return nil }
        let payload = opened.payload
        return DeepLink.url(serverID: serverID, sessionID: payload.sessionID ?? payload.rootSessionID,
                            requestID: ["permission", "question", "resolved"].contains(payload.kind) ? payload.requestID : nil)
    }
    static func process(data: Data, generic: NotificationPresentation, store: PushSnapshotStore, keys: PushKeyStore) async -> NotificationPresentation {
        guard let envelope = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .init(title: generic.title, body: generic.body) }
        return await process(envelope: envelope, generic: generic, store: store, keys: keys)
    }
}

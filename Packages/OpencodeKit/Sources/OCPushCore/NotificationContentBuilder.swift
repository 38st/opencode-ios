import CryptoKit
import Foundation
import OCFoundation
import OCModels
import OCSecurity
import OCShared

public struct NotificationPresentation: Sendable, Equatable {
    public var title: String
    public var subtitle = ""
    public var body: String
    public var category = NotificationCategories.openOnly
    public var thread = ""
    public var relevance = 0.0
    public var badge: Int?
    public var shownID: String?
    public var receipt: String?
    public var url: URL?
    /// Set when the device's settings lower the server's level; `silenced` also drops the sound.
    public var interruption: NotificationFilter.Level?
    public var silenced = false
    public init(title: String = "", body: String) { self.title = title; self.body = body }
}

/// No network, UI framework or sync engine. Failure returns the original generic text, with Open only.
public enum NotificationContentBuilder {
    public static func build(envelope: JSONValue, key: PushRecipientKey?, server: String?, now: Date,
                             generic: NotificationPresentation, store: PushSnapshotStore) -> NotificationPresentation {
        var fallback = generic
        fallback.category = NotificationCategories.openOnly
        fallback.shownID = nil; fallback.receipt = nil; fallback.url = nil
        do {
            let opened = try PushSealing.open(envelope, now: now) { _ in key }
            let payload = opened.payload
            guard payload.server == server else { return fallback }
            // A completion has no request ID. Its envelope fingerprint keeps retries stable
            // without conflating two completions from the same session and second.
            let id = payload.requestID ?? "result_" + Base64URL.encode(Data(SHA256.hash(data: opened.envelope.ciphertext)))
            let preferences = try store.preferences()
            var content = NotificationPresentation(body: payload.summary ?? alert(kind: payload.kind) ?? generic.body)
            switch payload.kind {
            case "permission": content.title = payload.action.map { localized("Allow \($0)?", comment: "Notification title; %@ is the action a session asks to run") } ?? localized("Allow this action?")
            case "question": content.title = localized("A session needs your answer")
            case "resolved": content.title = localized("Request resolved"); content.body = localized("Answered on another device")
            default: content.title = alert(kind: payload.kind) ?? generic.title
            }
            content.subtitle = [payload.title, payload.project].compactMap { $0 }.joined(separator: " · ")
            content.category = NotificationCategories.category(kind: payload.kind, risk: payload.riskTier,
                freeText: payload.freeText == true, approvals: preferences.lockScreenApprovals)
            content.thread = payload.rootSessionID ?? payload.sessionID ?? ""
            content.relevance = ["permission", "question"].contains(payload.kind) ? 1 : 0.3
            switch NotificationFilter.decide(kind: payload.kind, server: payload.server, sessionID: payload.sessionID,
                                             rootSessionID: payload.rootSessionID, preferences: preferences, now: now) {
            case .silence: content.silenced = true; content.interruption = .passive; content.relevance = 0
            case .deliver(let level):
                if level.rawValue != PushContract.shared.kinds[payload.kind]?.interruptionLevel { content.interruption = level }
            }
            let shown = ShownNotification(id: id, keyID: opened.envelope.keyID, server: payload.server,
                sessionID: payload.sessionID, rootSessionID: payload.rootSessionID, kind: payload.kind,
                digest: payload.digest, summary: content.body, expiresAt: Date(timeIntervalSince1970: Double(payload.expiry)), displayedAt: now)
            content.badge = try store.record(shown, pending: payload.pending)
            content.shownID = id; content.receipt = shown.receipt.uuidString; content.url = shown.url
            return content
        } catch { return fallback }
    }

    /// The alert text `constants.json` gives each kind.
    static func alert(kind: String) -> String? {
        switch kind {
        case "permission": localized("opencode needs your approval")
        case "question": localized("opencode has a question")
        case "finished": localized("A session finished")
        case "failed": localized("A session failed")
        case "resolved": localized("Answered on another device")
        case "test": localized("Test notification from opencode")
        default: PushContract.shared.kinds[kind]?.alert
        }
    }

    public static func process(envelope: JSONValue, now: Date = .now, generic: NotificationPresentation,
                               store: PushSnapshotStore, keys: PushKeyStore) async -> NotificationPresentation {
        guard let parsed = try? PushEnvelope(json: envelope),
              let key = try? await keys.key(keyID: parsed.keyID), let sender = key.serverPublicKey,
              let server = try? store.server(keyID: parsed.keyID), server == key.server.rawValue.uuidString else {
            var fallback = generic; fallback.category = NotificationCategories.openOnly; return fallback
        }
        guard !Task.isCancelled else { return .init(title: generic.title, body: generic.body) }
        return build(envelope: envelope, key: .init(privateKey: key.privateKey, senderPublicKey: sender),
                     server: server, now: now, generic: generic, store: store)
    }
}

import Foundation
import OCShared

/// The device's notification settings applied to one verified push. iOS shows every remote alert, so a silenced push
/// arrives passive, without sound, and stays in Notification Center; removing it entirely would need Apple's
/// notification filtering entitlement.
public enum NotificationFilter {
    public enum Level: String, Sendable, Equatable { case passive, active, timeSensitive = "time-sensitive" }
    public enum Decision: Sendable, Equatable {
        /// The server's level, or a lower one.
        case deliver(Level)
        case silence
    }
    /// The kinds the settings list. Others (`resolved`, `test`) always keep the server's level.
    public static let kinds = ["permission", "question", "finished", "failed"]

    public static func decide(kind: String, server: String, sessionID: String?, rootSessionID: String?,
                              preferences: PushPreferences, now: Date, calendar: Calendar = .current) -> Decision {
        let level = Level(rawValue: PushContract.shared.kinds[kind]?.interruptionLevel ?? "") ?? .active
        guard kinds.contains(kind) else { return .deliver(level) }
        // Approvals are silenced only by their own switch: not by quiet hours and not by a muted session.
        if kind == "permission" { return preferences.silencedKinds.contains(kind) ? .silence : .deliver(level) }
        if preferences.silencedKinds.contains(kind) { return .silence }
        if preferences.muted(server: server, sessionID: sessionID, rootSessionID: rootSessionID) { return .silence }
        if let quiet = preferences.quietHours, quiet.contains(now, calendar: calendar) {
            return .deliver(level == .timeSensitive ? .active : .passive)
        }
        return .deliver(level)
    }
}

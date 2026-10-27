import Foundation

public struct NotificationAction: Sendable, Equatable {
    public enum ID: String, Sendable, CaseIterable { case open = "OPEN", allow = "ALLOW_ONCE", reject = "REJECT", rejectWithNote = "REJECT_NOTE", answer = "ANSWER", reply = "REPLY" }
    public let id: ID
    public let title: String
    public var foreground = false
    public var authenticationRequired = false
    public var destructive = false
    public var textInput = false
}

public enum NotificationCategories {
    public static let openOnly = "OPEN_ONLY"
    public static func category(kind: String, risk: PermissionRisk, freeText: Bool, approvals: Bool) -> String {
        switch kind {
        case "permission": approvals ? (risk == .high ? "PERMISSION_HIGH_RISK" : "PERMISSION") : openOnly
        case "question": approvals && freeText ? "QUESTION" : openOnly
        case "finished": "FINISHED"
        case "failed": "FAILED"
        default: openOnly
        }
    }
    public static func actions(for category: String) -> [NotificationAction] {
        let open = NotificationAction(id: .open, title: "Open", foreground: true)
        let reject = NotificationAction(id: .reject, title: "Reject", destructive: true)
        switch category {
        case "PERMISSION": return [open, .init(id: .allow, title: "Allow once", authenticationRequired: true), reject,
                                    .init(id: .rejectWithNote, title: "Reject with note…", destructive: true, textInput: true)]
        case "PERMISSION_HIGH_RISK": return [open, reject]
        case "QUESTION": return [open, .init(id: .answer, title: "Answer…", textInput: true)]
        case "FINISHED", "FAILED": return [open, .init(id: .reply, title: "Reply…", authenticationRequired: true, textInput: true)]
        default: return [open]
        }
    }
}

#if canImport(UserNotifications)
import UserNotifications
public extension NotificationCategories {
    static func register(center: UNUserNotificationCenter = .current()) {
        center.setNotificationCategories(Set(PushContract.shared.categories.map { id in
            UNNotificationCategory(identifier: id, actions: actions(for: id).map { action in
                var options: UNNotificationActionOptions = []
                if action.foreground { options.insert(.foreground) }
                if action.authenticationRequired { options.insert(.authenticationRequired) }
                if action.destructive { options.insert(.destructive) }
                if action.textInput {
                    return UNTextInputNotificationAction(identifier: action.id.rawValue, title: action.title, options: options,
                                                         textInputButtonTitle: "Send", textInputPlaceholder: "Message")
                }
                return UNNotificationAction(identifier: action.id.rawValue, title: action.title, options: options)
            }, intentIdentifiers: [], options: [])
        }))
    }
}
#endif

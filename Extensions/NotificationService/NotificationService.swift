import Foundation
import OCPushCore
import OCSecurity
import OCShared
import UserNotifications

// UNNotificationServiceExtension callbacks are nonisolated. The lock owns all mutable state;
// cancellation and normal completion compete for the same one-shot handler.
nonisolated final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((UNNotificationContent) -> Void)?
    private var fallback: UNMutableNotificationContent?
    private var task: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        #if DEBUG
        NSLog("OPENCODE_NSE_DID_RECEIVE")
        try? PushSnapshotStore.appGroup().markNSEInvocation()
        #endif
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { contentHandler(request.content); return }
        content.categoryIdentifier = NotificationCategories.openOnly
        content.userInfo.removeValue(forKey: "shownReceipt")
        content.userInfo.removeValue(forKey: "shownID"); content.userInfo.removeValue(forKey: "route")
        let data = try? JSONSerialization.data(withJSONObject: content.userInfo["oc"] ?? [:])
        let generic = NotificationPresentation(title: content.title, body: content.body)
        lock.withLock {
            fallback = content; completion = contentHandler
            task = Task { [weak self] in
                guard let store = try? PushSnapshotStore.appGroup(), let data else { self?.finish(nil); return }
                let keys = PushKeyStore.keychain(accessGroup: Bundle.main.object(forInfoDictionaryKey: "OCKeychainGroup") as? String)
                let result = await NotificationContentBuilder.process(data: data, generic: generic, store: store, keys: keys)
                if !Task.isCancelled { self?.finish(result) }
            }
        }
    }
    override func serviceExtensionTimeWillExpire() {
        finish(nil, expired: true)
    }
    private func finish(_ presentation: NotificationPresentation?, expired: Bool = false) {
        let delivery: (((UNNotificationContent) -> Void), UNNotificationContent)? = lock.withLock {
            if expired { task?.cancel() }
            guard let handler = completion, let content = fallback else { return nil }
            completion = nil; fallback = nil; task = nil
            presentation?.apply(to: content)
            return (handler, content)
        }
        if let (handler, content) = delivery {
            if presentation?.clearsBadge == true { UNUserNotificationCenter.current().setBadgeCount(0) }
            handler(content)
        }
    }
    deinit { task?.cancel() }
}

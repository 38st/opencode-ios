#if os(iOS)
import Foundation
import OCIntents
import OCModels
import OCNetworking
import OCPushCore
import OCShared
import UIKit
import UserNotifications

/// Shared initialization also supports an action or LiveActivityIntent cold-starting the app. Every window shares
/// the one registry, however many scenes connect at once.
@MainActor public enum ApplicationServices {
    private static let shared = SharedOnce<ServerRegistry> {
        let registry = try await ServerRegistry.live()
        await registry.load()
        return registry
    }
    public static func registry() async throws -> ServerRegistry { try await shared.value() }
    /// The windows of this process: deep-link routing, key-window gating and the app-wide scene phase.
    public static let windows = WindowCoordinator()
    /// Links from Shortcuts, Spotlight and the controls, for the windows to route.
    public static let links = LinkInbox()
    /// The intents' work in this process; a cold start by an intent loads the registry first.
    static let intents = IntentActions(registry: { try await ApplicationServices.registry() }, links: links)
    /// Refreshes Siri's parameter phrases; the app sets it to its App Shortcuts provider's update.
    public static var appShortcutsChanged: @MainActor () -> Void = {}
}

@MainActor public final class MobileAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    public override init() { super.init() }
    deinit { for task in tasks.values { task.cancel() } }
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCategories.register()
        UNUserNotificationCenter.current().delegate = self
        IntentEnvironment.app = ApplicationServices.intents
        SessionIntentHandler.stop = { serverID, sessionID in
            let registry = try await ApplicationServices.registry()
            guard let server = registry.servers.first(where: { $0.id.rawValue.uuidString == serverID }),
                  let api = try await server.readPath.client?() else { throw CancellationError() }
            _ = try await api.send(WriteEndpoints.interrupt(sessionID))
        }
        own {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            #if !targetEnvironment(simulator)
            if [.authorized, .provisional, .ephemeral].contains(status) { application.registerForRemoteNotifications() }
            #else
            _ = status
            #endif
            #if targetEnvironment(simulator)
            if let registry = try? await ApplicationServices.registry() { if registry.notifications?.registration.isRelayRegistered != true { registry.notifications?.registration.unavailable() } }
            #endif
        }
        return true
    }
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        own { if let registry = try? await ApplicationServices.registry() { await registry.notifications?.registered(token: deviceToken) } }
    }
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        own { if let registry = try? await ApplicationServices.registry() { registry.notifications?.registration.unavailable() } }
    }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if let registry = try? await ApplicationServices.registry() {
            for server in registry.servers { registry.notifications?.changed(server); await server.reconnect(rerace: false) }
        }
        return []
    }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let identifier = response.notification.request.identifier
        let envelope = try? JSONSerialization.data(withJSONObject: content.userInfo["oc"] ?? [:])
        let receipt = content.userInfo["shownReceipt"] as? String
        let shownID = content.userInfo["shownID"] as? String
        let route = content.userInfo["route"] as? String
        let action = NotificationAction.ID(rawValue: response.actionIdentifier) ?? .open
        let text = (response as? UNTextInputNotificationResponse)?.userText
        do {
            try await withActionDeadline(seconds: .seconds(29)) {
                let registry = try await ApplicationServices.registry()
                try Task.checkCancellation()
                await self.handle(registry, shownID: shownID, receipt: receipt, route: route, envelope: envelope, action: action, text: text, identifier: identifier)
            }
        } catch { await feedback(localized("Couldn't reach your server"), replacing: identifier, route: route) }
    }
    private func handle(_ registry: ServerRegistry, shownID: String?, receipt: String?, route: String?, envelope: Data?, action: NotificationAction.ID, text: String?, identifier: String) async {
        guard let push = registry.notifications else { return }
        if action == .open {
            if let route, let url = URL(string: route), DeepLink(url: url) != nil { push.incomingURL = url }
            else if let shownID, let shown = try? push.registration.store.shown(shownID) { push.incomingURL = shown.url }
            else if let envelope {
                // A raw alert the NSE never opened: derive the route only, writing no shown record or pending count.
                push.incomingURL = await NotificationContentBuilder.route(data: envelope, store: push.registration.store, keys: push.registration.keys)
            }
            return
        }
        let result = await push.handler.handle(shownID: shownID ?? "", receipt: receipt, route: route, action: action, text: text)
        await feedback(result, replacing: identifier, route: route)
        push.reloadAudit()
    }
    private func feedback(_ message: String, replacing id: String, route: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = "Opencode"; content.body = message; content.categoryIdentifier = NotificationCategories.openOnly
        if let route, let url = URL(string: route), DeepLink(url: url) != nil { content.userInfo["route"] = route }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        try? await UNUserNotificationCenter.current().add(.init(identifier: id, content: content, trigger: nil))
    }
    private func own(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in await operation(); self?.tasks.removeValue(forKey: id) }
    }
}
#endif

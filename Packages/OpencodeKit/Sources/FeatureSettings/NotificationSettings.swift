#if os(iOS)
import SwiftUI
import OCDesign
import OCSync
import OCShared

public struct NotificationSettings: View {
    @Bindable var controller: PushController
    private let refreshOnAppear: Bool
    public init(controller: PushController, refreshOnAppear: Bool = true) {
        self.controller = controller; self.refreshOnAppear = refreshOnAppear
    }
    public var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text("Notifications").font(OCType.title)
                Text("Stay connected when you leave the app.").font(OCType.body).foregroundStyle(OCColor.textMuted)
            }
            OCCard { VStack(alignment: .leading, spacing: OCSpacing.lg) {
                status("System permission", controller.permission)
                status("Relay", controller.registration.relayState)
                if !controller.registration.pendingRevocations.isEmpty {
                    status("Removed servers", "Revocation pending for \(controller.registration.pendingRevocations.count); retried at the next launch")
                }
                Button("Enable notifications") { Task { await controller.enable() } }
                    .buttonStyle(OCButtonStyle()).accessibilityIdentifier("enableNotifications")
            } }
            Text("Lock-screen approvals").font(OCType.heading)
            OCSegmentedControl("Lock-screen approvals", options: [(true, "On, with risk tiers"), (false, "Open only")],
                selection: Binding(get: { controller.preferences.lockScreenApprovals }, set: { controller.setApprovals($0) }))
                .accessibilityIdentifier("lockScreenApprovals")
            Text("Allow once requires unlocking. High-risk requests must be reviewed in the app.")
                .font(OCType.small).foregroundStyle(OCColor.textMuted)
            OCToggleRow("Live Activity", detail: "Show progress for prompts you send from this phone.",
                        isOn: Binding(get: { controller.preferences.liveActivities }, set: { controller.setLiveActivities($0) }))
                .accessibilityIdentifier("liveActivityToggle")
            ForEach(controller.health) { server in
                OCCard { VStack(alignment: .leading, spacing: OCSpacing.lg) {
                    Text(server.name).font(OCType.heading)
                    status("Plugin", server.pluginVersion.map { "Installed · " + $0 } ?? (server.pluginMissing ? "Not installed" : "Checking"))
                    status("Registration", server.registration)
                    status("Last delivery", server.lastDelivery ?? "None yet")
                    if let date = server.lastDeliveryAt { Text(date, style: .relative).font(OCType.small).foregroundStyle(OCColor.textMuted) }
                    if server.pluginMissing { Text(controller.installCommand).font(OCType.code).textSelection(.enabled) }
                    Button("Send test push") { Task { await controller.test(server: server.id) } }
                        .buttonStyle(OCButtonStyle()).disabled(server.registration != "Registered")
                        .accessibilityIdentifier("testPush-" + server.id)
                } }
            }
            if let error = controller.error { Text(error).font(OCType.body).foregroundStyle(OCColor.textMuted) }
            Text("Notification decisions").font(OCType.heading)
            if controller.audit.isEmpty { Text("Decisions made from notifications appear here.").font(OCType.body).foregroundStyle(OCColor.textMuted) }
            ForEach(controller.audit) { entry in
                OCCard { VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text(entry.result).font(OCType.body)
                    Text(controller.health.first(where: { $0.id == entry.server })?.name ?? (entry.server.isEmpty ? "Unknown server" : entry.server)).font(OCType.small)
                    Text(entry.requestID).font(OCType.code).textSelection(.enabled)
                    Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized).font(OCType.small).foregroundStyle(OCColor.textMuted)
                    Text(entry.date, format: .dateTime.month().day().hour().minute()).font(OCType.small).foregroundStyle(OCColor.textMuted)
                } }
            }
        }
        .ocNavigationTitle("Notifications")
        .task { if refreshOnAppear { await controller.refresh() } }
        .refreshable { await controller.refresh() }
    }
    private func status(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            Text(title).font(OCType.small).foregroundStyle(OCColor.textMuted)
            Text(value).font(OCType.body)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

#if os(iOS)
import SwiftUI
import OCDesign
import OCSync
import OCShared

public struct NotificationSettings: View {
    @Bindable var controller: PushController
    private let refreshOnAppear: Bool
    @State private var confirmApprovalsOff = false
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
            categories
            quietHours
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
    private static let kinds = [("permission", "Approvals", "Requests to run commands or edit files."),
                                ("question", "Questions", "A session needs your answer."),
                                ("finished", "Finished sessions", "A session finished its work."),
                                ("failed", "Failed sessions", "A session stopped with an error.")]
    @ViewBuilder private var categories: some View {
        Text("Notify me about").font(OCType.heading)
        ForEach(Self.kinds, id: \.0) { kind, title, detail in
            OCToggleRow(title, detail: detail, isOn: Binding(get: { !controller.preferences.silencedKinds.contains(kind) }, set: { on in
                if !on && kind == "permission" { confirmApprovalsOff = true } else { controller.setNotifications(kind, enabled: on) }
            })).accessibilityIdentifier("notify-" + kind)
        }
        Text("Turned-off notifications still arrive in Notification Center, without sound or banner. Muted sessions do the same, except approvals.")
            .font(OCType.small).foregroundStyle(OCColor.textMuted)
            .sheet(isPresented: $confirmApprovalsOff) {
                OCConfirmationSheet("Turn off approval notifications?", message: "Sessions waiting for your approval will no longer alert you, on every server, including at night. They stay in Notification Center.",
                                    confirmTitle: "Turn off", cancel: { confirmApprovalsOff = false }) {
                    controller.setNotifications("permission", enabled: false); confirmApprovalsOff = false
                }.ocSheet()
            }
        if !controller.preferences.mutedSessions.isEmpty {
            OCCard { VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text("Muted sessions: \(controller.preferences.mutedSessions.count)").font(OCType.body)
                Text("Unmute a session from its menu.").font(OCType.small).foregroundStyle(OCColor.textMuted)
            } }.accessibilityIdentifier("mutedSessions")
        }
    }
    @ViewBuilder private var quietHours: some View {
        Text("Quiet hours").font(OCType.heading)
        OCToggleRow("Quiet hours", detail: "Lower the alert level during these hours. Approvals keep theirs.",
                    isOn: Binding(get: { controller.preferences.quietHours != nil }, set: { on in
            controller.setQuietHours(on ? QuietHours(start: 22 * 60, end: 7 * 60) : nil)
        })).accessibilityIdentifier("quietHoursToggle")
        if let quiet = controller.preferences.quietHours {
            DatePicker("From", selection: Binding(get: { Self.date(quiet.start) }, set: { controller.setQuietHours(QuietHours(start: Self.minutes($0), end: quiet.end)) }), displayedComponents: .hourAndMinute)
                .font(OCType.body).accessibilityIdentifier("quietHoursStart")
            DatePicker("Until", selection: Binding(get: { Self.date(quiet.end) }, set: { controller.setQuietHours(QuietHours(start: quiet.start, end: Self.minutes($0))) }), displayedComponents: .hourAndMinute)
                .font(OCType.body).accessibilityIdentifier("quietHoursEnd")
        }
    }
    private static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(timeIntervalSince1970: 0)) ?? .now
    }
    private static func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    private func status(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            Text(title).font(OCType.small).foregroundStyle(OCColor.textMuted)
            Text(value).font(OCType.body)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

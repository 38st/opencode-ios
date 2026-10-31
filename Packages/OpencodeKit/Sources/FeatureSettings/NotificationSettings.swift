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
                Text(localized("Notifications")).font(OCType.title)
                Text(localized("Stay connected when you leave the app.")).font(OCType.body).foregroundStyle(OCColor.textMuted)
            }
            OCCard { VStack(alignment: .leading, spacing: OCSpacing.lg) {
                status(localized("System permission"), controller.permission)
                status(localized("Relay", comment: "Push notification relay server"), controller.registration.relayState)
                if !controller.registration.pendingRevocations.isEmpty {
                    status(localized("Removed servers"), localized("Revocation pending for \(controller.registration.pendingRevocations.count); retried at the next launch", comment: "%lld is the number of removed servers"))
                }
                Button(localized("Enable notifications")) { Task { await controller.enable() } }
                    .buttonStyle(OCButtonStyle()).accessibilityIdentifier("enableNotifications")
            } }
            Text(localized("Lock-screen approvals")).font(OCType.heading)
            OCSegmentedControl(localized("Lock-screen approvals"), options: [(true, localized("On, with risk tiers")), (false, localized("Open only", comment: "Approvals can only be opened, not answered, from the lock screen"))],
                selection: Binding(get: { controller.preferences.lockScreenApprovals }, set: { controller.setApprovals($0) }))
                .accessibilityIdentifier("lockScreenApprovals")
            Text(localized("Allow once requires unlocking. High-risk requests must be reviewed in the app."))
                .font(OCType.small).foregroundStyle(OCColor.textMuted)
            OCToggleRow(localized("Live Activity"), detail: localized("Show progress for prompts you send from this phone."),
                        isOn: Binding(get: { controller.preferences.liveActivities }, set: { controller.setLiveActivities($0) }))
                .accessibilityIdentifier("liveActivityToggle")
            categories
            quietHours
            ForEach(controller.health) { server in
                OCCard { VStack(alignment: .leading, spacing: OCSpacing.lg) {
                    Text(server.name).font(OCType.heading)
                    status(localized("Plugin"), server.pluginVersion.map { localized("Installed · \($0)", comment: "%@ is the plugin version") } ?? (server.pluginMissing ? localized("Not installed") : localized("Checking")))
                    status(localized("Registration"), server.registration)
                    status(localized("Last delivery"), server.lastDelivery ?? localized("None yet"))
                    if let date = server.lastDeliveryAt { Text(date, style: .relative).font(OCType.small).foregroundStyle(OCColor.textMuted) }
                    if server.pluginMissing { Text(controller.installCommand).font(OCType.code).textSelection(.enabled) }
                    Button(localized("Send test push")) { Task { await controller.test(server: server.id) } }
                        .buttonStyle(OCButtonStyle()).disabled(!server.isRegistered)
                        .accessibilityIdentifier("testPush-" + server.id)
                } }
            }
            if let error = controller.error { Text(error).font(OCType.body).foregroundStyle(OCColor.textMuted) }
            Text(localized("Notification decisions")).font(OCType.heading)
            if controller.audit.isEmpty { Text(localized("Decisions made from notifications appear here.")).font(OCType.body).foregroundStyle(OCColor.textMuted) }
            ForEach(controller.audit) { entry in
                OCCard { VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text(entry.result).font(OCType.body)
                    Text(controller.health.first(where: { $0.id == entry.server })?.name ?? (entry.server.isEmpty ? localized("Unknown server") : entry.server)).font(OCType.small)
                    Text(entry.requestID).font(OCType.code).textSelection(.enabled)
                    Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized).font(OCType.small).foregroundStyle(OCColor.textMuted)
                    Text(entry.date, format: .dateTime.month().day().hour().minute()).font(OCType.small).foregroundStyle(OCColor.textMuted)
                } }
            }
        }
        .ocNavigationTitle(localized("Notifications"))
        .task { if refreshOnAppear { await controller.refresh() } }
        .refreshable { await controller.refresh() }
    }
    private static var kinds: [(String, String, String)] {
        [("permission", localized("Approvals"), localized("Requests to run commands or edit files.")),
         ("question", localized("Questions"), localized("A session needs your answer.")),
         ("finished", localized("Finished sessions"), localized("A session finished its work.")),
         ("failed", localized("Failed sessions"), localized("A session stopped with an error."))]
    }
    @ViewBuilder private var categories: some View {
        Text(localized("Notify me about")).font(OCType.heading)
        ForEach(Self.kinds, id: \.0) { kind, title, detail in
            OCToggleRow(title, detail: detail, isOn: Binding(get: { !controller.preferences.silencedKinds.contains(kind) }, set: { on in
                if !on && kind == "permission" { confirmApprovalsOff = true } else { controller.setNotifications(kind, enabled: on) }
            })).accessibilityIdentifier("notify-" + kind)
        }
        Text(localized("Turned-off notifications still arrive in Notification Center, without sound or banner. Muted sessions do the same, except approvals."))
            .font(OCType.small).foregroundStyle(OCColor.textMuted)
            .sheet(isPresented: $confirmApprovalsOff) {
                OCConfirmationSheet(localized("Turn off approval notifications?"), message: localized("Sessions waiting for your approval will no longer alert you, on every server, including at night. They stay in Notification Center."),
                                    confirmTitle: localized("Turn off"), cancel: { confirmApprovalsOff = false }) {
                    controller.setNotifications("permission", enabled: false); confirmApprovalsOff = false
                }.ocSheet()
            }
        if !controller.preferences.mutedSessions.isEmpty {
            OCCard { VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text(localized("Muted sessions: \(controller.preferences.mutedSessions.count)", comment: "%lld is the number of muted sessions")).font(OCType.body)
                Text(localized("Unmute a session from its menu.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
            } }.accessibilityIdentifier("mutedSessions")
        }
    }
    @ViewBuilder private var quietHours: some View {
        Text(localized("Quiet hours")).font(OCType.heading)
        OCToggleRow(localized("Quiet hours"), detail: localized("Lower the alert level during these hours. Approvals keep theirs."),
                    isOn: Binding(get: { controller.preferences.quietHours != nil }, set: { on in
            controller.setQuietHours(on ? QuietHours(start: 22 * 60, end: 7 * 60) : nil)
        })).accessibilityIdentifier("quietHoursToggle")
        if let quiet = controller.preferences.quietHours {
            DatePicker(localized("From", comment: "Start time of quiet hours"), selection: Binding(get: { Self.date(quiet.start) }, set: { controller.setQuietHours(QuietHours(start: Self.minutes($0), end: quiet.end)) }), displayedComponents: .hourAndMinute)
                .font(OCType.body).accessibilityIdentifier("quietHoursStart")
            DatePicker(localized("Until", comment: "End time of quiet hours"), selection: Binding(get: { Self.date(quiet.end) }, set: { controller.setQuietHours(QuietHours(start: quiet.start, end: Self.minutes($0))) }), displayedComponents: .hourAndMinute)
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

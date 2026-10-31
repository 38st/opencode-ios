#if os(iOS)
import SwiftUI
import OCDesign
import OCModels
import OCSync
import FeatureSettings
import FeatureTerminal

struct ServerSettingsView: View {
    /// The app's version and build; snapshots pass a fixed one, since a test host reports its own.
    var appVersion = ServerSettingsView.bundleVersion
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        return (info?["CFBundleVersion"] as? String).map { localized("\(version) (\($0))", comment: "App version, then build number") } ?? version
    }
    let registry: ServerRegistry
    var addOnOpen = false
    /// Opens straight into one server's settings section.
    var section: (ServerID, ServerSettingsSection)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("followUpBehavior") private var followUp = "steer"
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("changedFiles") private var changedFiles = true
    @AppStorage("showAgent") private var showAgent = false
    @AppStorage(TerminalSettings.fontSizeKey) private var terminalFontSize = TerminalSettings.defaultFontSize
    @AppStorage(TerminalSettings.optionAsMetaKey) private var optionAsMeta = true
    @State private var adding = false
    @State private var repairing: ServerStore?
    @State private var shownRepair: Set<ServerID> = []
    @State private var selection: ServerID?
    @State private var sectionRoute: SectionRoute?
    private struct SectionRoute: Hashable { let server: ServerID; let section: ServerSettingsSection }
    var body: some View {
        NavigationStack {
            OCForm {
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text(localized("Servers")).font(OCType.title).accessibilityAddTraits(.isHeader)
                    Text(localized("Manage server connections")).foregroundStyle(OCColor.textMuted)
                }
                if let controller = registry.notifications {
                    NavigationLink { NotificationSettings(controller: controller) } label: { OCLabel(localized("Notifications"), icon: "notifications").frame(minHeight: OCLayout.touchTarget, alignment: .leading).contentShape(Rectangle()) }
                        .font(OCType.body).accessibilityIdentifier("notificationSettings")
                }
                ForEach(registry.servers) { server in
                    Button { selection = server.id } label: {
                        OCCard {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                ServerRow(name: server.record.name, state: server.state, endpoints: server.record.endpoints,
                                          expiresSoon: server.tokenExpiresSoon)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("serverRow")
                        .accessibilityHint(localized("Open server details and connection diagnostics"))
                }
                Button { adding = true } label: { OCLabel(localized("Add server"), icon: "plus") }
                    .buttonStyle(OCButtonStyle()).accessibilityIdentifier("addServer")
                Text(localized("Your credentials stay in this device’s Keychain.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                OCSection(localized("App", comment: "Settings section for app-wide preferences")) {
                    followUpRow
                    OCToggleRow(localized("Wrap lines"), detail: localized("Wrap long lines in diffs and files."), isOn: $wrapLines)
                    OCToggleRow(localized("Changed files"), detail: localized("List the files each turn changed when it finishes."), isOn: $changedFiles)
                    OCToggleRow(localized("Show agent"), detail: localized("Switch between agents in the composer. When hidden, defaults to Build agent."), isOn: $showAgent)
                        .accessibilityIdentifier("showAgent")
                }
                OCSection(localized("Terminal")) {
                    terminalFontRow
                    OCToggleRow(localized("Option as Meta", comment: "Terminal setting: the Option key acts as the Meta key"), detail: localized("With a hardware keyboard, Option sends Escape before the key, as shell and editor shortcuts expect. Turn it off to type the characters your keyboard puts on Option."),
                                isOn: $optionAsMeta).accessibilityIdentifier("terminalOptionAsMeta")
                }
                if let system = registry.system { SystemIntegrationSection(system: system) }
                OCSection(localized("About")) {
                    LabeledContent(localized("Version"), value: appVersion)
                    LabeledContent(localized("Works with", comment: "Row label; the value is the oldest supported opencode version"),
                                   value: localized("opencode \(ServerInfo.minimumVersion) or later"))
                        .accessibilityIdentifier("minimumServerVersion")
                    NavigationLink { AcknowledgementsView() } label: { OCLabel(localized("Acknowledgements"), icon: "info") }
                        .font(OCType.body).accessibilityIdentifier("acknowledgements")
                }
            }
            .ocNavigationTitle(localized("Settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localized("Done")) { dismiss() }.accessibilityIdentifier("closeSettings") } }
            .navigationDestination(item: $selection) { id in
                if let server = registry.servers.first(where: { $0.id == id }) {
                    ServerDetailView(registry: registry, server: server) { repairing = server }
                }
            }
            .navigationDestination(item: $sectionRoute) { route in
                if let server = registry.servers.first(where: { $0.id == route.server }) {
                    ServerAdminView(server: server, section: route.section)
                }
            }
            .refreshable { await registry.refresh() }
        }.ocTheme().uiTestConnectionDiagnostics(registry)
            .sheet(isPresented: $adding, onDismiss: presentRepair) {
                AddServerView(registry: registry) { server in
                    adding = false
                    if case .incompatible = server.state { selection = server.id }
                }
            }
            .sheet(item: $repairing) { server in
                AddServerView(registry: registry, repairing: server) { _ in repairing = nil }
            }
            .onChange(of: registry.servers.filter { $0.needsRepair }.map { $0.id }) { _, _ in presentRepair() }
            .task {
                if addOnOpen { adding = true }
                else if let section { sectionRoute = .init(server: section.0, section: section.1) }
                else { presentRepair() }
            }
    }
    /// A menu Picker outside a Form draws no label, so the title and explanation sit beside it.
    private var followUpRow: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.sm))
            : AnyLayout(HStackLayout(spacing: OCSpacing.sm))
        return layout {
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text(localized("Follow-up behavior")).font(OCType.body)
                Text(localized("While the agent is working, Steer adds your message to the current run; Queue sends it after the run finishes."))
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            Picker(localized("Follow-up behavior"), selection: $followUp) {
                Text(localized("Steer", comment: "Follow-up option: add the message to the current run")).tag("steer")
                Text(localized("Queue", comment: "Follow-up option: send the message after the run")).tag("queue")
            }.pickerStyle(.menu).labelsHidden().font(OCType.body).frame(minHeight: OCLayout.touchTarget)
                .accessibilityLabel(localized("Follow-up behavior"))
                .accessibilityHint(localized("While the agent is working, Steer adds your message to the current run; Queue sends it after the run finishes."))
                .accessibilityIdentifier("followUpBehavior")
        }
    }
    /// The terminal's own size: it does not follow the system text size, so programs keep their columns.
    private var terminalFontRow: some View {
        Stepper(value: $terminalFontSize, in: TerminalSettings.fontSizes, step: 1) {
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text(localized("Font size")).font(OCType.body)
                Text(localized("\(Int(terminalFontSize)) points, in terminals only.", comment: "%lld is the terminal font size")).font(OCType.small).foregroundStyle(OCColor.textMuted)
            }
        }.frame(minHeight: OCLayout.touchTarget).accessibilityIdentifier("terminalFontSize")
    }
    private func presentRepair() {
        guard !adding, repairing == nil,
              let server = registry.servers.first(where: { $0.needsRepair && !shownRepair.contains($0.id) }) else { return }
        shownRepair.insert(server.id); repairing = server
    }
}
#endif

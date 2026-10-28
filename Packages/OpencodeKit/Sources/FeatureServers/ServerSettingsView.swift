#if os(iOS)
import SwiftUI
import OCDesign
import OCModels
import OCSync
import FeatureSettings

struct ServerSettingsView: View {
    let registry: ServerRegistry
    var addOnOpen = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("followUpBehavior") private var followUp = "steer"
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("changedFiles") private var changedFiles = true
    @AppStorage("showAgent") private var showAgent = false
    @State private var adding = false
    @State private var repairing: ServerStore?
    @State private var shownRepair: Set<ServerID> = []
    @State private var selection: ServerID?
    var body: some View {
        NavigationStack {
            OCForm {
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text("Servers").font(OCType.title).accessibilityAddTraits(.isHeader)
                    Text("Manage server connections").foregroundStyle(OCColor.textMuted)
                }
                if let controller = registry.notifications {
                    NavigationLink { NotificationSettings(controller: controller) } label: { OCLabel("Notifications", icon: "notifications") }
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
                        .accessibilityHint("Open server details and connection diagnostics")
                }
                Button { adding = true } label: { OCLabel("Add server", icon: "plus") }
                    .buttonStyle(OCButtonStyle()).accessibilityIdentifier("addServer")
                Text("Your credentials stay in this device’s Keychain.").font(OCType.small).foregroundStyle(OCColor.textMuted)
                OCSection("App") {
                    followUpRow
                    OCToggleRow("Wrap lines", detail: "Wrap long lines in diffs and files.", isOn: $wrapLines)
                    OCToggleRow("Changed files", detail: "List the files each turn changed when it finishes.", isOn: $changedFiles)
                    OCToggleRow("Show agent", detail: "Switch between agents in the composer. When hidden, defaults to Build agent.", isOn: $showAgent)
                        .accessibilityIdentifier("showAgent")
                }
                if let system = registry.system { SystemIntegrationSection(system: system) }
            }
            .ocNavigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("closeSettings") } }
            .navigationDestination(item: $selection) { id in
                if let server = registry.servers.first(where: { $0.id == id }) {
                    ServerDetailView(registry: registry, server: server) { repairing = server }
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
            .task { if addOnOpen { adding = true } else { presentRepair() } }
    }
    /// A menu Picker outside a Form draws no label, so the title and explanation sit beside it.
    private var followUpRow: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.sm))
            : AnyLayout(HStackLayout(spacing: OCSpacing.sm))
        return layout {
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text("Follow-up behavior").font(OCType.body)
                Text("While the agent is working, Steer adds your message to the current run; Queue sends it after the run finishes.")
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            Picker("Follow-up behavior", selection: $followUp) {
                Text("Steer").tag("steer")
                Text("Queue").tag("queue")
            }.pickerStyle(.menu).labelsHidden().font(OCType.body).frame(minHeight: OCLayout.touchTarget)
                .accessibilityLabel("Follow-up behavior")
                .accessibilityHint("While the agent is working, Steer adds your message to the current run; Queue sends it after the run finishes.")
                .accessibilityIdentifier("followUpBehavior")
        }
    }
    private func presentRepair() {
        guard !adding, repairing == nil,
              let server = registry.servers.first(where: { $0.needsRepair && !shownRepair.contains($0.id) }) else { return }
        shownRepair.insert(server.id); repairing = server
    }
}
#endif

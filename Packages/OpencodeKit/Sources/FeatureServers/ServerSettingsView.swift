#if os(iOS)
import SwiftUI
import OCDesign
import OCModels
import OCSync

struct ServerSettingsView: View {
    let registry: ServerRegistry
    var addOnOpen = false
    @Environment(\.dismiss) private var dismiss
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
                    Text("Servers").font(OCType.title)
                    Text("Manage server connections").foregroundStyle(OCColor.textMuted)
                }
                Text("App").font(OCType.heading)
                Picker("Follow-up behavior", selection: $followUp) {
                    Text("Steer").tag("steer")
                    Text("Queue").tag("queue")
                }.font(OCType.body).accessibilityIdentifier("followUpBehavior")
                Toggle("Wrap lines", isOn: $wrapLines).font(OCType.body)
                Toggle("Changed files", isOn: $changedFiles).font(OCType.body)
                Text("List the files each turn changed when it finishes").font(OCType.small).foregroundStyle(OCColor.textMuted)
                Toggle("Show agent", isOn: $showAgent).font(OCType.body).accessibilityIdentifier("showAgent")
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
    private func presentRepair() {
        guard !adding, repairing == nil,
              let server = registry.servers.first(where: { $0.needsRepair && !shownRepair.contains($0.id) }) else { return }
        shownRepair.insert(server.id); repairing = server
    }
}
#endif

#if os(iOS)
import SwiftUI
import OCDesign
import UIKit
import OCModels
import OCSync

struct ServerDetailView: View {
    let registry: ServerRegistry
    @Bindable var server: ServerStore
    let repair: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var endpoint = ""
    @State private var error: String?
    @State private var removing = false
    @State private var task: Task<Void, Never>?
    @State private var explainLocal = false
    @State private var showingConnectionDetails = false
    var body: some View {
        Group {
            if case .incompatible(let outcome) = server.state, !showingConnectionDetails {
                UpdateServerView(server: server, outcome: outcome)
            } else {
                OCForm {
                    OCSection("Server") {
                        TextField("Name", text: $name).onSubmit { perform { try await registry.rename(server, to: name) } }
                        Button("Save name") { perform { try await registry.rename(server, to: name) } }
                            .buttonStyle(OCButtonStyle())
                            .disabled(name == server.record.name || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        LabeledContent("Version", value: server.version ?? "Checking…")
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            StatusPill(status: .init(state: server.state, endpoints: server.record.endpoints))
                        }
                        if server.needsRepair { Button("Pair again", action: repair).buttonStyle(OCButtonStyle()) }
                        if server.record.endpoints.contains(where: { $0.stats.lastFailure == .localNetworkDenied }),
                           let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link("Allow Local Network access in Settings", destination: settings)
                                .buttonStyle(OCButtonStyle())
                        }
                        if let error = server.persistenceError { Text(error).foregroundStyle(OCColor.danger) }
                    }
                    if server.tokenExpiresSoon {
                        OCSection {
                            OCLabel("Your pairing token expires within 5 days.", icon: "lock")
                            Button("Pair again", action: repair).buttonStyle(OCButtonStyle())
                        }
                    }
                    OCSection("Endpoints") {
                        ForEach(server.record.endpoints) { entry in
                            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                                Text(entry.url.absoluteString).textSelection(.enabled).font(OCType.body)
                                Text(entry.kind.label + " · " + server.diagnosis(for: entry.id)).font(OCType.body).foregroundStyle(OCColor.textMuted)
                                if entry.url.scheme == "http" { OCLabel("Unencrypted", icon: "lock").font(OCType.small) }
                                if let success = entry.stats.lastSuccess { Text("Last healthy: \(success.formatted())").font(OCType.small).foregroundStyle(OCColor.textMuted) }
                                Button("Remove endpoint", role: .destructive) {
                                    perform { try await server.replaceEndpoints(server.record.endpoints.filter { $0.id != entry.id }) }
                                }
                                .buttonStyle(OCButtonStyle(.danger))
                                .disabled(server.record.endpoints.count == 1)
                                .accessibilityLabel("Remove endpoint \(entry.url.host ?? "server")")
                            }.padding(.vertical, OCSpacing.xs)
                        }
                        TextField("New endpoint URL", text: $endpoint).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Add endpoint") {
                            if registry.needsLocalNetworkExplanation(address: endpoint, pairing: false) { explainLocal = true }
                            else { addEndpoint() }
                        }.buttonStyle(OCButtonStyle()).disabled(endpoint.isEmpty)
                    }
                    OCSection("Capabilities") {
                        LabeledContent("Pairing", value: server.capabilities.pairing ? "Available" : "Needs 2.0.25")
                        if !server.capabilities.pairing { Text(ServerCapabilities.pairingRequirement).font(OCType.small) }
                        LabeledContent("Persistent terminal", value: server.capabilities.persistentPty ? "Available" : "Unavailable")
                    }
                    OCSection {
                        NavigationLink("Connection diagnostics") { DiagnosticsView(server: server) }
                            .buttonStyle(OCButtonStyle(.ghost))
                        Button { perform { await server.reconnect() } } label: { OCLabel("Reconnect", icon: "refresh") }
                            .buttonStyle(OCButtonStyle())
                    }
                }
            }
        }
        .ocTheme()
        .ocNavigationTitle(server.record.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .incompatible = server.state {
                ToolbarItem(placement: .secondaryAction) {
                    Button(showingConnectionDetails ? "Update instructions" : "Server details") { showingConnectionDetails.toggle() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                OCIconButton("Remove server", icon: "trash", role: .destructive) { removing = true }
            }
        }
        .confirmationDialog("Remove this server and its saved credential?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove server", role: .destructive) { perform { try await registry.remove(server); dismiss() } }
        }
        .alert("Could not complete action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $explainLocal) {
            LocalNetworkExplanation {
                explainLocal = false
                perform { await registry.acknowledgeLocalNetwork(); try await appendEndpoint() }
            }
        }
        .onAppear { name = server.record.name }
        .onDisappear { task?.cancel() }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        task?.cancel()
        task = Task { do { try await action() } catch { self.error = ServerRegistry.errorMessage(error) } }
    }
    private func addEndpoint() { perform { try await appendEndpoint() } }
    private func appendEndpoint() async throws {
        let entry = try ServerRegistry.endpoint(endpoint)
        guard !server.record.endpoints.contains(where: { $0.url == entry.url }) else { endpoint = ""; return }
        try await server.replaceEndpoints(server.record.endpoints + [entry]); endpoint = ""
    }
}

struct UpdateServerView: View {
    let server: ServerStore
    let outcome: ProbeOutcome
    @State private var task: Task<Void, Never>?
    @State private var copied: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.xl) {
                OCIcon("arrow-up", size: 32).font(OCType.title).foregroundStyle(OCColor.iconMuted).accessibilityHidden(true)
                Text(title).font(OCType.title).accessibilityIdentifier("updateTitle")
                Text(explanation)
                if case .v1 = outcome {
                    command("opencode upgrade")
                    Text("Then upgrade to opencode 2:")
                    command("opencode upgrade --major")
                    Text("The --major option needs opencode 1.19.0 or later. Run the first command to update V1 before using it.")
                        .foregroundStyle(OCColor.textMuted)
                } else if case .unsupportedV2 = outcome { command("opencode upgrade") }
                Button { task?.cancel(); task = Task { await server.reconnect() } } label: { OCLabel("Check again", icon: "refresh") }
                    .buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("checkAgain")
                if let copied { Text("Copied \(copied)").font(OCType.small) }
            }.padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
        }.ocTheme().onDisappear { task?.cancel() }
    }
    private var title: String {
        if case .notOpencode = outcome { "Not an opencode server" } else { "Update opencode" }
    }
    private var explanation: String {
        switch outcome {
        case .v1: "This app needs opencode 2. Run these commands on the computer hosting your server."
        case .unsupportedV2: "This server version is not supported. Use opencode 2.0.10 or later. Pairing needs 2.0.25 or later."
        default: "This address did not respond as an opencode server. Check the URL and that opencode serve is running."
        }
    }
    private func command(_ text: String) -> some View {
        OCCodeFrame("Terminal") {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
            Text(text).font(OCType.code).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Button { OCCopy.text(text); copied = text } label: { OCLabel("Copy command", icon: "copy") }
                .buttonStyle(OCButtonStyle(.ghost))
                .accessibilityLabel("Copy \(text)")
            }
        }
    }
}

struct DiagnosticsView: View {
    let server: ServerStore
    var body: some View {
        OCForm {
            OCSection {
                ShareLink("Export diagnostics", item: server.diagnosticsExport())
                    .buttonStyle(OCButtonStyle())
                Text("The export excludes credentials, server names, addresses, paths and event contents.").font(OCType.small)
            }
            OCSection("Last \(server.transitions.count) transitions") {
                ForEach(Array(server.transitions.enumerated()), id: \.offset) { _, transition in
                    Text(server.transitionDescription(transition))
                        .font(OCType.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            OCSection("Resyncs") { Text("\(server.resync?.records.count ?? 0) recorded") }
        }.ocNavigationTitle("Diagnostics").ocTheme()
    }
}
#endif

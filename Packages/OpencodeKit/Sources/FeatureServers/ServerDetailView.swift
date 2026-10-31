#if os(iOS)
import SwiftUI
import OCDesign
import UIKit
import OCModels
import OCSync
import FeatureSettings

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
                    OCSection(localized("Server")) {
                        TextField(localized("Name"), text: $name).onSubmit { perform { try await registry.rename(server, to: name) } }
                        Button(localized("Save name")) { perform { try await registry.rename(server, to: name) } }
                            .buttonStyle(OCButtonStyle())
                            .disabled(name == server.record.name || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        LabeledContent(localized("Version"), value: server.version ?? localized("Checking…"))
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            StatusPill(status: .init(state: server.state, endpoints: server.record.endpoints))
                        }
                        if server.needsRepair { Button(localized("Pair again"), action: repair).buttonStyle(OCButtonStyle()) }
                        if server.record.endpoints.contains(where: { $0.stats.lastFailure == .localNetworkDenied }),
                           let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link(localized("Allow Local Network access in Settings"), destination: settings)
                                .buttonStyle(OCButtonStyle())
                        }
                        if let error = server.persistenceError { Text(error).foregroundStyle(OCColor.danger) }
                    }
                    if server.tokenExpiresSoon {
                        OCSection {
                            OCLabel(localized("Your pairing token expires within 5 days."), icon: "lock")
                            Button(localized("Pair again"), action: repair).buttonStyle(OCButtonStyle())
                        }
                    }
                    OCSection(localized("Endpoints")) {
                        ForEach(server.record.endpoints) { entry in
                            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                                Text(entry.url.absoluteString).font(OCType.body).frame(minHeight: OCLayout.touchTarget, alignment: .leading).contentShape(Rectangle())
                                    .contextMenu { Button(localized("Copy address")) { OCCopy.text(entry.url.absoluteString) } }
                                    .accessibilityAction(named: localized("Copy address")) { OCCopy.text(entry.url.absoluteString) }
                                Text(entry.kind.label + " · " + server.diagnosis(for: entry.id)).font(OCType.body).foregroundStyle(OCColor.textMuted)
                                if entry.url.scheme == "http" { OCLabel(localized("Unencrypted"), icon: "lock").font(OCType.small) }
                                if let success = entry.stats.lastSuccess { Text(localized("Last healthy: \(success.formatted())", comment: "%@ is a date and time")).font(OCType.small).foregroundStyle(OCColor.textMuted) }
                                Button(localized("Remove endpoint"), role: .destructive) {
                                    perform { try await server.replaceEndpoints(server.record.endpoints.filter { $0.id != entry.id }) }
                                }
                                .buttonStyle(OCButtonStyle(.danger))
                                .disabled(server.record.endpoints.count == 1)
                                .accessibilityLabel(entry.url.host.map { localized("Remove endpoint \($0)", comment: "%@ is a host name") } ?? localized("Remove endpoint"))
                            }.padding(.vertical, OCSpacing.xs)
                        }
                        TextField(localized("New endpoint URL"), text: $endpoint).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(localized("Add endpoint")) {
                            if registry.needsLocalNetworkExplanation(address: endpoint, pairing: false) { explainLocal = true }
                            else { addEndpoint() }
                        }.buttonStyle(OCButtonStyle()).disabled(endpoint.isEmpty)
                    }
                    OCSection(localized("Capabilities")) {
                        LabeledContent(localized("Pairing"), value: server.capabilities.pairing ? localized("Available") : localized("Needs \(ServerInfo.minimumVersion)", comment: "%@ is the minimum opencode version"))
                        if !server.capabilities.pairing { Text(ServerCapabilities.pairingRequirement).font(OCType.small) }
                        LabeledContent(localized("Persistent terminal"), value: server.capabilities.persistentPty ? localized("Available") : localized("Unavailable"))
                    }
                    ServerAdminLinks(server: server)
                    OCSection {
                        NavigationLink(localized("Connection diagnostics")) { DiagnosticsView(server: server) }
                            .buttonStyle(OCButtonStyle(.ghost))
                        Button { perform { await server.reconnect() } } label: { OCLabel(localized("Reconnect"), icon: "refresh") }
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
                    Button(showingConnectionDetails ? localized("Update instructions") : localized("Server details")) { showingConnectionDetails.toggle() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                OCIconButton(localized("Remove server"), icon: "trash", role: .destructive) { removing = true }
            }
        }
        .confirmationDialog(localized("Remove this server and its saved credential?"), isPresented: $removing, titleVisibility: .visible) {
            Button(localized("Remove server"), role: .destructive) { perform { try await registry.remove(server); dismiss() } }
        }
        .alert(localized("Could not complete action"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK")) { error = nil }
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
                    Text(localized("Then upgrade to opencode 2:"))
                    command("opencode upgrade --major")
                    Text(localized("The --major option needs opencode 1.19.0 or later. Run the first command to update V1 before using it."))
                        .foregroundStyle(OCColor.textMuted)
                } else if case .unsupportedV2 = outcome { command("opencode upgrade") }
                Button { task?.cancel(); task = Task { await server.reconnect() } } label: { OCLabel(localized("Check again"), icon: "refresh") }
                    .buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("checkAgain")
                if let copied { Text(localized("Copied \(copied)", comment: "%@ is a shell command")).font(OCType.small) }
            }.padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
        }.ocTheme().onDisappear { task?.cancel() }
    }
    private var title: String {
        if case .notOpencode = outcome { localized("Not an opencode server") } else { localized("Update opencode") }
    }
    private var explanation: String {
        switch outcome {
        case .v1: localized("This app needs opencode 2. Run these commands on the computer hosting your server.")
        case .unsupportedV2(let info): localized("This server runs opencode \(info.version). The app needs opencode \(ServerInfo.minimumVersion) or later, which added pairing. Run this command on the computer hosting your server.", comment: "The first %@ is the server's version, the second the oldest supported version")
        default: localized("This address did not respond as an opencode server. Check the URL and that opencode serve is running.")
        }
    }
    private func command(_ text: String) -> some View {
        OCCodeFrame(localized("Terminal", comment: "Label above a shell command")) {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
            Text(text).font(OCType.code).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Button { OCCopy.text(text); copied = text } label: { OCLabel(localized("Copy command"), icon: "copy") }
                .buttonStyle(OCButtonStyle(.ghost))
                .accessibilityLabel(localized("Copy \(text)", comment: "%@ is a shell command"))
            }
        }
    }
}

struct DiagnosticsView: View {
    let server: ServerStore
    var body: some View {
        OCForm {
            OCSection {
                ShareLink(localized("Export diagnostics"), item: server.diagnosticsExport())
                    .buttonStyle(OCButtonStyle())
                Text(localized("The export excludes credentials, server names, addresses, paths and event contents.")).font(OCType.small)
            }
            OCSection(localized("Last \(server.transitions.count) transitions", comment: "%lld is the number of connection state changes")) {
                ForEach(Array(server.transitions.enumerated()), id: \.offset) { _, transition in
                    Text(server.transitionDescription(transition))
                        .font(OCType.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            OCSection(localized("Resyncs")) { Text(localized("\(server.resync?.records.count ?? 0) recorded", comment: "%lld is the number of recorded resyncs")) }
        }.ocNavigationTitle(localized("Diagnostics")).ocTheme()
    }
}
#endif

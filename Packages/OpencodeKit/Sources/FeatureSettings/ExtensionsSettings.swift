#if os(iOS)
import SwiftUI
import OCDesign
import OCFoundation
import OCModels
import OCSync

// Wording: packages/app/src/providers/connect/mcp-dialog.tsx and settings/providers/extensions.tsx at v2.2.1.
struct MCPSection: View {
    @Bindable var admin: ServerAdminModel
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text("MCP servers configured on this server. Their resources can be mentioned with @ in the composer.").foregroundStyle(OCColor.textMuted)
                AdminProjectPicker(admin: admin)
            }
            if let catalog = admin.catalog {
                OCSection("Servers") {
                    AdminLoadState(cell: catalog.mcp, empty: "No MCPs configured", emptyDetail: "Add servers under mcp.servers in opencode.json on the computer running opencode.") { (servers: [MCPServer]) in
                        ForEach(servers.sorted { $0.name < $1.name }) { server in row(server) }
                    }
                }
            }
            Text("Connect and Disconnect last until the server restarts. To change them for good, edit mcp.servers in opencode.json.")
                .font(OCType.small).foregroundStyle(OCColor.textMuted)
        }
        .task(id: admin.directory) { await admin.loadCatalogs(); await admin.loadIntegrations() }
        .refreshable { admin.catalog?.mcp.invalidate(); await admin.loadCatalogs() }
        // Only this screen's MCP sign-ins: a provider sign-in from another window keeps its own sheet.
        .sheet(isPresented: Binding(get: { admin.connect.map { flow in admin.catalog?.mcp.value?.contains { $0.integrationID == flow.integrationID } ?? false } ?? false },
                                    set: { if !$0 { admin.endConnect() } })) {
            if let flow = admin.connect { ConnectFlowView(flow: flow) { admin.endConnect() }.ocSheet() }
        }
        .onDisappear { task?.cancel() }
    }
    private func row(_ server: MCPServer) -> some View {
        let state = Self.state(server.status)
        return VStack(alignment: .leading, spacing: OCSpacing.sm) {
            AdminRow(title: server.name, detail: server.status.error) {
                OCBadge(state.title, tone: state.tone).accessibilityIdentifier("mcpStatus-" + server.name)
            }
            HStack(spacing: OCSpacing.sm) {
                if case .needsAuth = server.status, let integration = signIn(server) {
                    Button("Sign in") { admin.beginConnect(integration.0, method: integration.1) }.buttonStyle(OCButtonStyle(.contrast))
                }
                if case .connected = server.status {
                    Button("Disconnect") { task = Task { await admin.setMCP(server.name, connected: false) } }
                        .buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("mcpDisconnect-" + server.name)
                } else {
                    Button("Connect") { task = Task { await admin.setMCP(server.name, connected: true) } }
                        .buttonStyle(OCButtonStyle()).accessibilityIdentifier("mcpConnect-" + server.name)
                }
            }.disabled(admin.isBusy("mcp:" + server.name))
        }
    }
    /// MCP OAuth is the integration flow of the server's `integrationID`.
    private func signIn(_ server: MCPServer) -> (IntegrationInfo, IntegrationMethod)? {
        guard let id = server.integrationID, let integration = admin.integrations.value?.first(where: { $0.id == id }),
              let method = integration.methods.first(where: { $0.type == "oauth" }) else { return nil }
        return (integration, method)
    }
    static func state(_ status: MCPStatus) -> (title: String, tone: OCTone) {
        switch status {
        case .connected: ("Connected", .success)
        case .pending: ("Pending", .info)
        case .disabled: ("Disabled", .neutral)
        case .failed: ("Failed", .danger)
        case .needsAuth: ("Needs auth", .warning)
        case .unknown(let type, _): (type.isEmpty ? "Unknown" : type, .neutral)
        case .undecodable: ("Unknown", .neutral)
        }
    }
}

/// "Allow always" rules, per project. Deleting one makes opencode ask again.
struct SavedPermissionsSection: View {
    @Bindable var admin: ServerAdminModel
    @State private var deleting: SavedPermission?
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text("Rules saved with Allow always. opencode allows matching requests in this project without asking.").foregroundStyle(OCColor.textMuted)
                AdminProjectPicker(admin: admin)
            }
            if let project = admin.project {
                OCSection("Allow always") {
                    AdminLoadState(cell: admin.savedPermissions(for: project.id), empty: "No saved rules",
                                   emptyDetail: "Choosing Allow always on a request saves its patterns here.") { (rules: [SavedPermission]) in
                        ForEach(rules) { rule in
                            AdminRow(title: rule.action, detail: rule.resource + (rule.created > 0 ? "\nSaved " + AdminText.date(rule.created) : "")) {
                                Button { deleting = rule } label: { OCIcon("outline-trash").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
                                    .buttonStyle(.plain).foregroundStyle(OCColor.danger).disabled(admin.isBusy("saved:" + rule.id))
                                    .accessibilityLabel("Delete rule \(rule.action) \(rule.resource)")
                                    .accessibilityIdentifier("deleteSavedPermission")
                            }
                        }
                    }
                }
                .task(id: project.id) { await admin.loadSavedPermissions(projectID: project.id) }
            } else {
                Text("No projects yet").foregroundStyle(OCColor.textMuted)
            }
            Text("Auto-accept is not offered on the phone: every request without a saved rule asks first.")
                .font(OCType.small).foregroundStyle(OCColor.textMuted)
        }
        .refreshable {
            guard let project = admin.project else { return }
            admin.savedPermissions(for: project.id).invalidate(); await admin.loadSavedPermissions(projectID: project.id)
        }
        .confirmationDialog("Delete this rule?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete rule", role: .destructive) {
                guard let rule = deleting else { return }
                deleting = nil
                task = Task { _ = await admin.deleteSavedPermission(rule) }
            }.accessibilityIdentifier("confirmDeleteSavedPermission")
        } message: {
            Text("opencode will ask again before \(deleting?.action ?? "") on \(deleting?.resource ?? "") in \(admin.project.map(AdminText.name) ?? "this project").")
        }
        .onDisappear { task?.cancel() }
    }
}
#endif

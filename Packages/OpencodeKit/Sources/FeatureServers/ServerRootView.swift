#if os(iOS)
import SwiftUI
import OCDesign
import OCModels
import OCSync
import OCShared
import FeatureInbox
import FeatureTranscript
import FeatureComposer
import FeatureReview

public struct ServerRootView: View {
    @Bindable var registry: ServerRegistry
    @Binding private var incomingURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    private enum SettingsDestination: String, Identifiable {
        case settings, addServer
        var id: String { rawValue }
    }
    @State private var settingsDestination: SettingsDestination?
    @State private var sessionPath: [SessionRef] = []
    @State private var pendingLink: DeepLink?
    @State private var routingError: String?
    @State private var creatingSession = false
    @State private var recoveredDirectory: String?
    @State private var selectedServer: ServerID?
    @State private var selectedProject: String?
    /// The session New session was started from, and a server picked in New session itself.
    @State private var newSessionOrigin: SessionRef?
    @State private var newSessionServer: ServerID?
    @State private var homeDismissal: UUID?
    @State private var announcedConnections: [ServerID: String] = [:]
    @State private var localExplanation = false
    @State private var phaseTask: Task<Void, Never>?
    public init(registry: ServerRegistry, incomingURL: Binding<URL?> = .constant(nil)) {
        self.registry = registry; _incomingURL = incomingURL
    }
    public var body: some View {
        // Keep the sheet presenter stable when adding the first server replaces onboarding.
        ZStack {
            if registry.servers.isEmpty {
                NavigationStack {
                    OCEmptyState("Your servers, anywhere", detail: "Connect to opencode on your computer to keep your work close.", icon: "server") {
                        Button { settingsDestination = .addServer } label: { OCLabel("Add your first server", icon: "plus") }
                            .buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("addFirstServer")
                            .disabled(!registry.isLoaded)
                    }.ocNavigationTitle("Opencode")
                }
            } else if sizeClass == .regular {
                OCWorkspaceShell(homeInitiallyOpen: true, selectionID: sessionPath.last?.id,
                                 allowsPresentation: settingsDestination == nil && !localExplanation, reviewRequest: panelRequest,
                                 homeDismissal: homeDismissal) {
                    home
                } tabs: {
                    OCProjectTabs(projects: projectTabs, selection: $selectedProject)
                } main: {
                    if let ref = sessionPath.last {
                        VStack(spacing: 0) {
                            if sessionPath.count > 1 {
                                Button("Back to parent") { sessionPath.removeLast() }.buttonStyle(OCButtonStyle(.ghost))
                            }
                            sessionView(ref)
                        }
                    } else { newSessionView }
                } panel: {
                    if let ref = sessionPath.last, let server = registry.servers.first(where: { $0.id == ref.serverID }) { WorkspaceReviewPanel(server: server, sessionID: ref.sessionID) }
                    else { OCWorkspacePanel() }
                }
            } else {
                NavigationStack(path: $sessionPath) {
                    home.toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: SessionRef.self) { ref in
                            sessionView(ref).toolbar(.visible, for: .navigationBar)
                        }
                }
            }
        }
        .uiTestConnectionDiagnostics(registry)
        .ocTheme()
        .onChange(of: incomingURL, initial: true) { _, url in
            guard let url else { return }
            incomingURL = nil
            guard let link = DeepLink(url: url) else { return }
            pendingLink = link; routeLink()
        }
        .onChange(of: registry.isLoaded) { _, _ in routeLink() }
        .onChange(of: failedCreationDirectory) { _, directory in
            guard let directory else { return }
            if let ref = sessionPath.last { newSessionOrigin = ref; newSessionServer = ref.serverID }
            recoveredDirectory = directory; sessionPath = []
            if sizeClass != .regular { creatingSession = true }
        }
        .alert("Could not open link", isPresented: Binding(get: { routingError != nil }, set: { if !$0 { routingError = nil } })) {
            Button("OK") { routingError = nil }
        } message: { Text(routingError ?? "") }
        .sheet(isPresented: $creatingSession) {
            NavigationStack { newSessionView.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creatingSession = false } } } }.ocSheet()
        }
        .background {
            Button("New session", action: beginSession).keyboardShortcut("n", modifiers: .command).hidden()
        }
        .sheet(item: $settingsDestination) { destination in
            ServerSettingsView(registry: registry, addOnOpen: destination == .addServer).ocSheet()
        }
        .sheet(isPresented: $localExplanation) {
            LocalNetworkExplanation {
                localExplanation = false
                phaseTask?.cancel()
                phaseTask = Task { await registry.acknowledgeLocalNetwork() }
            }.interactiveDismissDisabled().uiTestConnectionDiagnostics(registry)
        }
        .onChange(of: registry.requiresLocalNetworkExplanation) { _, needed in localExplanation = needed }
        .onChange(of: repairIDs) { _, ids in
            if !ids.isEmpty && settingsDestination == nil { settingsDestination = .settings }
        }
        .overlay(alignment: .bottom) {
            if let error = registry.error {
                OCToast(announcement: error) {
                    Text(error).font(OCType.body)
                    if !registry.isLoaded {
                        Button("Try again") { phaseTask?.cancel(); phaseTask = Task { await registry.load() } }
                            .buttonStyle(OCButtonStyle())
                    }
                }
            }
        }
        .task {
            await registry.load()
            await registry.setScenePhase(scenePhase == .active ? .active : .inactive)
        }
        .onDisappear { phaseTask?.cancel() }
        .onChange(of: connectionNotices) { _, notices in announceConnection(notices) }
        .onChange(of: scenePhase) { _, phase in
            phaseTask?.cancel()
            phaseTask = Task { await registry.setScenePhase(phase == .active ? .active : phase == .background ? .background : .inactive) }
        }
    }
    @ViewBuilder private func sessionView(_ ref: SessionRef) -> some View {
        if let server = registry.servers.first(where: { $0.id == ref.serverID }) {
            SessionScreen(server: server, sessionID: ref.sessionID, requestID: ref.requestID, newSession: beginSession, deleted: { sessionPath = [] },
                          openSettings: { settingsDestination = .settings }, openRoot: { root in
                sessionPath = [.init(serverID: server.id, sessionID: root)]
            }) { child in
                sessionPath.append(.init(serverID: server.id, sessionID: child))
            }.id(ref.id)
        } else { Text("This server is no longer saved.").font(OCType.body) }
    }
    private func routeLink() {
        guard registry.isLoaded, let link = pendingLink else { return }
        pendingLink = nil
        let id = ServerID(rawValue: link.serverID)
        guard registry.servers.contains(where: { $0.id == id }) else {
            routingError = "This server is not saved. Add it in Settings first."; return
        }
        // Home's filters stay as the user left them; a server-only link starts New session on that server.
        newSessionOrigin = nil; newSessionServer = id
        sessionPath = link.sessionID.map { [.init(serverID: id, sessionID: $0, requestID: link.requestID)] } ?? []
    }

    private func beginSession() {
        recoveredDirectory = nil
        newSessionOrigin = sessionPath.last; newSessionServer = nil
        homeDismissal = UUID()
        if sizeClass == .regular { sessionPath = [] } else { creatingSession = true }
    }
    private var newSessionTarget: NewSessionTarget? {
        let origin = newSessionOrigin.map { ref in
            NewSessionTarget(serverID: ref.serverID, projectID: registry.servers.first { $0.id == ref.serverID }?.sessions[ref.sessionID]?.info.projectID)
        }
        return NewSessionTarget.resolve(servers: registry.servers.map(\.id), chosenServer: newSessionServer, homeServer: selectedServer,
                                        homeProject: selectedProject, origin: origin)
    }
    @ViewBuilder private var newSessionView: some View {
        if let target = newSessionTarget, let server = registry.servers.first(where: { $0.id == target.serverID }) {
            NewSessionView(server: server, directory: recoveredDirectory, project: target.projectID, servers: registry.servers,
                           selectServer: { newSessionServer = $0.id; recoveredDirectory = nil }) { id in
                creatingSession = false; sessionPath = [.init(serverID: server.id, sessionID: id)]
            }
            // A new target (Home's project, a project tab, or another server) starts a fresh New session.
            .id(server.id.rawValue.uuidString + ":" + (target.projectID ?? ""))
        }
    }
    /// Each server's connection problem, or "connected"; the brief connecting states between retries are left out
    /// so VoiceOver hears one announcement per change, not one per retry.
    private var connectionNotices: [ServerID: String] {
        var values: [ServerID: String] = [:]
        for server in registry.servers {
            if let notice = server.connectionNotice { values[server.id] = notice.identifier }
            else if case .connected = server.state { values[server.id] = "connected" }
        }
        return values
    }
    private func announceConnection(_ new: [ServerID: String]) {
        for server in registry.servers {
            guard let next = new[server.id], next != announcedConnections[server.id] else { continue }
            let previous = announcedConnections.updateValue(next, forKey: server.id)
            if previous == nil && next == "connected" { continue }
            let text = server.record.name + ": " + (server.connectionNotice?.title ?? "Connected")
            AccessibilityNotification.Announcement(text).post()
        }
    }
    private var panelRequest: UUID? {
        guard let ref = sessionPath.last, let server = registry.servers.first(where: { $0.id == ref.serverID }), let session = server.sessions[ref.sessionID] else { return nil }
        let review = server.readPath.review(sessionID: ref.sessionID, directory: session.info.location.directory)
        let files = server.readPath.files(sessionID: ref.sessionID, directory: session.info.location.directory)
        return review.tab == "Files" ? files.presentRequest : review.presentRequest
    }
    private var failedCreationDirectory: String? {
        guard let ref = sessionPath.last else { return nil }
        return registry.servers.first { $0.id == ref.serverID }?.readPath.failedCreationDirectories[ref.sessionID]
    }
    private var repairIDs: [ServerID] { registry.servers.filter { $0.needsRepair }.map { $0.id } }
    private var projectTabs: [OCProjectTab] {
        registry.servers.filter { selectedServer == nil || $0.id == selectedServer }.flatMap { server in
            server.projects.map { OCProjectTab(id: server.id.rawValue.uuidString + ":" + $0.id, title: $0.name ?? URL(fileURLWithPath: $0.canonical).lastPathComponent) }
        }
    }
    private var home: some View {
        WorkspaceSidebar(registry: registry, selectedServer: $selectedServer, selectedProject: $selectedProject,
                         openSettings: { settingsDestination = .settings }, newSession: beginSession,
                         selectedSession: sizeClass == .regular ? sessionPath.first : nil, selectSession: { ref in
            sessionPath = [ref]; newSessionOrigin = nil; homeDismissal = UUID()
        })
            .uiTestConnectionDiagnostics(registry)
    }
}

struct LocalNetworkExplanation: View {
    let proceed: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OCSpacing.xl) {
                    OCIcon("globe", size: 32).font(OCType.title).foregroundStyle(OCColor.iconMuted).accessibilityHidden(true)
                    Text("Connect on your local network").font(OCType.title)
                    Text("Opencode connects directly to the server you choose on your computer. iOS may ask you to allow Local Network access next.")
                    Text("Allow access to connect over Wi-Fi. You can change this later in Settings → Privacy & Security → Local Network.")
                        .foregroundStyle(OCColor.textMuted)
                    Button("Continue", action: proceed).buttonStyle(OCButtonStyle(.contrast))
                        .accessibilityIdentifier("localNetworkContinue")
                }.padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }.ocNavigationTitle("Local Network").navigationBarTitleDisplayMode(.inline).ocTheme()
        }
    }
}
#endif

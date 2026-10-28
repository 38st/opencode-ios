#if os(iOS)
import SwiftUI
import UIKit
import OCDesign
import OCModels
import OCSync
import OCShared
import FeatureInbox
import FeatureTranscript
import FeatureComposer
import FeatureReview

/// One window's workspace. Every window shares the registry; navigation, panels and widths belong to the window,
/// restore with it on iPad, and the window coordinator decides which window takes a link.
public struct ServerRootView: View {
    @Bindable var registry: ServerRegistry
    let windows: WindowCoordinator
    @Binding private var windowValue: SessionRef?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("workspace.window") private var storedState: Data?
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
    @State private var windowID = UUID()
    @State private var sceneSession: UISceneSession?
    @State private var registered = false
    @State private var resetsOtherWindows = false
    @State private var layout = OCWorkspaceLayout()
    @State private var paletteOpen = false
    @State private var homeToggle: UUID?
    @State private var reviewToggle: UUID?
    @State private var homeSearch = ""
    @State private var homeShowsHidden = false
    public init(registry: ServerRegistry, windows: WindowCoordinator = WindowCoordinator(), window: Binding<SessionRef?> = .constant(nil)) {
        self.registry = registry; self.windows = windows; _windowValue = window
    }
    public var body: some View {
        status(presentations(routing(lifecycle(workspace))))
    }
    @ViewBuilder private var workspace: some View {
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
                OCWorkspaceShell(layout: $layout, selectionID: sessionPath.last?.id,
                                 allowsPresentation: settingsDestination == nil && !localExplanation && !paletteOpen, reviewRequest: panelRequest,
                                 homeDismissal: homeDismissal, homeToggle: homeToggle, reviewToggle: reviewToggle) {
                    home
                } tabs: {
                    OCProjectTabs(projects: projectTabs, selection: $selectedProject)
                } main: {
                    if let ref = sessionPath.last {
                        VStack(spacing: 0) {
                            if sessionPath.count > 1 {
                                Button("Back to parent") { sessionPath.removeLast() }.buttonStyle(OCButtonStyle(.ghost))
                            }
                            sessionView(ref, ownsCommands: !creatingSession)
                        }
                    } else { newSessionView(ownsCommands: !creatingSession) }
                } panel: {
                    if let ref = sessionPath.last, let server = registry.servers.first(where: { $0.id == ref.serverID }) {
                        WorkspaceReviewPanel(server: server, sessionID: ref.sessionID) { id in open(SessionRef(serverID: server.id, sessionID: id)) }
                    } else { OCWorkspacePanel() }
                }
            } else {
                NavigationStack(path: $sessionPath) {
                    home.toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: SessionRef.self) { ref in
                            // Only the screen on top takes the menu bar's composer commands and Toggle review.
                            sessionView(ref, ownsCommands: ref == sessionPath.last && !creatingSession).toolbar(.visible, for: .navigationBar)
                        }
                }
            }
            if paletteOpen && sizeClass == .regular {
                Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { paletteOpen = false }.accessibilityHidden(true)
                GeometryReader { geometry in
                    // Desktop dialog.css: at most 640 wide and 280 to 480 tall, centred a little above the middle.
                    CommandPalette(search: paletteGroups, select: selectPaletteEntry, supportsWindows: supportsMultipleWindows,
                                   maxHeight: min(480, geometry.size.height - 96)) { paletteOpen = false }
                        .frame(width: min(640, geometry.size.width - OCSpacing.lg * 2))
                        .background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.dock))
                        .overlay(RoundedRectangle(cornerRadius: OCRadius.dock).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: OCRadius.dock)).ocElevation(.floating)
                        .frame(maxWidth: .infinity).padding(.top, max(48, (geometry.size.height - 480) / 2)).padding(.bottom, OCSpacing.xl)
                }.accessibilityAddTraits(.isModal)
            }
        }
    }
    /// The window's registration, phase, restoration and saved state.
    private func lifecycle(_ content: some View) -> some View {
        content
            .uiTestConnectionDiagnostics(registry)
            .ocTheme()
            .background { probe }
            .focusedSceneValue(\.ocWindowCommands, OCWindowCommands(window: windowID, state: commandState, perform: perform))
            .onAppear(perform: register)
            .onDisappear { phaseTask?.cancel(); windows.unregister(windowID) }
            .onChange(of: scenePhase, initial: true) { _, phase in windows.update(windowID, phase: phase == .active ? .active : phase == .background ? .background : .inactive) }
            .onChange(of: sessionPath, initial: true) { _, path in
                windows.update(windowID, path: path)
                if supportsMultipleWindows {
                    windowValue = path.first.map { SessionRef(serverID: $0.serverID, sessionID: $0.sessionID) }
                    WindowScenes.mark(sceneSession, root: path.first.flatMap(rootRef))
                }
                save()
            }
            .modifier(SavesWindowState(layout: layout, server: selectedServer, project: selectedProject, tab: currentReview?.tab,
                                       treeWidth: currentReview?.sidebarWidth, save: save))
    }
    /// Links, notifications and dropped activities.
    private func routing(_ content: some View) -> some View {
        content
            .onOpenURL(perform: route)
            // A Home row dropped at the edge of the screen opens here, in the window it created.
            .onContinueUserActivity(SessionActivity.type) { activity in
                guard let url = SessionActivity.url(activity), let link = DeepLink(url: url) else { return }
                if let ref = link.sessionID.map({ SessionRef(serverID: ServerID(rawValue: link.serverID), sessionID: $0) }), let other = windows.window(showing: ref), other != windowID {
                    windows.bringForward(other)
                    // The drop made this window, but the session already has one: this one closes.
                    if sessionPath.isEmpty, let sceneSession { WindowScenes.close(sceneSession) }
                    return
                }
                pendingLink = link; routeLink()
            }
            .onChange(of: windows.routes[windowID]) { _, _ in
                guard let link = windows.take(windowID) else { return }
                pendingLink = link; routeLink()
            }
            .onChange(of: registry.notifications?.incomingURL, initial: true) { _, url in
                // Every window sees the change; the first one takes it and the coordinator picks the window.
                guard let url, registry.notifications?.incomingURL == url else { return }
                registry.notifications?.incomingURL = nil
                route(url)
            }
            .onChange(of: registry.isLoaded) { _, _ in routeLink() }
            .onChange(of: failedCreationDirectory) { _, directory in
                guard let directory else { return }
                if let ref = sessionPath.last { newSessionOrigin = ref; newSessionServer = ref.serverID }
                recoveredDirectory = directory; sessionPath = []
                if sizeClass != .regular { creatingSession = true }
            }
    }
    private func presentations(_ content: some View) -> some View {
        content
            .alert("Could not open link", isPresented: Binding(get: { routingError != nil }, set: { if !$0 { routingError = nil } })) {
                Button("OK") { routingError = nil }
            } message: { Text(routingError ?? "") }
            .sheet(isPresented: $creatingSession) {
                NavigationStack { newSessionView(ownsCommands: true).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creatingSession = false } } } }.ocSheet()
            }
            .sheet(isPresented: Binding(get: { paletteOpen && sizeClass != .regular }, set: { paletteOpen = $0 })) {
                palette.presentationDetents([.large]).ocSheet()
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
            // App-wide prompts appear once, in the key window.
            .onChange(of: registry.requiresLocalNetworkExplanation, initial: true) { _, needed in localExplanation = needed && windows.isKey(windowID) }
            .onChange(of: windows.current) { _, _ in localExplanation = registry.requiresLocalNetworkExplanation && windows.isKey(windowID) }
            .onChange(of: repairIDs) { _, ids in
                if !ids.isEmpty && settingsDestination == nil && windows.isKey(windowID) { settingsDestination = .settings }
            }
    }
    /// The error toast, connection announcements and the UI-test elements.
    private func status(_ content: some View) -> some View {
        content
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
            .overlay(alignment: .topLeading) { debugElements }
            .task { await registry.load() }
            .onChange(of: connectionNotices) { _, notices in if windows.isKey(windowID) { announceConnection(notices) } }
    }
    @ViewBuilder private func sessionView(_ ref: SessionRef, ownsCommands: Bool) -> some View {
        if let server = registry.servers.first(where: { $0.id == ref.serverID }) {
            SessionScreen(server: server, sessionID: ref.sessionID, requestID: ref.requestID, newSession: beginSession, deleted: { sessionPath = [] },
                          openSettings: { settingsDestination = .settings }, reviewToggle: reviewToggle, ownsCommands: ownsCommands, openRoot: { root in
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
        creatingSession = false; paletteOpen = false
        sessionPath = link.sessionID.map { [.init(serverID: id, sessionID: $0, requestID: link.requestID)] } ?? []
    }
    /// Sends a link to the window already showing its session, or else to the key window.
    private func route(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        let ref = link.sessionID.map { SessionRef(serverID: ServerID(rawValue: link.serverID), sessionID: $0) }
        let root = ref.flatMap(rootRef)
        // A window iPadOS keeps but has not connected takes the link when it comes forward.
        if let ref, windows.window(showing: ref) == nil, let root, windows.window(showing: root) == nil,
           let parked = WindowScenes.session(showing: root, except: sceneSession) {
            let scene = parked.persistentIdentifier
            windows.park(link, scene: scene)
            // If iPadOS does not bring that window back, the link opens as if no window had it.
            WindowScenes.activate(parked) {
                guard windows.takeParked(scene: scene) != nil else { return }
                if windows.route(link, root: root, from: windowID) == nil { pendingLink = link; routeLink() }
            }
            return
        }
        if windows.route(link, root: root, from: windowID) == nil { pendingLink = link; routeLink() }
    }
    private func beginSession() {
        recoveredDirectory = nil
        newSessionOrigin = sessionPath.last; newSessionServer = nil
        homeDismissal = UUID()
        if sizeClass == .regular { sessionPath = [] } else { creatingSession = true }
    }
    /// Opens a session here, unless another window already shows it: then that window comes forward.
    private func open(_ ref: SessionRef) {
        if let other = windows.window(showing: ref), other != windowID { windows.bringForward(other); return }
        if windows.window(showing: ref) == nil, let root = rootRef(ref), root.sessionID == ref.sessionID,
           let other = WindowScenes.session(showing: root, except: sceneSession) {
            WindowScenes.activate(other); return
        }
        creatingSession = false
        sessionPath = [ref]; newSessionOrigin = nil; homeDismissal = UUID()
    }
    private func openInNewWindow(_ ref: SessionRef) {
        let root = rootRef(ref) ?? ref
        if let other = windows.window(showing: root) {
            if other == windowID { return }
            windows.bringForward(other); return
        }
        if let other = WindowScenes.session(showing: root, except: sceneSession) { WindowScenes.activate(other); return }
        openWindow(value: SessionRef(serverID: root.serverID, sessionID: root.sessionID))
    }
    private func rootRef(_ ref: SessionRef) -> SessionRef? {
        guard let server = registry.servers.first(where: { $0.id == ref.serverID }) else { return nil }
        var id = ref.sessionID, seen: Set<String> = []
        while seen.insert(id).inserted, let parent = server.sessions[id]?.info.parentID { id = parent }
        return SessionRef(serverID: ref.serverID, sessionID: id)
    }
    private var newSessionTarget: NewSessionTarget? {
        let origin = newSessionOrigin.map { ref in
            NewSessionTarget(serverID: ref.serverID, projectID: registry.servers.first { $0.id == ref.serverID }?.sessions[ref.sessionID]?.info.projectID)
        }
        return NewSessionTarget.resolve(servers: registry.servers.map(\.id), chosenServer: newSessionServer, homeServer: selectedServer,
                                        homeProject: selectedProject, origin: origin)
    }
    @ViewBuilder private func newSessionView(ownsCommands: Bool) -> some View {
        if let target = newSessionTarget, let server = registry.servers.first(where: { $0.id == target.serverID }) {
            NewSessionView(server: server, directory: recoveredDirectory, project: target.projectID, servers: registry.servers,
                           selectServer: { newSessionServer = $0.id; recoveredDirectory = nil }, ownsCommands: ownsCommands) { id in
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
    private var currentReview: ReviewModel? {
        guard let ref = sessionPath.last, let server = registry.servers.first(where: { $0.id == ref.serverID }), let session = server.sessions[ref.sessionID] else { return nil }
        return server.readPath.review(sessionID: ref.sessionID, directory: session.info.location.directory)
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
        let newWindow: ((SessionRef) -> Void)? = supportsMultipleWindows ? { ref in openInNewWindow(ref) } : nil
        // ⌘1–9 follow the rows Home shows; each row's menu shows its key, except on iPhone, which has no menu bar.
        let shortcuts = UIDevice.current.userInterfaceIdiom == .phone ? [:]
            : Dictionary(uniqueKeysWithValues: ordered.prefix(9).enumerated().map { ($1.ref.id, WorkspaceCommand.session($0 + 1).chord.description) })
        return WorkspaceSidebar(registry: registry, selectedServer: $selectedServer, selectedProject: $selectedProject,
                                openSettings: { settingsDestination = .settings }, newSession: beginSession,
                                selectedSession: sizeClass == .regular ? sessionPath.first : nil,
                                openInNewWindow: newWindow, openPalette: { paletteOpen = true }, shortcut: { shortcuts[$0.id] },
                                search: $homeSearch, showHidden: $homeShowsHidden, selectSession: { ref in open(ref) })
            .uiTestConnectionDiagnostics(registry)
    }

    // MARK: Window commands

    private var ordered: [SessionSummary] {
        HomeOrdering.ordered(registry.servers, server: selectedServer, project: selectedProject, hidden: homeShowsHidden, search: homeSearch)
    }
    private var commandState: WindowCommandState {
        let ordered = ordered
        return WindowCommandState(modal: paletteOpen || settingsDestination != nil || localExplanation || routingError != nil, loaded: registry.isLoaded,
                                  canCreateSession: !registry.servers.isEmpty, supportsWindows: supportsMultipleWindows,
                                  sidebarAvailable: sizeClass == .regular && !registry.servers.isEmpty,
                                  current: sessionPath.first.flatMap(rootRef), sessions: ordered.map(\.ref),
                                  sessionTitles: ordered.map { $0.session.info.title ?? "Untitled session" },
                                  unread: Set(ordered.filter { $0.session.unread }.map(\.ref.id)),
                                  // A search or the hidden sessions never hide a pending request from ⇧⌘A.
                                  approvals: HomeOrdering.approvals(HomeOrdering.ordered(registry.servers, server: selectedServer, project: selectedProject)),
                                  openRequest: sessionPath.last?.requestID)
    }
    private func perform(_ command: WorkspaceCommand) {
        let state = commandState
        switch command {
        case .newSession: beginSession()
        case .newWindow: openWindow(id: Self.windowGroup)
        case .toggleSidebar: homeToggle = UUID()
        case .toggleReview: reviewToggle = UUID()
        case .commandPalette: paletteOpen = true
        case .reviewNextApproval:
            guard let ref = WorkspaceCommandRouter.nextApproval(state) else { return }
            registry.servers.first { $0.id == ref.serverID }?.readPath.reviewRequest = ref.requestID
            open(ref)
        default:
            if let ref = WorkspaceCommandRouter.session(command, window: state) { open(ref) }
        }
    }
    /// The App's window group, for New Window.
    public static let windowGroup = "workspace"

    // MARK: The switcher

    private var palette: some View {
        CommandPalette(search: paletteGroups, select: selectPaletteEntry, supportsWindows: supportsMultipleWindows) { paletteOpen = false }
    }
    private func paletteGroups(_ query: String) -> [SwitcherGroup] {
        var window = commandState; window.modal = false
        let composer = composerCommands?.state
        let commands = WorkspaceCommand.all.filter { $0 != .commandPalette && WorkspaceCommandRouter.isEnabled($0, window: window, composer: composer, find: findCommand != nil) }
        var sessions: [SwitcherIndex.Session] = [], projects: [SwitcherIndex.Project] = []
        for server in registry.servers {
            for session in server.sessions.values where session.info.parentID == nil && session.info.time.archived == nil {
                let item = SessionSummary(server: server, session: session)
                guard !item.meta.hidden else { continue }
                sessions.append(.init(ref: item.ref, title: session.info.title ?? "Untitled session", project: item.projectName, updated: item.activity))
            }
            for project in server.projects {
                projects.append(.init(filter: server.id.rawValue.uuidString + ":" + project.id, name: project.name ?? URL(fileURLWithPath: project.canonical).lastPathComponent,
                                      path: project.canonical, server: server.record.name))
            }
        }
        return SwitcherIndex.groups(query: query, commands: commands, sessions: sessions, projects: projects)
    }
    @FocusedValue(\.ocComposerCommands) private var composerCommands
    @FocusedValue(\.ocFindCommand) private var findCommand
    private func selectPaletteEntry(_ entry: SwitcherEntry, newWindow: Bool) {
        paletteOpen = false
        switch entry.kind {
        case .session(let ref): if newWindow { openInNewWindow(ref) } else { open(ref) }
        case .project(let filter):
            selectedServer = registry.servers.first { filter.hasPrefix($0.id.rawValue.uuidString + ":") }?.id
            selectedProject = filter; layout.homeOpen = true
        case .command(let command):
            var window = commandState; window.modal = false
            let performed = WorkspaceCommandRouter.perform(command, window: window, composer: composerCommands?.state, find: findCommand != nil,
                                                           windowAction: perform, composerAction: { composerCommands?.perform($0) }, findAction: { findCommand?.perform() })
            #if DEBUG
            if performed { OCCommandTrace.shared.record("palette." + command.id) }
            #else
            _ = performed
            #endif
        }
    }

    // MARK: Window lifecycle and restoration

    private static var owner: String {
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"], id.hasPrefix("ui-") { return id }
        #endif
        return ""
    }
    private func register() {
        guard !registered else { return }
        registered = true
        if windows.applyPhase == nil { windows.applyPhase = { [registry] in await registry.setScenePhase($0) } }
        let first = windows.register(windowID) { WindowScenes.activate(sceneSession) }
        windows.update(windowID, phase: scenePhase == .active ? .active : scenePhase == .background ? .background : .inactive)
        defer { windows.update(windowID, path: sessionPath) }
        #if DEBUG
        // A fresh UI-test launch starts with one window, whatever an earlier test left open.
        if first && ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
            resetsOtherWindows = true
            if let sceneSession { WindowScenes.closeOthers(keeping: sceneSession) }
            return
        }
        #else
        _ = first
        #endif
        guard supportsMultipleWindows else { return }
        if let state = WindowState.restore(storedState, owner: Self.owner, servers: Set(registry.servers.map(\.id))) {
            sessionPath = state.path; selectedServer = state.server; selectedProject = state.project
            layout = OCWorkspaceLayout(homeOpen: state.homeOpen, reviewOpen: state.reviewOpen, chatWidth: state.chatWidth, homeWidth: state.homeWidth)
            if let ref = state.path.last, let server = registry.servers.first(where: { $0.id == ref.serverID }), let session = server.sessions[ref.sessionID] {
                let review = server.readPath.review(sessionID: ref.sessionID, directory: session.info.location.directory)
                review.sidebarWidth = state.reviewTreeWidth
                if state.reviewOpen, let tab = state.reviewTab { review.present(tab) }
            }
        } else if let value = windowValue {
            sessionPath = [value]
        }
    }
    private var probe: WindowSceneProbe {
        WindowSceneProbe(attached: { session in sceneAttached(session) }, touched: { windows.focused(windowID) },
                         disconnected: { phaseTask?.cancel(); windows.unregister(windowID) })
    }
    private func sceneAttached(_ session: UISceneSession) {
        sceneSession = session
        if resetsOtherWindows { resetsOtherWindows = false; WindowScenes.closeOthers(keeping: session) }
        if supportsMultipleWindows { WindowScenes.mark(session, root: sessionPath.first.flatMap(rootRef)) }
        if let link = windows.takeParked(scene: session.persistentIdentifier) { pendingLink = link; routeLink() }
    }
    private func save() {
        guard registered, supportsMultipleWindows else { return }
        var state = WindowState(owner: Self.owner)
        state.path = sessionPath; state.server = selectedServer; state.project = selectedProject
        state.homeOpen = layout.homeOpen; state.reviewOpen = layout.reviewOpen; state.chatWidth = layout.chatWidth; state.homeWidth = layout.homeWidth
        state.reviewTab = currentReview?.tab; state.reviewTreeWidth = currentReview?.sidebarWidth ?? WorkspaceWidths.reviewTreeDefault
        storedState = state.encoded()
    }
    @ViewBuilder private var debugElements: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"] != nil {
            VStack(spacing: 0) {
                Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityLabel("Windows")
                    .accessibilityValue("this=\(windowID.uuidString)\n" + windows.diagnostics).accessibilityIdentifier("windowInventory")
                // UIKit does not publish scene changes to SwiftUI; read them every second.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityLabel("Scenes")
                        .accessibilityValue(WindowScenes.inventory).accessibilityIdentifier("sceneInventory")
                }
                Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityLabel("Commands")
                    .accessibilityValue(OCCommandTrace.shared.summary).accessibilityIdentifier("commandTrace")
                Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityLabel("Home order")
                    .accessibilityValue(ordered.map { $0.session.id + ($0.session.unread ? "*" : "") }.joined(separator: " ")).accessibilityIdentifier("homeOrder")
                // What the menu bar itself enabled, read every second like the scenes.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityLabel("Menu commands")
                        .accessibilityValue(OCCommandTrace.shared.menuEnabled.joined(separator: " ")).accessibilityIdentifier("workspaceCommands")
                }
            }.allowsHitTesting(true)
        }
        #endif
    }
}

/// Saves the window's state whenever a part of it changes.
private struct SavesWindowState: ViewModifier {
    let layout: OCWorkspaceLayout
    let server: ServerID?
    let project: String?
    let tab: String?
    let treeWidth: Double?
    let save: () -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: layout) { _, _ in save() }
            .onChange(of: server) { _, _ in save() }
            .onChange(of: project) { _, _ in save() }
            .onChange(of: tab) { _, _ in save() }
            .onChange(of: treeWidth) { _, _ in save() }
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

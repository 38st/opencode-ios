#if os(iOS)
import SwiftUI
import Foundation
import OCModels
import OCSync
import OCDesign
import OCShared

public struct HomeView: View {
    let registry: ServerRegistry
    @Binding var selectedServer: ServerID?
    @Binding var selectedProject: String?
    let openSettings: () -> Void
    let newSession: () -> Void
    let selectSession: (SessionRef) -> Void
    /// iPad only: the session in another window. Nil hides the menu item.
    let openInNewWindow: ((SessionRef) -> Void)?
    let openPalette: (() -> Void)?
    /// ⌘1–9 follow Home's order; the hint shows a row's number.
    let shortcut: (SessionRef) -> String?
    /// The session open beside Home; its root row is highlighted.
    let selectedSession: SessionRef?
    /// The search and the hidden-sessions toggle, owned by the window when it passes them, so ⌘1–9 follow the rows
    /// Home shows.
    private let searchBinding: Binding<String>?
    private let showHiddenBinding: Binding<Bool>?
    @State private var ownSearch = ""
    @State private var ownShowHidden = false
    private var search: String { searchBinding?.wrappedValue ?? ownSearch }
    private var showHidden: Bool { showHiddenBinding?.wrappedValue ?? ownShowHidden }
    @State private var error: String?
    @State private var action: Task<Void, Never>?
    @State private var cursors: [ServerID: String] = [:]
    @State private var loadedScope = false
    @State private var loading = false
    public init(registry: ServerRegistry, selectedServer: Binding<ServerID?>, selectedProject: Binding<String?>,
                openSettings: @escaping () -> Void, newSession: @escaping () -> Void = {}, selectedSession: SessionRef? = nil,
                openInNewWindow: ((SessionRef) -> Void)? = nil, openPalette: (() -> Void)? = nil, shortcut: @escaping (SessionRef) -> String? = { _ in nil },
                search: Binding<String>? = nil, showHidden: Binding<Bool>? = nil, selectSession: @escaping (SessionRef) -> Void) {
        self.registry = registry; _selectedServer = selectedServer; _selectedProject = selectedProject
        self.openSettings = openSettings; self.selectSession = selectSession; self.newSession = newSession
        self.selectedSession = selectedSession; self.openInNewWindow = openInNewWindow; self.openPalette = openPalette; self.shortcut = shortcut
        searchBinding = search; showHiddenBinding = showHidden
    }
    /// A subagent is shown in its root session's row, so highlight the root.
    private var selectedRowID: String? {
        guard let ref = selectedSession, let server = registry.servers.first(where: { $0.id == ref.serverID }) else { return nil }
        var id = ref.sessionID, seen: Set<String> = []
        while seen.insert(id).inserted, let parent = server.sessions[id]?.info.parentID { id = parent }
        return server.id.rawValue.uuidString + ":" + id
    }
    private var servers: [ServerStore] { registry.servers.filter { selectedServer == nil || selectedServer == $0.id } }
    private var searchServers: [ServerStore] {
        guard let owner = selectedProject?.split(separator: ":", maxSplits: 1).first else { return servers }
        return servers.filter { $0.id.rawValue.uuidString == owner }
    }
    private var sections: [HomeSection] {
        HomeOrdering.sections(registry.servers, server: selectedServer, project: selectedProject, hidden: showHidden, search: search)
    }
    public var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(servers) { server in
                if server.connectionNotice != nil {
                    // Ticks the retry countdown.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let notice = server.notice(now: .now) {
                            OCConnectionBanner(server.record.name + " · " + notice.title, detail: notice.detail, actionTitle: notice.actionTitle) {
                                switch notice.action {
                                case .repair, .details: openSettings()
                                case let action?: Task { await server.perform(action) }
                                case nil: break
                                }
                            }
                        }
                    }.padding(.horizontal, OCSpacing.sm).padding(.bottom, OCSpacing.xs)
                }
            }
            ScrollViewReader { proxy in
                List {
                    filters.listRowSeparator(.hidden).listRowBackground(OCColor.background)
                    let listed = sections
                    ForEach(listed.prefix(2)) { section($0.title, items: $0.items) }
                    if HomeOrdering.all(registry.servers, hidden: showHidden, search: search).isEmpty {
                        Text(search.isEmpty ? "Your sessions will appear here" : "No matching sessions")
                            .font(OCType.small).foregroundStyle(OCColor.textMuted).listRowSeparator(.hidden)
                            .listRowBackground(OCColor.background)
                    }
                    ForEach(listed.dropFirst(2)) { section($0.title, items: $0.items) }
                    if !cursors.isEmpty || (!loadedScope && servers.contains(where: { $0.readPath.rootCursor != nil })) {
                        Button(loading ? "Loading…" : "Load older sessions") { run(failureMessage: "Could not load older sessions.") { try await loadMore() } }
                            .disabled(loading).buttonStyle(OCButtonStyle()).listRowSeparator(.hidden).listRowBackground(OCColor.background)
                    }
                    if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).listRowBackground(OCColor.background) }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(OCColor.background)
                    .accessibilityIdentifier("homeSessions")
                    .refreshable { error = nil; await registry.refresh() }
                    .task(id: search + (selectedProject ?? "") + (selectedServer?.rawValue.uuidString ?? "")) {
                        do {
                            try await Task.sleep(for: .milliseconds(250))
                            cursors = [:]; loadedScope = false
                            for server in searchServers {
                                let project = selectedProject?.split(separator: ":", maxSplits: 1).last.map(String.init)
                                let next = try await server.readPath.listSessions(search: search.isEmpty ? nil : search, project: project)
                                try Task.checkCancellation(); cursors[server.id] = next
                            }
                            loadedScope = true; error = nil
                        } catch is CancellationError {} catch { self.error = "Could not refresh sessions. Pull to try again." }
                    }
                    .onChange(of: selectedRowID, initial: true) { _, id in
                        guard let id else { return }
                        withAnimation { proxy.scrollTo(id) }
                    }
            }
        }.background(OCColor.backgroundDeep).onDisappear { action?.cancel() }
    }
    private var header: some View {
        HStack(spacing: OCSpacing.xs) {
            OCIcon("grid-plus").foregroundStyle(OCColor.iconMuted)
            Text("Home").font(OCType.body).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let openPalette { OCIconButton("Command palette", icon: "magnifying-glass-menu", action: openPalette).accessibilityIdentifier("openCommandPalette") }
            OCIconButton("New session", icon: "plus", action: newSession).accessibilityIdentifier("newSession")
            OCIconButton("Settings", icon: "settings-gear", action: openSettings).accessibilityIdentifier("openSettings")
        }.padding(.leading, OCSpacing.lg).padding(.trailing, OCSpacing.xs)
    }
    private var filters: some View {
        VStack(spacing: OCSpacing.sm) {
            // A full-width row, so the server name is legible in the iPad sidebar.
            Menu {
                Button("All servers") { selectedServer = nil; selectedProject = nil }
                ForEach(registry.servers) { server in
                    Button { selectedServer = server.id; selectedProject = nil } label: {
                        Text(server.record.name)
                        Text(ServerStatus(state: server.state, endpoints: server.record.endpoints).title)
                    }
                }
                Divider()
                Toggle("Hidden sessions", isOn: showHiddenBinding ?? $ownShowHidden)
                Button("Manage servers", action: openSettings)
            } label: {
                HStack {
                    OCIcon("server")
                    Text(registry.servers.first { $0.id == selectedServer }?.record.name ?? "All servers").font(OCType.small)
                    Spacer(minLength: 0); OCIcon("chevron-down", size: 12)
                }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Switch server")
                .accessibilityValue(registry.servers.first { $0.id == selectedServer }?.record.name ?? "All servers")
                .accessibilityIdentifier("serverSwitcher")
            Menu {
                Button("All projects") { selectedProject = nil }
                ForEach(servers) { server in
                    Section(server.record.name) {
                        ForEach(server.projects) { project in
                            Button(project.name ?? URL(fileURLWithPath: project.canonical).lastPathComponent) {
                                selectedProject = server.id.rawValue.uuidString + ":" + project.id
                            }.accessibilityIdentifier("project-option-" + server.id.rawValue.uuidString + ":" + project.id)
                        }
                    }
                }
            } label: {
                HStack {
                    OCIcon("folder")
                    Text(projectTitle).font(OCType.small)
                    Spacer(minLength: 0); OCIcon("chevron-down", size: 12)
                }.frame(minHeight: OCLayout.touchTarget)
            }.buttonStyle(.plain).accessibilityIdentifier("projectPicker")
            HStack(spacing: OCSpacing.sm) {
                OCIcon("magnifying-glass").foregroundStyle(OCColor.iconMuted)
                TextField("Search sessions", text: searchBinding ?? $ownSearch).textFieldStyle(.plain).font(OCType.small).autocorrectionDisabled().accessibilityIdentifier("sessionSearch")
            }.padding(.horizontal, OCSpacing.md).frame(minHeight: OCLayout.touchTarget)
                .background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
        }
    }
    private var projectTitle: String {
        for server in servers {
            if let project = server.projects.first(where: { server.id.rawValue.uuidString + ":" + $0.id == selectedProject }) {
                return project.name ?? URL(fileURLWithPath: project.canonical).lastPathComponent
            }
        }
        return "All projects"
    }
    private func section(_ title: String, items: [SessionSummary]) -> some View {
        Section {
            ForEach(items) { item in
                let selected = item.id == selectedRowID
                HomeSessionRow(item: item, selected: selected, select: { selectSession(item.ref) }, review: { selectSession(item.reviewRef) })
                    .listRowSeparator(.hidden)
                    .listRowBackground(OCColor.background.overlay {
                        if selected { RoundedRectangle(cornerRadius: OCRadius.md).fill(OCColor.pressed).padding(.horizontal, OCSpacing.xs) }
                    })
                    .swipeActions(edge: .trailing) {
                        Button("Mark read") { markRead(item) }.tint(OCColor.accent)
                        Button(item.meta.hidden ? "Unhide" : "Hide") { toggleHidden(item) }.tint(OCColor.textMuted)
                    }
                    .swipeActions(edge: .leading) {
                        Button(item.meta.pinned ? "Unpin" : "Pin") { togglePinned(item) }.tint(OCColor.info)
                    }
                    .contextMenu { menu(item) }
                    // Dragging a row to the edge of the screen opens the session in a new window.
                    .onDrag { SessionActivity.provider(item.ref) }
            }
        } header: { if !items.isEmpty { OCSidebarHeader(title) } }
    }
    @ViewBuilder private func menu(_ item: SessionSummary) -> some View {
        Button { selectSession(item.ref) } label: {
            Text("Open")
            if let shortcut = shortcut(item.ref) { Text(shortcut) }
        }
        if let openInNewWindow { Button("Open in New Window") { openInNewWindow(item.ref) } }
        if item.needsYou { Button("Review") { selectSession(item.reviewRef) } }
        Divider()
        Button("Mark read") { markRead(item) }
        Button(item.meta.pinned ? "Unpin" : "Pin") { togglePinned(item) }
        Button(item.meta.hidden ? "Unhide" : "Hide") { toggleHidden(item) }
        if let url = DeepLink.url(serverID: item.server.id.rawValue, sessionID: item.session.id) {
            Button("Copy session link") { OCCopy.text(url.absoluteString) }
        }
    }
    private func markRead(_ item: SessionSummary) { run { try await item.server.readPath.markViewed(item.session.id) } }
    private func togglePinned(_ item: SessionSummary) { run { var meta = item.meta; meta.pinned.toggle(); try await item.server.readPath.setLocalMeta(meta, sessionID: item.session.id) } }
    private func toggleHidden(_ item: SessionSummary) { run { var meta = item.meta; meta.hidden.toggle(); try await item.server.readPath.setLocalMeta(meta, sessionID: item.session.id) } }
    private func run(failureMessage: String = "Could not save the change. Try again.", _ operation: @escaping @MainActor () async throws -> Void) {
        action?.cancel(); action = Task { do { try await operation(); error = nil } catch is CancellationError {} catch { self.error = failureMessage } }
    }
    private func loadMore() async throws {
        loading = true; defer { loading = false }
        for server in searchServers {
            guard let cursor = cursors[server.id] ?? (!loadedScope && search.isEmpty ? server.readPath.rootCursor : nil) else { continue }
            let project = selectedProject?.split(separator: ":", maxSplits: 1).last.map(String.init)
            cursors[server.id] = try await server.readPath.listSessions(search: search.isEmpty ? nil : search, project: project, cursor: cursor)
        }
    }
}
#endif

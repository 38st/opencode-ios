#if os(iOS)
import SwiftUI
import Foundation
import OCModels
import OCSync
import OCDesign

public struct HomeView: View {
    let registry: ServerRegistry
    @Binding var selectedServer: ServerID?
    @Binding var selectedProject: String?
    let openSettings: () -> Void
    let newSession: () -> Void
    let selectSession: (SessionRef) -> Void
    @State private var search = ""
    @State private var showHidden = false
    @State private var error: String?
    @State private var action: Task<Void, Never>?
    @State private var cursors: [ServerID: String] = [:]
    @State private var loadedScope = false
    @State private var loading = false
    public init(registry: ServerRegistry, selectedServer: Binding<ServerID?>, selectedProject: Binding<String?>,
                openSettings: @escaping () -> Void, newSession: @escaping () -> Void = {}, selectSession: @escaping (SessionRef) -> Void) {
        self.registry = registry; _selectedServer = selectedServer; _selectedProject = selectedProject
        self.openSettings = openSettings; self.selectSession = selectSession; self.newSession = newSession
    }
    private var servers: [ServerStore] { registry.servers.filter { selectedServer == nil || selectedServer == $0.id } }
    private var searchServers: [ServerStore] {
        guard let owner = selectedProject?.split(separator: ":", maxSplits: 1).first else { return servers }
        return servers.filter { $0.id.rawValue.uuidString == owner }
    }
    private var all: [SessionSummary] {
        var values: [SessionSummary] = []
        for server in registry.servers {
            for session in server.sessions.values where session.info.parentID == nil {
                let item = SessionSummary(server: server, session: session)
                guard showHidden == item.meta.hidden else { continue }
                let title = session.info.title ?? "Untitled session"
                guard search.isEmpty || title.localizedCaseInsensitiveContains(search) else { continue }
                values.append(item)
            }
        }
        values.sort { a, b in
            if a.meta.pinned != b.meta.pinned { return a.meta.pinned }
            if a.activity != b.activity { return a.activity > b.activity }
            return a.id < b.id
        }
        return values
    }
    private var recent: [SessionSummary] {
        all.filter { item in
            !item.needsYou && item.runningCount == 0 && (selectedServer == nil || selectedServer == item.server.id) &&
                (selectedProject == nil || selectedProject == item.server.id.rawValue.uuidString + ":" + item.session.info.projectID)
        }
    }
    private func date(_ item: SessionSummary) -> Date { Date(timeIntervalSince1970: item.activity / 1_000) }
    private var days: [Date] { Set(recent.map { Calendar.current.startOfDay(for: date($0)) }).sorted(by: >) }
    public var body: some View {
        VStack(spacing: 0) {
            header
            List {
                filters.listRowSeparator(.hidden).listRowBackground(OCColor.background)
                section("Needs you", items: all.filter(\.needsYou))
                section("Running", items: all.filter { !$0.needsYou && $0.runningCount > 0 })
                if all.isEmpty {
                    Text(search.isEmpty ? "Your sessions will appear here" : "No matching sessions")
                        .font(OCType.small).foregroundStyle(OCColor.textMuted).listRowSeparator(.hidden)
                        .listRowBackground(OCColor.background)
                }
                ForEach(days, id: \.self) { day in
                    section(dayTitle(day), items: recent.filter { Calendar.current.isDate(date($0), inSameDayAs: day) })
                }
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
        }.background(OCColor.backgroundDeep).onDisappear { action?.cancel() }
    }
    private var header: some View {
        HStack(spacing: OCSpacing.xs) {
            OCIcon("grid-plus").foregroundStyle(OCColor.iconMuted)
            Text("Home").font(OCType.body).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Menu {
                Button("All servers") { selectedServer = nil; selectedProject = nil }
                ForEach(registry.servers) { server in Button(server.record.name) { selectedServer = server.id; selectedProject = nil } }
                Divider()
                Toggle("Hidden sessions", isOn: $showHidden)
                Button("Manage servers", action: openSettings)
            } label: {
                HStack(spacing: OCSpacing.xs) {
                    OCIcon("server", size: 14)
                    Text(registry.servers.first { $0.id == selectedServer }?.record.name ?? "All servers").font(OCType.small).lineLimit(1)
                    OCIcon("chevron-down", size: 12)
                }.frame(minHeight: OCLayout.touchTarget)
            }.buttonStyle(.plain).accessibilityLabel("Switch server").accessibilityIdentifier("serverSwitcher")
            OCIconButton("New session", icon: "plus", action: newSession).accessibilityIdentifier("newSession")
            OCIconButton("Settings", icon: "settings-gear", action: openSettings).accessibilityIdentifier("openSettings")
        }.padding(.leading, OCSpacing.lg).padding(.trailing, OCSpacing.xs)
    }
    private var filters: some View {
        VStack(spacing: OCSpacing.sm) {
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
                TextField("Search sessions", text: $search).textFieldStyle(.plain).font(OCType.small).autocorrectionDisabled().accessibilityIdentifier("sessionSearch")
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
                HomeSessionRow(item: item, select: { selectSession(item.ref) }, review: { selectSession(item.reviewRef) })
                    .listRowSeparator(.hidden).listRowBackground(OCColor.background)
                    .swipeActions(edge: .trailing) {
                        Button("Mark read") { run { try await item.server.readPath.markViewed(item.session.id) } }.tint(OCColor.accent)
                        Button(item.meta.hidden ? "Unhide" : "Hide") { run { var meta = item.meta; meta.hidden.toggle(); try await item.server.readPath.setLocalMeta(meta, sessionID: item.session.id) } }.tint(OCColor.textMuted)
                    }
                    .swipeActions(edge: .leading) {
                        Button(item.meta.pinned ? "Unpin" : "Pin") { run { var meta = item.meta; meta.pinned.toggle(); try await item.server.readPath.setLocalMeta(meta, sessionID: item.session.id) } }.tint(OCColor.info)
                    }
            }
        } header: { if !items.isEmpty { OCSidebarHeader(title) } }
    }
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
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
#endif

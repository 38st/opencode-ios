// Sources: packages/gui-extensions/src/context/{tab.tsx,format.ts,i18n/en.ts} (the stats, system prompt and raw
// messages), gui-extensions/src/details (session details), and the TUI sidebar's Todo and MCP sections. The V2 API
// exposes no LSP status, so the TUI's LSP section has no counterpart here.
#if os(iOS)
import SwiftUI
import OCFoundation
import OCModels
import OCSync
import OCDesign

/// The review panel's Context tab, and the iPhone's context sheet.
public struct ContextPanel: View {
    let store: ReadStore
    let sessionID: String
    let openSession: (String) -> Void
    let showChanges: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var width: CGFloat = 0
    @State private var exporting = false
    public init(store: ReadStore, sessionID: String, openSession: @escaping (String) -> Void = { _ in }, showChanges: @escaping () -> Void = {}) {
        self.store = store; self.sessionID = sessionID; self.openSession = openSession; self.showChanges = showChanges
    }
    public var body: some View {
        if let session = store.sessions[sessionID] {
            ScrollView {
                VStack(alignment: .leading, spacing: OCSpacing.xl) {
                    content(session)
                }.padding(.horizontal, OCSpacing.lg).padding(.top, OCSpacing.lg).padding(.bottom, OCSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }.background(OCColor.background).accessibilityIdentifier("contextPanel")
                .sheet(isPresented: $exporting) {
                    OCExportSheet(prepare: { try await store.exportFile(sessionID, format: $0, sanitize: $1) }) { exporting = false }.ocSheet()
                }
        } else {
            OCEmptyState("Session unavailable", detail: "Open the session to see its context.", icon: "brain", presentation: .panel) { EmptyView() }
        }
    }
    @ViewBuilder private func content(_ session: SessionModel) -> some View {
        // Whole messages, with their content: todos and raw messages need it.
        let messages = session.transcript.map { transcript in transcript.order.compactMap { transcript.messages[$0]?.value.fields } } ?? []
        let catalog = store.catalogs[session.info.location.key]
        let models = catalog?.models.value ?? []
        let usage = ContextUsage.compute(messages, boundary: session.info.revert?.messageID, models: models, session: session.info.model)
        HStack(alignment: .top) {
            meter(usage)
            Button { exporting = true } label: { OCIcon("download") }.buttonStyle(OCButtonStyle(.ghost))
                .accessibilityLabel("Export session").accessibilityIdentifier("contextExport")
        }
        let columns = typeSize.isAccessibilitySize || width < 512 ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OCSpacing.lg, alignment: .topLeading), count: columns), alignment: .leading, spacing: OCSpacing.lg) {
            ForEach(stats(session, messages: messages, usage: usage, catalog: catalog), id: \.0) { label, value in
                VStack(alignment: .leading, spacing: OCSpacing.xs) {
                    Text(label).font(OCType.micro).foregroundStyle(OCColor.textMuted)
                    value.font(OCType.small.weight(.medium)).foregroundStyle(OCColor.text).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
            }
        }
        details(session, catalog: catalog)
        let todos = SessionTodo.current(messages, boundary: session.info.revert?.messageID)
        if !todos.isEmpty {
            section("Todo") {
                ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .firstTextBaseline, spacing: OCSpacing.sm) {
                        Text(Self.marker(todo.status)).font(OCType.code).foregroundStyle(todo.status == .inProgress ? OCColor.accent : OCColor.textMuted)
                        Text(todo.content).font(OCType.small).strikethrough(todo.status == .cancelled)
                            .foregroundStyle(todo.status == .completed || todo.status == .cancelled ? OCColor.textMuted : OCColor.text)
                    }.accessibilityElement(children: .combine).accessibilityValue(Self.statusName(todo.status))
                }
            }
        }
        if let servers = catalog?.mcp.value, !servers.isEmpty {
            section("MCP") {
                ForEach(servers) { mcp in
                    HStack(spacing: OCSpacing.sm) {
                        OCStatusDot(Self.tone(mcp.status))
                        Text(mcp.name).font(OCType.small)
                        Spacer(minLength: 0)
                        Text(Self.statusTitle(mcp.status)).font(OCType.micro).foregroundStyle(OCColor.textMuted)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        if let prompt = messages.last(where: { $0.type == "system" })?.text.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            section("System Prompt") {
                Text(prompt).font(OCType.small).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, OCSpacing.md).padding(.vertical, OCSpacing.sm).frame(maxWidth: .infinity, alignment: .leading)
                    .background(OCColor.surface, in: RoundedRectangle(cornerRadius: OCRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
            }
        }
        if !messages.isEmpty {
            section("Raw messages") {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(messages, id: \.id) { message in RawMessageRow(message: message, created: time(message.time.created)) }
                }
            }
        }
    }
    private func meter(_ usage: ContextUsage?) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Context").font(OCType.button)
                Spacer(minLength: 0)
                Text(usage?.percent.map { "\($0)%" } ?? "—").font(OCType.button)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(OCColor.layer2)
                    Capsule().fill(OCColor.accent).frame(width: geometry.size.width * min(1, Double(usage?.percent ?? 0) / 100))
                }
            }.frame(height: 6).accessibilityHidden(true)
            Text(usage.map { usage in usage.limit.map { Self.number(usage.total) + " of " + Self.number($0) + " tokens" } ?? Self.number(usage.total) + " tokens, limit unknown" } ?? "No usage yet")
                .font(OCType.micro).foregroundStyle(OCColor.textMuted)
        }.accessibilityElement(children: .combine).accessibilityLabel("Context window")
            .accessibilityValue(usage?.percent.map { "\($0) percent used" } ?? "Unknown")
            .accessibilityIdentifier("contextMeter")
    }
    private func stats(_ session: SessionModel, messages: [MessageFields], usage: ContextUsage?, catalog: LocationCatalog?) -> [(String, Text)] {
        let model = usage?.model ?? session.info.model
        let info = model.flatMap { ComposerPickers.model($0, in: catalog?.models.value ?? []) }
        let provider = model.map { model in catalog?.providers.value?.last { $0.id == model.providerID }?.name ?? model.providerID }
        let agent = session.info.agent ?? messages.last { $0.type == "assistant" }?.agent
        let variant = model?.variant.flatMap { $0 == "default" ? nil : $0 }
        let cost = store.family(session.id).reduce(0) { $0 + $1.info.cost }
        return [
            ("Session", Text(session.info.title ?? session.id)),
            ("Messages", Text(Self.number(Double(messages.count)))),
            ("Provider", Text(usage == nil ? "—" : provider ?? "—")),
            ("Model", Text(usage == nil ? "—" : info.map(ComposerPickers.displayName) ?? model?.id ?? "—")),
            ("Variant", Text(variant ?? "Default")),
            ("Agent", Text(agent?.capitalized ?? "—")),
            ("Context Limit", Text(usage?.limit.map(Self.number) ?? "—")),
            ("Total Tokens", Text(usage.map { Self.number($0.total) } ?? "—")),
            ("Usage", Text(usage?.percent.map { "\($0)%" } ?? "—")),
            ("Input Tokens", Text(usage.map { Self.number($0.input) } ?? "—")),
            ("Output Tokens", Text(usage.map { Self.number($0.output) } ?? "—")),
            ("Reasoning Tokens", Text(usage.map { Self.number($0.reasoning) } ?? "—")),
            ("Cache Tokens (read/write)", Text(usage.map { Self.number($0.cacheRead) + " / " + Self.number($0.cacheWrite) } ?? "— / —")),
            ("User Messages", Text(Self.number(Double(messages.filter { $0.type == "user" }.count)))),
            ("Assistant Messages", Text(Self.number(Double(messages.filter { $0.type == "assistant" }.count)))),
            ("Total Cost", Text(cost.formatted(.currency(code: "USD")))),
            ("Session Created", time(session.info.time.created)),
            ("Last Activity", time(usage?.created)),
        ]
    }
    private func details(_ session: SessionModel, catalog: LocationCatalog?) -> some View {
        section("Session") {
            row("ID") {
                HStack(spacing: OCSpacing.xs) {
                    Text(session.id).font(OCType.code).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    OCIconButton("Copy session ID", icon: "copy") { OCCopy.text(session.id) }
                }
            }
            // A session in a worktree runs in its own directory, beside the project's.
            let project = session.info.location.project?.directory ?? ""
            let worktree = !project.isEmpty && project != session.info.location.directory
            row(worktree ? "Worktree" : "Directory") { Text(session.info.location.directory).font(OCType.small).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            if worktree { row("Project") { Text(project).font(OCType.small).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
            if let branch = catalog?.vcs.value?["branch"]?["current"]?.stringValue { row("Branch") { OCLabel(branch, icon: "branch").font(OCType.small) } }
            row("Updated") { time(max(session.info.time.updated, session.info.time.created)).font(OCType.small) }
            if let parent = session.info.parentID {
                row("Parent") {
                    Button(store.sessions[parent]?.info.title ?? parent) { openSession(parent) }.buttonStyle(OCButtonStyle(.ghost))
                        .accessibilityIdentifier("contextParent")
                }
            }
            let children = store.sessions.values.filter { $0.info.parentID == session.id }.sorted { $0.info.time.created < $1.info.time.created }
            if !children.isEmpty {
                row("Subagents") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(children, id: \.id) { child in
                            Button(child.info.title ?? child.id) { openSession(child.id) }.buttonStyle(OCButtonStyle(.ghost))
                        }
                    }
                }
            }
            let review = store.review(sessionID: session.id, directory: session.info.location.directory)
            if !review.files.isEmpty {
                row("Changes") {
                    Button { showChanges() } label: {
                        HStack(spacing: OCSpacing.sm) {
                            Text("\(review.files.count) \(review.files.count == 1 ? "file" : "files")")
                            Text("+\(review.additions)").foregroundStyle(OCColor.success)
                            Text("−\(review.deletions)").foregroundStyle(OCColor.danger)
                        }
                    }.buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("contextChanges")
                }
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            Text(title).font(OCType.micro).foregroundStyle(OCColor.textMuted).accessibilityAddTraits(.isHeader)
            content()
        }
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize || width < 360 ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.xs)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OCSpacing.md))
        return layout {
            Text(title).font(OCType.small).foregroundStyle(OCColor.textMuted).frame(minWidth: typeSize.isAccessibilitySize ? nil : 96, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: OCLayout.touchTarget)
    }
    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
    /// The desktop's medium date and time, in the environment's locale and time zone.
    private func time(_ value: Double?) -> Text {
        guard let value, value > 0 else { return Text("—") }
        var style = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
        style.locale = locale; style.timeZone = timeZone
        return Text(Date(timeIntervalSince1970: value / 1_000).formatted(style))
    }
    static func marker(_ status: SessionTodo.Status) -> String {
        switch status { case .completed: "[✓]"; case .inProgress: "[•]"; case .cancelled: "[-]"; case .pending: "[ ]" }
    }
    static func statusName(_ status: SessionTodo.Status) -> String {
        switch status { case .completed: "Completed"; case .inProgress: "In progress"; case .cancelled: "Cancelled"; case .pending: "Pending" }
    }
    static func statusTitle(_ status: MCPStatus) -> String {
        switch status {
        case .connected: "Connected"; case .pending: "Connecting"; case .disabled: "Disabled"; case .needsAuth: "Needs sign-in"
        case .failed: status.error ?? "Failed"; case .unknown(let type, _): type; case .undecodable: "Unknown"
        }
    }
    static func tone(_ status: MCPStatus) -> OCTone {
        switch status { case .connected: .success; case .pending: .info; case .failed: .danger; case .needsAuth: .warning; default: .neutral }
    }
}

/// The iPhone's context sheet: the Context tab under the desktop's mobile title.
public struct ContextSheet: View {
    let store: ReadStore
    let sessionID: String
    let openSession: (String) -> Void
    let showChanges: () -> Void
    let close: () -> Void
    public init(store: ReadStore, sessionID: String, openSession: @escaping (String) -> Void = { _ in }, showChanges: @escaping () -> Void = {}, close: @escaping () -> Void) {
        self.store = store; self.sessionID = sessionID; self.openSession = openSession; self.showChanges = showChanges; self.close = close
    }
    public var body: some View {
        NavigationStack {
            ContextPanel(store: store, sessionID: sessionID, openSession: openSession, showChanges: showChanges)
                .ocNavigationTitle("Usage").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done", action: close).accessibilityIdentifier("closeContext") }
                }
        }
    }
}

/// One raw message, rendered as JSON only once it is expanded.
private struct RawMessageRow: View {
    let message: MessageFields
    let created: Text
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                Text((try? message.raw.prettyPrinted()) ?? "").font(OCType.code).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(OCSpacing.md).frame(maxWidth: .infinity, alignment: .leading).background(OCColor.backgroundDeep, in: RoundedRectangle(cornerRadius: OCRadius.md))
            }
        } label: {
            HStack(spacing: OCSpacing.sm) {
                Text("\(message.type) \(Text("• " + message.id).foregroundStyle(OCColor.textMuted))").font(OCType.small)
                Spacer(minLength: 0)
                created.font(OCType.micro).foregroundStyle(OCColor.textMuted)
            }.lineLimit(1).frame(minHeight: OCLayout.touchTarget)
        }.tint(OCColor.iconMuted)
    }
}
#endif

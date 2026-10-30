#if os(iOS)
import SwiftUI
import OCModels
import OCFoundation
import OCSync
import OCRender
import OCDesign

public struct ReviewScreen: View {
    @Bindable var model: ReviewModel
    let composer: ComposerModel
    let openFile: (ReviewPath, Int?) -> Void
    @AppStorage("reviewShowAll") private var showAll = false
    @AppStorage(OCWorkspaceLayout.reviewSplitKey) private var split = true
    @AppStorage("wrapLines") private var wrap = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var comment: OCDiffSelection?
    @State private var editing: LineComment?
    @State private var renderLarge = false
    @State private var regularWidth = false
    @State private var diffWidth: CGFloat = 0
    @State private var gitAction: GitQuickAction?
    @State private var gitError: String?
    public init(model: ReviewModel, composer: ComposerModel, openFile: @escaping (ReviewPath, Int?) -> Void) {
        self.model = model; self.composer = composer; self.openFile = openFile
    }
    public var body: some View {
        GeometryReader { geometry in
            let regular = geometry.size.width >= 480 && !typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                if let error = model.error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.sm).ocAnnounce(error, initial: true) }
                if (model.loading || model.awaitingProvider) && !model.loaded { ProgressView("Loading changes…").font(OCType.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if model.error != nil && !model.providerKnown {
                    OCEmptyState("Request failed", detail: "", icon: "warning", presentation: .panel) {
                        Button("Try again") { model.refresh() }.buttonStyle(OCButtonStyle())
                    }
                } else if model.loaded && model.vcs.provider == nil {
                    OCEmptyState("No tracked changes", detail: "Track, review, and undo changes in this project", icon: "review", presentation: .panel, fileIcon: ".gitignore") {
                        Button(model.creating ? "Creating Git repository…" : "Create Git repository") { model.initializeGit() }.buttonStyle(OCButtonStyle()).disabled(model.creating)
                    }
                } else if model.files.isEmpty {
                    sourceMenu.padding(OCSpacing.sm)
                    OCEmptyState(regular ? "No file changes yet" : model.source == .working ? "No uncommitted changes yet" : model.source == .branch ? "No branch changes yet" : "No changes", detail: regular ? "Project changes will appear here" : "", icon: "review", presentation: .panel) { EmptyView() }
                } else if regular {
                    HStack(spacing: 0) {
                        if model.sidebarVisible {
                            sidebar.frame(width: min(model.sidebarWidth, geometry.size.width - 200))
                            OCResizeHandle("Resize file tree", value: $model.sidebarWidth, range: WorkspaceWidths.reviewTreeMinimum...WorkspaceWidths.reviewTreeMaximum,
                                           reset: WorkspaceWidths.reviewTreeDefault)
                        }
                        preview
                    }
                } else { compact }
            }
            .onChange(of: regular, initial: true) { _, value in regularWidth = value }
            .sheet(item: Binding(get: { regular ? nil : comment }, set: { comment = $0 })) { selection in
                OCLineCommentEditor(file: selection.file, selection: selection.selection, initialText: "", editing: false) { text in
                    composer.addComment(.init(file: commentPath(selection.file), selection: selection.selection, comment: text, preview: selection.preview, deletedText: selection.deletedText)); comment = nil
                } cancel: { comment = nil }.ocSheet()
            }
            .sheet(item: Binding(get: { regular ? nil : editing }, set: { editing = $0 })) { value in
                OCLineCommentEditor(file: value.file, selection: value.selection, initialText: value.comment, editing: true) { text in
                    var next = value; next.comment = text; composer.updateComment(next); editing = nil
                } cancel: { editing = nil }.ocSheet()
            }
        }
        .onAppear { model.appear() }.onDisappear { model.disappear() }
        .sheet(item: $gitAction) { action in
            OCConfirmationSheet(action.title, message: action.message, detail: action.prompt, confirmTitle: action.confirmTitle, destructive: false,
                                cancel: { gitAction = nil }) {
                gitAction = nil
                Task { do { try await composer.sendAgentPrompt(action.prompt) } catch { gitError = WriteErrorMessage.message(error) } }
            }.ocSheet()
        }
        .alert("Could not send the prompt", isPresented: Binding(get: { gitError != nil }, set: { if !$0 { gitError = nil } })) {
            Button("OK") { gitError = nil }
        } message: { Text(gitError ?? "") }
        .onChange(of: phase) { _, phase in if phase == .active { model.invalidate() } }
    }
    private func commentPath(_ path: String) -> String { model.path(path)?.absolute ?? path }
    private var sourceMenu: some View {
        Group {
            if model.sources.count > 1 {
                Menu { ForEach(model.sources, id: \.key) { source in Button(source.title) { model.choose(source) } } } label: { OCLabel(model.source.title, icon: "branch").font(OCType.small) }.buttonStyle(OCButtonStyle(.ghost)).accessibilityLabel("Review source")
            } else { Text(model.source.title).font(OCType.small).frame(minHeight: OCLayout.touchTarget) }
        }
    }
    private var totals: some View {
        HStack(spacing: OCSpacing.xs) {
            Text("+\(model.additions)").foregroundStyle(OCColor.success); Text("−\(model.deletions)").foregroundStyle(OCColor.danger)
            gitMenu
        }.font(OCType.micro)
    }
    /// Commit and push, or open a pull request: prompts to the session's agent, shown before they are sent.
    private var gitMenu: some View {
        Menu {
            ForEach(GitQuickAction.allCases) { action in Button(action.title) { gitAction = action } }
        } label: { OCIcon("branch-out").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
            .accessibilityLabel("Git actions").accessibilityIdentifier("reviewGitActions")
            .disabled(model.vcs.provider == nil || composer.session == nil || composer.session?.info.parentID != nil)
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack { sourceMenu; Spacer(minLength: 0); totals }.padding(.horizontal, OCSpacing.sm)
            Text("\(model.reviewedCount) of \(model.files.count) reviewed").font(OCType.micro).foregroundStyle(OCColor.textMuted)
            TextField("Filter files", text: $model.filter).textFieldStyle(.plain).font(OCType.small).padding(OCSpacing.md).frame(minHeight: OCLayout.touchTarget)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(treeRows.enumerated()), id: \.offset) { _, entry in
                        if let file = entry.file {
                            Button { model.select(file.file) } label: {
                                HStack(spacing: OCSpacing.sm) {
                                    OCFileIcon(file.file)
                                    VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                                        if !model.filter.isEmpty {
                                            Text((file.file as NSString).deletingLastPathComponent).font(OCType.micro).foregroundStyle(OCColor.textMuted).lineLimit(1)
                                        }
                                        Text((file.file as NSString).lastPathComponent).font(OCType.small).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if model.isReviewed(file) { OCIcon("check") }
                                    if file.status == "added" || file.status == "deleted" { Text(file.status == "added" ? "A" : "D").font(OCType.micro).foregroundStyle(file.status == "added" ? OCColor.success : OCColor.danger) }
                                }.padding(.leading, CGFloat(entry.depth) * 16 + OCSpacing.sm).padding(.trailing, OCSpacing.sm).frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
                                    .background(model.selected?.file == file.file ? OCColor.pressed : .clear).background(OCColor.background).ocHover(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("reviewFile-" + file.file)
                                .accessibilityValue(model.selected?.file == file.file ? "Selected" : "")
                                .contextMenu {
                                    Button("Open file") { open(file) }
                                    Button("Mention in composer") { if let path = model.path(file.file) { composer.mentionFile(path.absolute, focus: true) } }
                                    Button(model.isReviewed(file) ? "Mark as not reviewed" : "Mark as reviewed") { model.mark(file, reviewed: !model.isReviewed(file)) }
                                }
                        } else { OCLabel(entry.name, icon: "folder").font(OCType.small).padding(.leading, CGFloat(entry.depth) * 16 + OCSpacing.sm).frame(maxWidth: .infinity, minHeight: OCLayout.touchTarget, alignment: .leading) }
                    }
                    if model.filteredFiles.isEmpty { Text("No results found").font(OCType.small).padding() }
                }
            }.refreshable { model.refresh() }
        }.background(OCColor.background)
    }
    private var treeRows: [(name: String, depth: Int, file: FileDiff?)] {
        var result: [(String, Int, FileDiff?)] = [], seen: Set<String> = []
        for file in model.filteredFiles {
            let parts = file.file.split(separator: "/")
            if model.filter.isEmpty && parts.count > 1 {
                for depth in 0..<(parts.count - 1) {
                    let directory = parts.prefix(depth + 1).joined(separator: "/")
                    if seen.insert(directory).inserted { result.append((String(parts[depth]), depth, nil)) }
                }
            }
            result.append((file.file, model.filter.isEmpty ? max(0, parts.count - 1) : 0, file))
        }; return result
    }
    private var toolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OCSpacing.xxs) {
                OCIconButton("Toggle file tree", icon: "file-tree") { model.sidebarVisible.toggle() }
                if !model.sidebarVisible { sourceMenu; totals; Text("\((model.orderedFiles.firstIndex { $0.file == model.selected?.file } ?? 0) + 1)/\(model.files.count)").font(OCType.micro) }
                OCIconButton("Previous file", icon: "chevron-left") { model.move(-1) }
                OCIconButton("Next file", icon: "chevron-right") { model.move(1) }
                OCIconButton(showAll ? "Hide non-diff lines" : "Show all lines", icon: "code-lines") { showAll.toggle() }
                Menu { Button("Unified") { split = false }; if diffWidth >= 560 { Button("Split") { split = true } }; Toggle("Wrap lines", isOn: $wrap) } label: { OCIcon(split && diffWidth >= 560 ? "split" : "unified").frame(width: 44, height: 44) }.accessibilityLabel("Diff view")
                if let file = model.selected { OCToggleRow("Reviewed", isOn: Binding(get: { model.isReviewed(file) }, set: { model.mark(file, reviewed: $0) })).fixedSize() }
            }
        }.scrollIndicators(.hidden)
    }
    private var preview: some View {
        VStack(spacing: 0) {
            toolbar
            if let file = model.selected {
                HStack(spacing: OCSpacing.sm) {
                    Text(file.status == "added" ? "A" : file.status == "deleted" ? "D" : "M").font(OCType.micro).foregroundStyle(OCColor.textMuted)
                    OCFileIcon(file.file)
                    VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                        Text((file.file as NSString).lastPathComponent).font(OCType.small).lineLimit(1)
                        let directory = (file.file as NSString).deletingLastPathComponent
                        if !directory.isEmpty { Text(directory).font(OCType.micro).foregroundStyle(OCColor.textMuted).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: OCSpacing.xs) { Text("+\(file.additions)").foregroundStyle(OCColor.success); Text("−\(file.deletions)").foregroundStyle(OCColor.danger) }.font(OCType.micro)
                    OCIconButton("Open file", icon: "open-file") { open(file) }
                }.padding(.horizontal, OCSpacing.sm).frame(minHeight: OCLayout.touchTarget)
                diff([file], headers: false).onGeometryChange(for: CGFloat.self) { $0.size.width } action: { diffWidth = $0 }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    private var compact: some View {
        VStack(spacing: 0) {
            HStack {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: OCSpacing.xs) { sourceMenu; totals }
                    Spacer(minLength: 0)
                } else { sourceMenu; Spacer(minLength: 0); totals }
                OCIconButton(model.state.openFiles.isEmpty ? "Expand all" : "Collapse all", icon: model.state.openFiles.isEmpty ? "expand" : "collapse") { model.expandAll(model.state.openFiles.isEmpty) }
            }.frame(minHeight: 40).padding(.horizontal, OCSpacing.sm)
            let optionsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.xs)) : AnyLayout(HStackLayout())
            optionsLayout { Text("\(model.reviewedCount) of \(model.files.count) reviewed").font(OCType.micro)
                if !typeSize.isAccessibilitySize { Spacer() }
                HStack {
                if case .turn = model.source {
                    OCIconButton("Previous file", icon: "chevron-left") { model.move(-1) }
                    OCIconButton("Next file", icon: "chevron-right") { model.move(1) }
                }
                Menu {
                    Toggle("Show all lines", isOn: $showAll)
                    ForEach(model.files, id: \.file) { file in Button((model.isReviewed(file) ? "Unmark " : "Reviewed ") + file.file) { model.mark(file, reviewed: !model.isReviewed(file)) } }
                } label: { Text("Review options").font(OCType.small).frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle()) }
                }
            }.padding(.horizontal, OCSpacing.sm)
            diff(model.files, headers: true)
        }
    }
    @ViewBuilder private func diff(_ files: [FileDiff], headers: Bool) -> some View {
        if !renderLarge && files.contains(where: { $0.changedLines > 20_000 }) {
            VStack { Text("Diff too large to render"); Button("Render anyway") { renderLarge = true }.buttonStyle(OCButtonStyle()) }.font(OCType.small)
        } else {
            OCDiffView(files.map { input($0, headers: headers) }, split: !headers && split, showAll: showAll, wrap: wrap, headers: headers,
                       comments: composer.comments.map { c in var c = c; c.file = files.first { commentPath($0.file) == c.file }?.file ?? c.file; return c },
                       selected: model.selection, selectedFile: model.selected?.file, scrollOffset: Binding(get: { model.scrollOffsets[headers ? "accordion" : model.selected?.file ?? ""] ?? 0 }, set: { model.scrollOffsets[headers ? "accordion" : model.selected?.file ?? ""] = $0 }),
                       onComment: { comment = $0; model.select($0.file); model.selection = $0.selection }, onToggle: { model.toggle($0) }, onOpen: { path in if let file = files.first(where: { $0.file == path }) { open(file) } },
                       onEdit: { value in editing = composer.comments.first { $0.id == value.id } }, onDelete: { composer.removeComment($0.id) }, inlineComment: regularWidth ? inlinePlacement : nil, inlineEditor: regularWidth && inlinePlacement != nil ? AnyView(inlineEditor) : nil, onMove: { model.move($0) }, refresh: { model.refresh() })
        }
    }
    private func input(_ file: FileDiff, headers: Bool) -> OCDiffInput {
        let image = FileContent.image(file.file)
        let message: String? = image ? (file.status == "deleted" ? "Removed image file." : model.imageErrors.contains(file.file) ? "Unable to load image." : "Loading…") : nil
        return .init(path: file.file, text: file.patch, fullFile: file["bounded"]?.boolValue != true,
                     expanded: !headers || model.isOpen(file.file), summary: "\(file.status == "added" ? "Added" : file.status == "deleted" ? "Removed" : "Modified") +\(file.additions) −\(file.deletions)",
                     imageData: image ? model.images[file.file] : nil, mediaMessage: message)
    }
    private var inlinePlacement: LineComment? {
        if let value = comment { return .init(id: "editor", file: value.file, selection: value.selection, comment: "", time: .distantPast) }
        if var value = editing { value.file = model.files.first { commentPath($0.file) == value.file }?.file ?? value.file; return value }
        return nil
    }
    @ViewBuilder private var inlineEditor: some View {
        if let value = comment {
            OCLineCommentEditor(file: value.file, selection: value.selection, initialText: "", editing: false, showsFile: false) { text in
                composer.addComment(.init(file: commentPath(value.file), selection: value.selection, comment: text, preview: value.preview, deletedText: value.deletedText)); comment = nil
            } cancel: { comment = nil }.id(value.id)
        } else if let value = editing {
            OCLineCommentEditor(file: value.file, selection: value.selection, initialText: value.comment, editing: true, showsFile: false) { text in
                var next = value; next.comment = text; composer.updateComment(next); editing = nil
            } cancel: { editing = nil }.id(value.id)
        }
    }
    private func open(_ file: FileDiff) { if let path = model.path(file.file) { openFile(path, DiffParser.parse(file.patch).firstChangedLine) } }
}
#endif

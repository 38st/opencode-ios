#if os(iOS)
import SwiftUI
import QuickLook
import OCModels
import OCSync
import OCDesign
import OCRender

public struct FilesScreen: View {
    @Bindable var model: FilesModel
    let composer: ComposerModel
    let changes: [FileDiff]
    @AppStorage("wrapLines") private var wrap = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var sidebarWidth: Double = 240
    @State private var preview = true
    @State private var finding = false
    @State private var find = ""
    @State private var matchIndex = 0
    /// Names this viewer to the menu bar's Find.
    @State private var findOwner = UUID()
    @State private var search = CodeSearchResult()
    @State private var comment: OCDiffSelection?
    @State private var quickLook = false
    @State private var editing: LineComment?
    @State private var regularWidth = false
    @State private var resultIndex = 0
    @FocusState private var filterFocused: Bool
    @FocusState private var findFocused: Bool
    public init(model: FilesModel, composer: ComposerModel, changes: [FileDiff] = []) { self.model = model; self.composer = composer; self.changes = changes }
    public var body: some View {
        GeometryReader { geometry in
            let regular = geometry.size.width >= 480 && !typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: OCSpacing.xs) {
                        Button("All files") { model.allFiles() }.buttonStyle(OCTabStyle(selected: model.selectedPath == nil))
                        ForEach(model.openFiles, id: \.absolute) { path in
                            HStack(spacing: 0) {
                                Button((path.path as NSString).lastPathComponent) { model.open(path) }.buttonStyle(OCTabStyle(selected: model.selectedPath == path))
                                OCIconButton("Close tab", icon: "close") { model.close(path) }
                            }
                        }
                    }
                }.accessibilityLabel("Open files").scrollIndicators(.hidden)
                HStack(spacing: 0) {
                    if regular || model.selectedPath == nil {
                        browser.frame(width: regular ? min(sidebarWidth, geometry.size.width - 200) : nil)
                        if regular {
                            OCResizeHandle("Resize file tree", value: $sidebarWidth, range: WorkspaceWidths.reviewTreeMinimum...WorkspaceWidths.reviewTreeMaximum,
                                           reset: WorkspaceWidths.reviewTreeDefault)
                        }
                    }
                    if model.selectedPath != nil { viewer }
                    else if regular { OCEmptyState("Open a file", detail: "Choose a file from the tree", icon: "file-tree") { EmptyView() } }
                }
            }.onChange(of: regular, initial: true) { _, value in regularWidth = value }
        }
        .onAppear { model.appear() }.onDisappear { model.disappear() }
        .onChange(of: phase) { _, phase in if phase == .active { model.invalidate() } }
        .sheet(item: Binding(get: { regularWidth ? nil : comment }, set: { comment = $0 })) { value in
            OCLineCommentEditor(file: value.file, selection: value.selection, initialText: "", editing: false) { text in
                composer.addComment(.init(file: value.file, selection: value.selection, comment: text, origin: "file", preview: value.preview)); comment = nil
            } cancel: { comment = nil }.ocSheet()
        }
        .sheet(item: Binding(get: { regularWidth ? nil : editing }, set: { editing = $0 })) { value in
            OCLineCommentEditor(file: value.file, selection: value.selection, initialText: value.comment, editing: true) { text in
                var value = value; value.comment = text; composer.updateComment(value); editing = nil
            } cancel: { editing = nil }.ocSheet()
        }
        .sheet(isPresented: $quickLook) { if let url = model.localURL { QuickLookView(url: url).ocSheet() } }
        .confirmationDialog("Download file?", isPresented: $model.needsDownloadConfirmation) {
            Button("Download") { model.loadMore(all: true) }; Button("Cancel", role: .cancel) { model.cancel() }
        } message: { Text("This file is larger than 100 MiB.") }
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text((model.directory as NSString).lastPathComponent).font(OCType.button).padding(OCSpacing.md)
            TextField("Filter files", text: $model.query).font(OCType.small).padding(OCSpacing.md).frame(minHeight: 44)
                .focused($filterFocused)
                .onChange(of: model.query) { _, _ in resultIndex = 0 }
                .onSubmit { openResult() }
                .onKeyPress(.upArrow) { resultIndex = max(0, resultIndex - 1); return .handled }
                .onKeyPress(.downArrow) { resultIndex = min(max(0, model.results.count - 1), resultIndex + 1); return .handled }
                .onKeyPress(.escape) { model.query = ""; return .handled }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.query.isEmpty {
                        ForEach(Array(tree.enumerated()), id: \.offset) { _, item in
                            row(item.entry, depth: item.depth)
                            if model.expanded.contains(item.entry.path), model.listingErrors.contains(item.entry.path) {
                                Button("Failed to list files") { model.loadDirectory(item.entry.path, force: true) }
                                    .buttonStyle(OCButtonStyle(.ghost)).padding(.leading, CGFloat(item.depth + 1) * 16)
                                    .accessibilityHint("Retry")
                            }
                        }
                        if model.listingErrors.contains("") { Text("Failed to list files").font(OCType.small).padding() }
                    } else {
                        ForEach(model.results, id: \.path) { row($0, depth: 0) }
                        if model.results.isEmpty { Text("No results found").font(OCType.small).padding() }
                    }
                }
            }.refreshable { model.invalidate() }
        }
    }
    private var tree: [(entry: FileEntry, depth: Int)] {
        var result: [(FileEntry, Int)] = []
        func visit(_ path: String, depth: Int) {
            guard depth < 100 else { return }
            for entry in model.children[path] ?? [] {
                result.append((entry, depth)); if entry.type == .directory, model.expanded.contains(entry.path) { visit(entry.path, depth: depth + 1) }
            }
        }; visit("", depth: 0); return result
    }
    private func row(_ entry: FileEntry, depth: Int) -> some View {
        Button {
            if entry.type == .directory { model.toggle(entry.path) }
            else if let path = ReviewPath(entry.path, root: .location, location: model.directory, project: model.projectDirectory) { filterFocused = false; model.open(path) }
        } label: {
            HStack(spacing: OCSpacing.sm) {
                if entry.type == .directory { OCIcon(model.expanded.contains(entry.path) ? "chevron-down" : "chevron-right", size: 12) }
                OCFileIcon(entry.path, directory: entry.type == .directory)
                if !model.query.isEmpty { Text((entry.path as NSString).deletingLastPathComponent).font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(1) }
                Text((entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).lastPathComponent).font(OCType.small).lineLimit(1)
                Spacer(minLength: 0)
                if let status = status(entry) { Text(status).font(OCType.micro).foregroundStyle(OCColor.textMuted) }
            }.padding(.leading, CGFloat(depth) * 16 + OCSpacing.sm).padding(.trailing, OCSpacing.sm).frame(minHeight: 44).contentShape(Rectangle()).ocHover()
        }.buttonStyle(.plain).accessibilityIdentifier("fileEntry-" + entry.path).background(!model.query.isEmpty && model.results.indices.contains(resultIndex) && model.results[resultIndex].path == entry.path ? OCColor.layer2 : OCColor.background).contextMenu {
            if entry.type != .directory, let path = ReviewPath(entry.path, root: .location, location: model.directory, project: model.projectDirectory) {
                Button("Open") { filterFocused = false; model.open(path) }
            }
            Button("Mention in composer") { composer.mentionFile(ComposerInput.absolute(entry.path, directory: model.directory), focus: regularWidth) }
            Button("Copy path") { OCCopy.text(ComposerInput.absolute(entry.path, directory: model.directory)) }
        }.onDrag { Self.mentionProvider(ComposerInput.absolute(entry.path, directory: model.directory)) }
    }
    /// A file dropped on the composer becomes an @file mention; other apps receive the path as text.
    static func mentionProvider(_ path: String) -> NSItemProvider {
        let provider = NSItemProvider(object: path as NSString)
        provider.registerDataRepresentation(forTypeIdentifier: ComposerDrop.mentionType, visibility: .ownProcess) { done in
            done(ComposerDrop.mentionPayload(path), nil); return nil
        }
        provider.suggestedName = (path as NSString).lastPathComponent
        return provider
    }
    /// Find in this file, from the Find button, its ⌘F or the menu bar's Find.
    private func openFind() { finding = true; preview = false; findFocused = true }
    private var findable: Bool {
        guard let path = model.selectedPath, let content = model.content else { return false }
        return !FileContent.image(path.path) && !FileContent.quickLook(path.path) && !content.binary
    }
    private func openResult() {
        guard model.results.indices.contains(resultIndex), let path = ReviewPath(model.results[resultIndex].path, root: .location, location: model.directory, project: model.projectDirectory) else { return }
        filterFocused = false; model.open(path)
    }
    private func status(_ entry: FileEntry) -> String? {
        let values = changes.filter { $0.file == entry.path || entry.type == .directory && $0.file.hasPrefix(entry.path) }
        guard !values.isEmpty else { return nil }
        return values.allSatisfy { $0.status == "added" } ? "A" : values.allSatisfy { $0.status == "deleted" } ? "D" : "M"
    }
    private var inlinePlacement: LineComment? {
        if let value = comment { return .init(id: "editor", file: value.file, selection: value.selection, comment: "", time: .distantPast) }
        return editing
    }
    @ViewBuilder private var inlineEditor: some View {
        if let value = comment {
            OCLineCommentEditor(file: value.file, selection: value.selection, initialText: "", editing: false, showsFile: false) { text in
                composer.addComment(.init(file: value.file, selection: value.selection, comment: text, origin: "file", preview: value.preview)); comment = nil
            } cancel: { comment = nil }.id(value.id)
        } else if let value = editing {
            OCLineCommentEditor(file: value.file, selection: value.selection, initialText: value.comment, editing: true, showsFile: false) { text in
                var next = value; next.comment = text; composer.updateComment(next); editing = nil
            } cancel: { editing = nil }.id(value.id)
        }
    }
    private var currentMatch: CodeSearchMatch? { search.matches.indices.contains(matchIndex) ? search.matches[matchIndex] : nil }
    private func nextMatch(_ delta: Int) {
        guard !search.matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + search.matches.count) % search.matches.count
        model.selection = .init(start: search.matches[matchIndex].line)
    }
    private var viewer: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack {
                    // The button owns ⌘F: on iPadOS a menu item's ⌘F does not run, as the system's Edit ▸ Find has it.
                    OCIconButton("Find", icon: "magnifying-glass") { openFind() }.keyboardShortcut(WorkspaceKeys.FilesViewer.find.keyboardShortcut)
                    Button("Mention in composer") { if let path = model.selectedPath { composer.mentionFile(path.absolute, focus: regularWidth) } }.buttonStyle(OCButtonStyle(.ghost))
                    if model.selectedPath?.path.lowercased().hasSuffix(".md") == true { Button(preview ? "Source" : "Preview") { preview.toggle() }.buttonStyle(OCButtonStyle(.ghost)) }
                    if model.loading { Button("Cancel") { model.cancel() }.buttonStyle(OCButtonStyle(.ghost)) }
                }
            }.scrollIndicators(.hidden)
            if finding {
                HStack {
                    TextField("Find", text: $find).font(OCType.small).frame(minHeight: OCLayout.touchTarget).onSubmit { nextMatch(1) }
                        .focused($findFocused).onAppear { findFocused = true }
                    Text(search.matches.isEmpty ? "0/0" : "\(matchIndex + 1)/\(search.matches.count)").font(OCType.micro).accessibilityLabel("Search matches").accessibilityValue(search.matches.isEmpty ? "0 of 0" : "\(matchIndex + 1) of \(search.matches.count)")
                    OCIconButton("Previous match", icon: "chevron-up") { nextMatch(-1) }.disabled(search.matches.isEmpty)
                    OCIconButton("Next match", icon: "chevron-down") { nextMatch(1) }.disabled(search.matches.isEmpty)
                    OCIconButton("Close search", icon: "close") { finding = false }
                }.padding(.horizontal, OCSpacing.sm)
            }
            if let error = model.error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding().ocAnnounce(error, initial: true) }
            if let content = model.content, let path = model.selectedPath {
                if !content.complete {
                    if FileContent.image(path.path) || FileContent.quickLook(path.path) {
                        VStack(alignment: .leading, spacing: OCSpacing.xs) {
                            ProgressView(value: Double(content.data.count), total: Double(content.total)) {
                                Text("\(content.data.count.formatted(.byteCount(style: .file))) of \(content.total.formatted(.byteCount(style: .file)))").font(OCType.micro)
                            }.tint(OCColor.accent)
                            if !model.loading {
                                Button("Download") {
                                    if content.total > 100 * 1_048_576 { model.needsDownloadConfirmation = true }
                                    else { model.loadMore(all: true) }
                                }.buttonStyle(OCButtonStyle(.ghost))
                            }
                        }.padding(OCSpacing.sm)
                    } else {
                        HStack { Text("Showing the first \(content.binary ? content.data.count : content.text.utf8.count) of \(content.total)").font(OCType.micro); Button("Load more") { model.loadMore() }.buttonStyle(OCButtonStyle(.ghost)).disabled(model.loading) }.padding(OCSpacing.sm)
                    }
                }
                if FileContent.image(path.path) {
                    if let image = UIImage(data: content.data), content.complete { ZoomImage(image: image) }
                    else { Text(model.loading ? "Loading…" : "Unable to load image.").font(OCType.small) }
                } else if FileContent.quickLook(path.path) {
                    Button("Preview \((path.path as NSString).lastPathComponent)") { quickLook = true }.buttonStyle(OCButtonStyle()).disabled(model.localURL == nil)
                } else if content.binary { Text("Binary file · \(content.total.formatted(.byteCount(style: .file)))").font(OCType.small) }
                else if path.path.lowercased().hasSuffix(".md") && preview { ScrollView { StreamingMarkdownView(content.text).padding(OCSpacing.md) } }
                else {
                    OCDiffView([.init(path: path.absolute, text: content.text, source: true)], wrap: wrap, comments: composer.comments, selected: model.selection, search: search, currentMatch: currentMatch,
                               scrollOffset: Binding(get: { model.scrollOffsets[path.absolute] ?? 0 }, set: { model.scrollOffsets[path.absolute] = $0 }), onComment: { comment = $0; model.selection = $0.selection }, onEdit: { editing = $0 }, onDelete: { composer.removeComment($0.id) }, inlineComment: regularWidth ? inlinePlacement : nil, inlineEditor: regularWidth && inlinePlacement != nil ? AnyView(inlineEditor) : nil, refresh: { model.invalidate() })
                }
            } else if model.loading { ProgressView("Loading…").font(OCType.small) }
            Spacer(minLength: 0)
        }.focusedSceneValue(\.ocFindCommand, findable ? OCFindCommand(owner: findOwner, id: model.selectedPath?.absolute ?? "", perform: openFind) : nil)
        .task(id: SearchRequest(query: finding ? find : "", text: model.content?.text ?? "")) {
            let result = await CodeSearchResult.find(finding ? find : "", in: model.content?.text ?? "")
            guard !Task.isCancelled else { return }; search = result; matchIndex = 0; nextMatch(0)
        }
    }
    private struct SearchRequest: Equatable { let query: String; let text: String }
}
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let view = QLPreviewController(); view.dataSource = context.coordinator; return view }
    func updateUIViewController(_ view: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
private struct ZoomImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    var body: some View {
        VStack {
            Button("Fit") { scale = 1 }.buttonStyle(OCButtonStyle(.ghost))
            GeometryReader { geometry in
                let fit = min(1, geometry.size.width / max(1, image.size.width), geometry.size.height / max(1, image.size.height))
                let zoom = min(8, max(0.25, scale * pinch))
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image).resizable()
                        .frame(width: image.size.width * fit * zoom, height: image.size.height * fit * zoom)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { scale = min(8, max(0.25, scale * $0.magnification)) })
                }
            }
        }
    }
}
#endif

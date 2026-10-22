import SwiftUI
import OCModels
import OCRender

public struct DiffCardView: View {
    let file: String
    let patch: String
    let additions: Int
    let deletions: Int
    let defaultExpanded: Bool
    @State private var expanded: Bool
    @State private var selecting = false
    @AppStorage("reviewShowAll") private var showAll = false
    @AppStorage("reviewSplit") private var split = true
    @AppStorage("wrapLines") private var wrap = true
    #if os(iOS)
    @State private var comment: OCDiffSelection?
    @State private var editing: LineComment?
    #endif
    @Environment(\.ocFileLinks) private var fileLinks
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(file: String, patch: String, additions: Int, deletions: Int, expanded: Bool = false) {
        self.file = file; self.patch = patch; self.additions = additions; self.deletions = deletions
        defaultExpanded = expanded; _expanded = State(initialValue: expanded)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if fileLinks != nil { header }
            else { Button { expanded.toggle() } label: { header }.buttonStyle(.plain) }
            if expanded {
                #if os(iOS)
                diff(full: false).frame(height: min(4_800, max(48, CGFloat(patch.components(separatedBy: "\n").count) * 24)))
                Button("Show full diff") { selecting = true }.buttonStyle(OCButtonStyle()).padding(OCSpacing.sm)
                #else
                CodeBlockView(patch)
                #endif
            }
        }.background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
            .onChange(of: defaultExpanded) { _, value in expanded = value }
            #if os(iOS)
            .sheet(item: Binding(get: { selecting ? nil : comment }, set: { comment = $0 })) { value in commentEditor(value) }
            .sheet(item: Binding(get: { selecting ? nil : editing }, set: { editing = $0 })) { value in editComment(value) }
            #endif
            .sheet(isPresented: $selecting) {
                #if os(iOS)
                fullViewer.ocSheet()
                    .sheet(item: $comment) { value in commentEditor(value) }
                    .sheet(item: $editing) { value in editComment(value) }
                #else
                OCTextSelectionSheet(text: patch).ocSheet()
                #endif
            }
    }
    private func openFile() { fileLinks?.open(file + (DiffParser.parse(patch).firstChangedLine.map { ":\($0)" } ?? "")) }
    @ViewBuilder private var fileTitle: some View {
        if fileLinks != nil {
            Button(action: openFile) { Text(file).font(OCType.small).lineLimit(1).truncationMode(.middle).frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityHint("Open file")
        } else { Text(file).font(OCType.small).lineLimit(1).truncationMode(.middle) }
    }
    private var header: some View {
        HStack(spacing: OCSpacing.sm) {
            OCIcon("code").foregroundStyle(OCColor.iconMuted)
            if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: OCSpacing.xs) { fileTitle; counts } }
            else { fileTitle; counts }
            Spacer(minLength: 0)
            if fileLinks != nil {
                OCIconButton(expanded ? "Collapse diff" : "Expand diff", icon: expanded ? "chevron-down" : "chevron-right") { expanded.toggle() }
            } else { OCIcon(expanded ? "chevron-down" : "chevron-right", size: 12) }
        }.font(OCType.micro).padding(OCSpacing.md).frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
            .fixedSize(horizontal: false, vertical: true)
    }
    #if os(iOS)
    private func diff(full: Bool) -> some View {
        OCDiffView([.init(path: file, text: patch)], split: full && split, showAll: showAll, wrap: wrap, comments: (fileLinks?.comments(file) ?? []).map { var value = $0; value.file = file; return value }, onComment: { comment = $0 }, onOpen: { _ in openFile() }, onEdit: { value in
            editing = fileLinks?.comments(file).first { $0.id == value.id }
        }, onDelete: { fileLinks?.removeComment($0.id) })
    }
    private var fullViewer: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    HStack {
                        OCIconButton(showAll ? "Hide non-diff lines" : "Show all lines", icon: "code-lines") { showAll.toggle() }
                        Menu {
                            Button("Unified") { split = false }
                            if geometry.size.width >= 560 && !typeSize.isAccessibilitySize { Button("Split") { split = true } }
                            Toggle("Wrap lines", isOn: $wrap)
                        } label: { OCIcon(split && geometry.size.width >= 560 && !typeSize.isAccessibilitySize ? "split" : "unified").frame(width: 44, height: 44) }
                            .accessibilityLabel("Diff view")
                        Spacer(minLength: 0)
                        if fileLinks != nil { Button("Open file") { selecting = false; openFile() }.buttonStyle(OCButtonStyle(.ghost)) }
                    }.padding(.horizontal, OCSpacing.sm)
                    diff(full: true)
                }
            }.ocNavigationTitle(file)
                .toolbar { ToolbarItem(placement: .cancellationAction) { OCIconButton("Close diff", icon: "close") { selecting = false } } }
        }
    }
    private func editComment(_ value: LineComment) -> some View {
        OCLineCommentEditor(file: value.file, selection: value.selection, initialText: value.comment, editing: true) { text in
            var value = value; value.comment = text; fileLinks?.updateComment(value); editing = nil
        } cancel: { editing = nil }.ocSheet()
    }
    private func commentEditor(_ value: OCDiffSelection) -> some View {
        OCLineCommentEditor(file: value.file, selection: value.selection, initialText: "", editing: false) { text in
            fileLinks?.comment?(.init(file: value.file, selection: value.selection, comment: text, preview: value.preview, deletedText: value.deletedText)); comment = nil
        } cancel: { comment = nil }.ocSheet()
    }
    #endif
    private var counts: some View {
        HStack(spacing: OCSpacing.sm) {
            Text("+\(additions)").foregroundStyle(OCColor.success)
            Text("−\(deletions)").foregroundStyle(OCColor.danger)
        }.fixedSize()
    }
}

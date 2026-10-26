import SwiftUI
import OCModels

public struct OCLineCommentEditor: View {
    let file: String
    let selection: LineSelection?
    let editing: Bool
    let showsFile: Bool
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var fieldHeight = 80.0
    public init(file: String, selection: LineSelection?, initialText: String, editing: Bool, showsFile: Bool = true, submit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.file = file; self.selection = selection; self.editing = editing; self.showsFile = showsFile; self.submit = submit; self.cancel = cancel; _text = State(initialValue: initialText)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.md) {
            Text("Comment").font(OCType.button)
            if showsFile { Text(file).font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(2) }
            ZStack(alignment: .topLeading) {
                if text.isEmpty { Text("Add context for this change").foregroundStyle(OCColor.textFaint).padding(OCSpacing.sm) }
                #if os(iOS)
                CommentTextView(text: $text, submit: { submit(text) }, cancel: cancel).frame(height: min(160, fieldHeight))
                #else
                TextEditor(text: $text).focused($focused).scrollContentBackground(.hidden).frame(height: min(160, fieldHeight)).accessibilityLabel("Add context for this change")
                #endif
            }.font(OCType.small).background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.md))
                .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.focus, lineWidth: OCBorder.hairline))
            let footer = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.sm)) : AnyLayout(HStackLayout(spacing: OCSpacing.sm))
            footer {
                if let selection { Text(selection.label).font(OCType.micro).foregroundStyle(OCColor.textFaint) }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: OCSpacing.sm) {
                    Button("Cancel", action: cancel).buttonStyle(OCButtonStyle(.ghost)).keyboardShortcut(.cancelAction)
                    Button(editing ? "Save" : "Comment") { submit(text) }.buttonStyle(OCButtonStyle(.contrast)).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.return, modifiers: .command)
                }
            }
        }.padding(OCSpacing.md).frame(maxWidth: 400)
            .background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
            .onAppear { focused = true }
    }
}

public struct OCCommentCard: View {
    let comment: LineComment
    let edit: (() -> Void)?
    let delete: (() -> Void)?
    public init(_ comment: LineComment, edit: (() -> Void)? = nil, delete: (() -> Void)? = nil) { self.comment = comment; self.edit = edit; self.delete = delete }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack { OCFileIcon(comment.file); Text((comment.file as NSString).lastPathComponent).font(OCType.small).lineLimit(1); Spacer(minLength: 0)
                if edit != nil || delete != nil { Menu { if let edit { Button("Edit", action: edit) }; if let delete { Button("Delete", action: delete) } } label: { OCIcon("dot-grid").frame(width: 44, height: 44) }.accessibilityLabel("More options") }
            }
            if let selection = comment.selection { Text(selection.label).font(OCType.micro).foregroundStyle(OCColor.textMuted) }
            Text(comment.comment).font(OCType.small).fixedSize(horizontal: false, vertical: true)
        }.padding(OCSpacing.md).frame(maxWidth: 320, alignment: .leading)
            .background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
    }
}

#if os(iOS)
import SwiftUI
import UIKit
import OCModels

struct CommentTextView: UIViewRepresentable {
    @Binding var text: String
    let submit: () -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> CommentEditorView {
        OCFonts.register()
        let view = CommentEditorView()
        view.backgroundColor = .clear
        view.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: UIFont(name: "Inter-Regular", size: 13) ?? .preferredFont(forTextStyle: .footnote))
        view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(OCColor.text)
        view.tintColor = UIColor(OCColor.accent)
        view.accessibilityLabel = "Add context for this change"
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: CommentEditorView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.submit = { if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submit() } }
        view.cancel = cancel
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CommentTextView
        init(_ parent: CommentTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}
final class CommentEditorView: UITextView {
    var submit: (() -> Void)?
    var cancel: (() -> Void)?
    private var focusTask: Task<Void, Never>?
    deinit { focusTask?.cancel() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        focusTask?.cancel()
        guard window != nil else { return }
        // A collection cell may attach during a SwiftUI update; focus on the next turn.
        focusTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, window != nil else { return }
            becomeFirstResponder()
        }
    }
    override var keyCommands: [UIKeyCommand]? {
        guard markedTextRange == nil else { return super.keyCommands }
        return [WorkspaceKeys.CommentEditor.submit.keyCommand(#selector(send)), WorkspaceKeys.CommentEditor.cancel.keyCommand(#selector(dismissEditor))]
    }
    @objc private func send() { submit?() }
    @objc private func dismissEditor() { cancel?() }
}
#endif

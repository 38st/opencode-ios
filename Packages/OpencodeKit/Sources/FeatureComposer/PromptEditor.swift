#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OCModels
import OCDesign

/// Keys that only make sense while the prompt is being edited, plus the menu keys the editor forwards
/// (`WorkspaceKeys.forwarded`). The menu bar owns the rest (⌘., ⌘', ⇧⌘D, ⌘U, ⌘N).
enum ComposerKey: Equatable { case send, escape, up, down, tab, emptyBackspace, menu(WorkspaceCommand) }

/// TextKit 2 lets a pre-edit delegate expand deletion to a complete mention and
/// keeps marked text untouched while the SwiftUI projection catches up.
struct PromptEditor: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var caret: Int
    var shell: Bool
    var enabled: Bool
    var placeholder = ""
    var suggestionsActive = false
    var focusRequest: UUID?
    var pasteAttachment: (NSItemProvider) -> Void = { _ in }
    /// A file dragged from the Files tab, with the UTF-16 offset it was dropped at.
    var dropMention: (String, Int) -> Void = { _, _ in }
    /// Whether an input method holds marked text.
    var composing: (Bool) -> Void = { _ in }
    var key: (ComposerKey) -> Bool
    func makeUIView(context: Context) -> EditorView {
        let view = EditorView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.pasteDelegate = context.coordinator
        view.textDropDelegate = context.coordinator
        // Drops go through the same paste configuration: text is inserted where it lands, media become attachments.
        view.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [ComposerDrop.mentionType, UTType.plainText.identifier, UTType.image.identifier, UTType.pdf.identifier, UTType.fileURL.identifier])
        view.backgroundColor = .clear
        view.textContainerInset = .init(top: OCSpacing.lg, left: OCSpacing.md, bottom: OCSpacing.sm, right: OCSpacing.md)
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityLabel = "Prompt"
        view.accessibilityIdentifier = "promptEditor"
        view.keyboardDismissMode = .interactive
        view.updateStyle(shell: shell)
        view.key = key
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: EditorView, context: Context) {
        context.coordinator.parent = self; view.key = key; view.suggestionsActive = suggestionsActive; view.composing = composing
        guard view.markedTextRange == nil else { return }
        view.updateStyle(shell: shell)
        view.placeholder = placeholder
        if Self.attributed(view.attributedText) != text {
            let value = Self.native(text, shell: shell, traits: view.traitCollection)
            context.coordinator.updating = true
            view.apply(value, selection: NSRange(location: min(caret, value.length), length: 0), resetUndo: value.length == 0)
            context.coordinator.updating = false
        }
        view.resetTypingAttributes()
        view.focusRequest = focusRequest
        view.scheduleFocusRequest()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EditorView, context: Context) -> CGSize? {
        let size = uiView.sizeThatFits(.init(width: proposal.width ?? 320, height: .greatestFiniteMagnitude))
        return .init(width: proposal.width ?? size.width, height: max(OCComposerMetrics.editorMinimum, min(OCComposerMetrics.editorMaximum, size.height)))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static let tokenKey = NSAttributedString.Key("app.opencode.mention")
    static func attributed(_ native: NSAttributedString) -> AttributedString {
        var value = AttributedString(native.string)
        native.enumerateAttribute(tokenKey, in: NSRange(location: 0, length: native.length)) { token, nsRange, _ in
            guard let data = token as? Data, let token = try? JSONDecoder().decode(DraftMention.self, from: data),
                  let range = Range(nsRange, in: native.string), let start = AttributedString.Index(range.lowerBound, within: value),
                  let end = AttributedString.Index(range.upperBound, within: value) else { return }
            value[start..<end][MentionAttribute.self] = token
        }
        return value
    }
    static func native(_ text: AttributedString, shell: Bool, traits: UITraitCollection) -> NSAttributedString {
        let value = NSMutableAttributedString(string: String(text.characters), attributes: [.font: OCType.editorFont(shell: shell, traits: traits), .foregroundColor: UIColor(OCColor.text),
                                                                                          .paragraphStyle: OCType.editorParagraphStyle(traits: traits)])
        for run in text.runs {
            guard let token = run[MentionAttribute.self], let data = try? JSONEncoder().encode(token) else { continue }
            let offset = String(text[..<run.range.lowerBound].characters).utf16.count
            let range = NSRange(location: offset, length: String(text[run.range].characters).utf16.count)
            value.addAttributes([tokenKey: data, .foregroundColor: UIColor(OCMentionStyle.color(token.kind))], range: range)
        }
        return value
    }
    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate, UITextDropDelegate {
        var parent: PromptEditor
        var updating = false
        /// Where the current drop lands; nil for a paste.
        private var dropOffset: Int?
        init(_ parent: PromptEditor) { self.parent = parent }
        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting, transform item: any UITextPasteItem) {
            if item.itemProvider.registeredTypeIdentifiers.contains(ComposerDrop.mentionType) {
                let provider = item.itemProvider
                let offset = dropOffset ?? (textPasteConfigurationSupporting as? UITextView)?.selectedRange.location ?? 0
                item.setNoResult()
                Task { [weak self] in
                    guard let data = try? await ComposerMedia.data(provider, type: ComposerDrop.mentionType),
                          let path = ComposerDrop.mentionPath(data) else { return }
                    self?.parent.dropMention(path, offset)
                }
            } else if [UTType.image, .pdf, .fileURL].contains(where: { item.itemProvider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                parent.pasteAttachment(item.itemProvider); item.setNoResult()
            } else { item.setDefaultResult() }
        }
        func textDroppableView(_ textDroppableView: any UIView & UITextDroppable, willPerformDrop drop: any UITextDropRequest) {
            dropOffset = textDroppableView.offset(from: textDroppableView.beginningOfDocument, to: drop.dropPosition)
        }
        func textDroppableView(_ textDroppableView: any UIView & UITextDroppable, dropSessionDidEnd session: any UIDropSession) { dropOffset = nil }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.enabled else { return false }
            guard textView.markedTextRange == nil else { return true }
            if text.isEmpty, range.length == 0, textView.text.isEmpty, parent.shell { return !parent.key(.emptyBackspace) }
            var expanded = range
            textView.attributedText.enumerateAttribute(PromptEditor.tokenKey, in: NSRange(location: 0, length: textView.attributedText.length)) { token, tokenRange, _ in
                guard token != nil else { return }
                if NSIntersectionRange(range, tokenRange).length > 0 { expanded = NSUnionRange(expanded, tokenRange) }
                else if range.length == 0 && range.location > tokenRange.location && range.location < NSMaxRange(tokenRange) {
                    expanded = NSRange(location: NSMaxRange(tokenRange), length: 0)
                }
            }
            if expanded != range,
               let start = textView.position(from: textView.beginningOfDocument, offset: expanded.location),
               let end = textView.position(from: start, offset: expanded.length), let target = textView.textRange(from: start, to: end) {
                textView.replace(target, withText: text)
                textViewDidChange(textView)
                return false
            }
            (textView as? EditorView)?.resetTypingAttributes()
            return true
        }
        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            (textView as? EditorView)?.updatePlaceholder()
            parent.caret = textView.selectedRange.location
            parent.text = PromptEditor.attributed(textView.attributedText)
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating, textView.markedTextRange == nil else { return }
            (textView as? EditorView)?.resetTypingAttributes()
            parent.caret = textView.selectedRange.location
        }
    }
}

final class EditorView: UITextView {
    // UITextView(usingTextLayoutManager:) is a factory initializer, so subclass property
    // initializers never run. Keep new state in types whose zeroed memory is a valid value.
    private var placeholderStorage: NSString?
    var placeholder: String {
        get { placeholderStorage.map { $0 as String } ?? "" }
        set { guard newValue != placeholder else { return }; placeholderStorage = newValue as NSString; updatePlaceholder() }
    }
    private(set) lazy var placeholderView: UITextView = {
        let view = UITextView(usingTextLayoutManager: true)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false; view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.isScrollEnabled = false
        addSubview(view)
        return view
    }()
    var key: (ComposerKey) -> Bool = { _ in false }
    /// Optional: the factory initializer leaves it zeroed, which for an optional is nil.
    var composing: ((Bool) -> Void)?
    var suggestionsActive = false
    var focusRequest: UUID?
    private var consumedFocusRequest: UUID?
    private var pendingFocusRequest: UUID?
    private var focusTask: Task<Void, Never>?
    private var styledFont: UIFont?
    private var styledParagraph: NSParagraphStyle?
    private var shellTraitsState = 0 // 0 unknown, 1 prompt, 2 shell
    private(set) var styleApplications = 0
    func updateStyle(shell: Bool) {
        updateInputTraits(shell: shell)
        let font = OCType.editorFont(shell: shell, traits: traitCollection)
        let paragraph = OCType.editorParagraphStyle(traits: traitCollection)
        guard styledFont != font || styledParagraph != paragraph else { return }
        styledFont = font; styledParagraph = paragraph; styleApplications += 1
        textStorage.addAttributes([.font: font, .paragraphStyle: paragraph], range: NSRange(location: 0, length: textStorage.length))
        updatePlaceholder()
    }
    private func updateInputTraits(shell: Bool) {
        let compact = traitCollection.horizontalSizeClass == .compact
        let accessoryChanged = compact != (inputAccessoryView != nil)
        if accessoryChanged {
            if compact {
                let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: bounds.width, height: OCLayout.touchTarget))
                toolbar.autoresizingMask = .flexibleWidth
                toolbar.tintColor = UIColor(OCColor.text)
                let hide = UIBarButtonItem(title: "Hide keyboard", style: .plain, target: self, action: #selector(hideKeyboard))
                hide.setTitleTextAttributes([.font: OCType.editorFont(shell: false, traits: traitCollection)], for: .normal)
                toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), hide]
                inputAccessoryView = toolbar
            } else { inputAccessoryView = nil }
        }
        guard shellTraitsState != (shell ? 2 : 1) || accessoryChanged else { return }
        shellTraitsState = shell ? 2 : 1
        autocapitalizationType = shell ? .none : .sentences
        autocorrectionType = shell ? .no : .default
        spellCheckingType = shell ? .no : .default
        smartQuotesType = .no; smartDashesType = .no
        smartInsertDeleteType = shell ? .no : .default
        inlinePredictionType = shell ? .no : .default
        writingToolsBehavior = shell ? .none : .default
        if isFirstResponder { reloadInputViews() }
    }
    @objc private func hideKeyboard() { resignFirstResponder() }
    func updatePlaceholder() {
        placeholderView.isHidden = !text.isEmpty || placeholder.isEmpty
        placeholderView.textContainerInset = textContainerInset
        placeholderView.textContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        placeholderView.attributedText = NSAttributedString(string: placeholder, attributes: [
            .font: styledFont ?? OCType.editorFont(shell: false, traits: traitCollection),
            .paragraphStyle: styledParagraph ?? OCType.editorParagraphStyle(traits: traitCollection),
            .foregroundColor: UIColor(OCColor.textMuted)
        ])
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderView.frame = CGRect(origin: .zero, size: bounds.size)
    }
    func resetTypingAttributes() {
        guard markedTextRange == nil else { return }
        // UIKit inherits the preceding run at a token's trailing edge.
        var attributes = typingAttributes
        attributes.removeValue(forKey: PromptEditor.tokenKey)
        attributes[.foregroundColor] = UIColor(OCColor.text)
        if let styledFont { attributes[.font] = styledFont }
        if let styledParagraph { attributes[.paragraphStyle] = styledParagraph }
        typingAttributes = attributes
    }
    override func insertText(_ text: String) { resetTypingAttributes(); super.insertText(text) }
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        resetTypingAttributes(); super.setMarkedText(markedText, selectedRange: selectedRange)
        composing?(markedTextRange != nil)
    }
    override func unmarkText() { super.unmarkText(); composing?(false) }
    deinit { focusTask?.cancel() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { focusTask?.cancel(); focusTask = nil; pendingFocusRequest = nil }
        else { updateInputTraits(shell: shellTraitsState == 2); scheduleFocusRequest() }
    }
    func scheduleFocusRequest() {
        guard window != nil, let request = focusRequest, request != consumedFocusRequest, request != pendingFocusRequest else { return }
        focusTask?.cancel(); pendingFocusRequest = request
        // A responder change re-enters SwiftUI's focus graph. Perform it after updateUIView finishes.
        focusTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.focusRequest == request else { return }
            self.pendingFocusRequest = nil; self.fulfillFocusRequest(); self.focusTask = nil
        }
    }
    func fulfillFocusRequest() {
        guard window != nil, let focusRequest, focusRequest != consumedFocusRequest else { return }
        consumedFocusRequest = focusRequest
        selectedRange = NSRange(location: attributedText.length, length: 0)
        becomeFirstResponder()
    }
    func apply(_ value: NSAttributedString, selection: NSRange, resetUndo: Bool = false) {
        let previous = NSAttributedString(attributedString: attributedText), previousSelection = selectedRange
        if resetUndo { undoManager?.removeAllActions() }
        else {
            undoManager?.registerUndo(withTarget: self) { view in
                view.apply(previous, selection: previousSelection)
                view.delegate?.textViewDidChange?(view)
            }
        }
        textStorage.setAttributedString(value)
        selectedRange = selection
        updatePlaceholder()
    }
    override func deleteBackward() {
        if text.isEmpty && key(.emptyBackspace) { return }
        if markedTextRange == nil, selectedRange.location > 0 || selectedRange.length > 0 {
            var range = selectedRange.length == 0 ? NSRange(location: selectedRange.location - 1, length: 1) : selectedRange
            var hasMention = false
            attributedText.enumerateAttribute(PromptEditor.tokenKey, in: NSRange(location: 0, length: attributedText.length)) { value, token, _ in
                if value != nil && NSIntersectionRange(range, token).length > 0 {
                    range = NSUnionRange(range, token); hasMention = true
                }
            }
            if hasMention {
                let value = NSMutableAttributedString(attributedString: attributedText)
                value.deleteCharacters(in: range)
                apply(value, selection: NSRange(location: range.location, length: 0))
                delegate?.textViewDidChange?(self)
                return
            }
        }
        super.deleteBackward()
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(handleKey), markedTextRange != nil { return false }
        return super.canPerformAction(action, withSender: sender)
    }
    override var keyCommands: [UIKeyCommand]? {
        // Do not register priority commands while the IME owns the keyboard.
        // Returning early from handleKey would still consume Return.
        guard markedTextRange == nil else { return super.keyCommands }
        let chords = WorkspaceKeys.local(.promptEditor).filter { suggestionsActive || !WorkspaceKeys.PromptEditor.suggestions.contains($0) }
            + WorkspaceKeys.forwarded(.promptEditor).map(\.chord)
        return chords.map { $0.keyCommand(#selector(handleKey)) }
    }
    @objc private func handleKey(_ command: UIKeyCommand) {
        guard markedTextRange == nil else { return }
        let keys = WorkspaceKeys.PromptEditor.self
        let action: ComposerKey
        if let forwarded = WorkspaceKeys.forwarded(.promptEditor).first(where: { $0.chord.matches(command) }) { action = .menu(forwarded) }
        else if keys.send.matches(command) { action = .send }
        else if keys.escape.matches(command) { action = .escape }
        else if keys.up.matches(command) || keys.previous.matches(command) { action = .up }
        else if keys.down.matches(command) || keys.next.matches(command) { action = .down }
        else if keys.accept.matches(command) { action = .tab }
        else { return }
        if !key(action), action == .tab { insertText("\t") }
    }
}
#endif

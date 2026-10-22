#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import OCModels
import OCDesign
@testable import FeatureComposer

private struct MentionFormatting: AttributedTextFormattingDefinition {
    typealias Scope = DraftAttributes
    var body: some AttributedTextFormattingDefinition<Scope> { AttributedTextFormatting.EmptyDefinition<Scope>() }
}
@MainActor private final class EditorBinding {
    var text: AttributedString
    var caret: Int
    init(_ text: AttributedString) { self.text = text; caret = String(text.characters).utf16.count }
    var binding: Binding<AttributedString> { .init(get: { self.text }, set: { self.text = $0 }) }
    var selection: Binding<Int> { .init(get: { self.caret }, set: { self.caret = $0 }) }
}
@MainActor @Suite(.serialized) struct EditorBehaviorTests {
    private func token() -> AttributedString {
        var value = AttributedString("@file.swift")
        value[MentionAttribute.self] = .init(kind: "file", value: "file.swift")
        return value
    }
    private func findTextView(_ view: UIView) -> UITextView? {
        if let text = view as? UITextView { return text }
        return view.subviews.lazy.compactMap(findTextView).first
    }
    @Test func nativeFormattingDefinitionDoesNotMakeMentionsAtomic() async throws {
        let state = EditorBinding(token())
        let host = UIHostingController(rootView: TextEditor(text: state.binding).attributedTextFormattingDefinition(MentionFormatting()))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 400)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let view = try #require(findTextView(host.view))
        view.becomeFirstResponder(); view.selectedRange = NSRange(location: 11, length: 0)
        view.deleteBackward()
        try await Task.sleep(for: .milliseconds(50))
        // The native editor deletes one character, leaving a broken token.
        #expect(view.text == "@file.swif")
    }
    @Test func textKitMentionsDeleteAtomicallyAndUndoAndMarkedTextSurvive() async throws {
        let state = EditorBinding(token())
        let editor = PromptEditor(text: state.binding, caret: state.selection, shell: false, enabled: true, key: { _ in false })
        let coordinator = editor.makeCoordinator()
        let view = EditorView(usingTextLayoutManager: true)
        let host = UIViewController(); host.view.addSubview(view); view.frame = host.view.bounds
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 400)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.delegate = coordinator
        view.attributedText = PromptEditor.native(state.text, shell: false, traits: view.traitCollection)
        view.becomeFirstResponder(); view.selectedRange = NSRange(location: 11, length: 0)
        view.deleteBackward()
        #expect(view.text.isEmpty)
        try await Task.sleep(for: .milliseconds(20))
        view.undoManager?.undo()
        #expect(view.text == "@file.swift")
        #expect(PromptEditor.attributed(view.attributedText).runs.first?[MentionAttribute.self] != nil)
        view.selectedRange = NSRange(location: 11, length: 0)
        view.insertText(" ")
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0))
        #expect(view.markedTextRange != nil)
        view.unmarkText()
        #expect(view.text.hasSuffix(" にほん"))
    }
    @Test func typingAtMentionTrailingEdgeDoesNotExtendToken() throws {
        var text = token(); text.append(AttributedString(" "))
        let state = EditorBinding(text)
        let editor = PromptEditor(text: state.binding, caret: state.selection, shell: false, enabled: true, key: { _ in false })
        let coordinator = editor.makeCoordinator()
        let view = EditorView(usingTextLayoutManager: true)
        view.delegate = coordinator
        view.attributedText = PromptEditor.native(text, shell: false, traits: view.traitCollection)
        view.selectedRange = NSRange(location: 11, length: 0)
        // Reproduce UIKit's inherited attributes immediately before the trailing space.
        view.typingAttributes = view.attributedText.attributes(at: 10, effectiveRange: nil)
        view.insertText("typed")
        let restored = PromptEditor.attributed(view.attributedText)
        #expect(String(restored.characters) == "@file.swifttyped ")
        #expect(restored.runs.filter { $0[MentionAttribute.self] != nil }.map { String(restored[$0.range].characters) } == ["@file.swift"])
        #expect(view.attributedText.attribute(.foregroundColor, at: 11, effectiveRange: nil) as? UIColor == UIColor(OCColor.text))
    }
    @Test func markedCompositionOwnsHardwareReturnAndStyleChangesAreBounded() async throws {
        let view = EditorView(usingTextLayoutManager: true)
        let host = UIViewController(); host.view.addSubview(view); view.frame = host.view.bounds
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 400)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.becomeFirstResponder(); view.updateStyle(shell: false)
        let send = try #require(view.keyCommands?.first { $0.input == "\r" && $0.modifierFlags.isEmpty })
        let sendAction = try #require(send.action)
        var sent = false; view.key = { _ in sent = true; return true }
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0))
        #expect(view.markedTextRange != nil)
        #expect(view.keyCommands?.contains { $0.action == send.action && $0.input == "\r" } != true)
        #expect(!view.canPerformAction(sendAction, withSender: send))
        view.unmarkText()
        #expect(!sent && view.text == "にほん")
        #expect(view.keyCommands?.contains { $0.action == send.action && $0.input == "\r" } == true)
        for _ in 0..<50 { view.insertText("a"); view.updateStyle(shell: false) }
        #expect(view.styleApplications == 1)
        view.updateStyle(shell: true)
        #expect(view.styleApplications == 2)
    }

}
#endif

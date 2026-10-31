import Foundation
import SwiftUI
import OCRender
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct CodeBlockView: View {
    let code: String
    let language: String?
    let closed: Bool
    @State private var highlighted: AttributedString?
    @State private var selecting = false
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ code: String, language: String? = nil, closed: Bool = true) {
        self.code = code; self.language = language; self.closed = closed
    }
    private var folded: Bool { code.split(separator: "\n", omittingEmptySubsequences: false).count > 200 }
    private var preview: String { folded ? code.split(separator: "\n", omittingEmptySubsequences: false).prefix(200).joined(separator: "\n") : code }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, OCSpacing.md).background(OCColor.band)
            ScrollView(.horizontal) {
                Text(highlighted ?? AttributedString(preview)).font(OCType.code)
                    .fixedSize(horizontal: true, vertical: true).padding(OCSpacing.md)
                    .ocSelectableText(code)
            }.fixedSize(horizontal: false, vertical: true)
                // Code reads left to right in every language.
                .environment(\.layoutDirection, .leftToRight)
            if folded {
                Button(localized("Show full output (\(code.split(separator: "\n", omittingEmptySubsequences: false).count) lines)", comment: "%lld is the number of lines in a folded code block")) { selecting = true }
                    .buttonStyle(OCButtonStyle()).padding(OCSpacing.sm)
            }
        }.background(OCColor.backgroundDeep, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
            .sheet(isPresented: $selecting) { OCTextSelectionSheet(text: code).ocSheet() }
            .task(id: HighlightInput(code: preview, language: language, closed: closed)) {
                highlighted = nil
                guard closed else { return }
                let spans = await CodeHighlighter.shared.highlight(preview, language: language)
                guard !Task.isCancelled else { return }
                var value = AttributedString(preview)
                for span in spans {
                    guard let range = Range(span.range, in: preview), let lower = AttributedString.Index(range.lowerBound, within: value),
                          let upper = AttributedString.Index(range.upperBound, within: value) else { continue }
                    value[lower..<upper].foregroundColor = span.kind.color
                }
                highlighted = value
            }
    }
    @ViewBuilder private var header: some View {
        if !closed && typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                HStack(spacing: OCSpacing.sm) { languageLabel; Spacer(minLength: 0); copyButton }
                OCBadge(localized("Streaming", comment: "Badge on a code block that is still being written")).padding(.bottom, OCSpacing.sm)
            }
        } else {
            HStack(spacing: OCSpacing.sm) {
                languageLabel
                if !closed { OCBadge(localized("Streaming", comment: "Badge on a code block that is still being written")) }
                Spacer(minLength: 0)
                copyButton
            }
        }
    }
    private var languageLabel: some View { Text(language ?? localized("Text", comment: "Code block language label for plain text")).font(OCType.small).foregroundStyle(OCColor.textMuted) }
    private var copyButton: some View { OCIconButton(localized("Copy code"), icon: "copy") { OCCopy.text(code) } }
    private struct HighlightInput: Equatable { let code: String; let language: String?; let closed: Bool }
}
private extension HighlightSpan.Kind {
    var color: Color {
        switch self {
        case .comment: OCColor.syntaxComment
        case .keyword: OCColor.syntaxKeyword
        case .string: OCColor.syntaxString
        case .number: OCColor.syntaxConstant
        case .type: OCColor.syntaxType
        case .property: OCColor.syntaxProperty
        case .punctuation: OCColor.syntaxPunctuation
        }
    }
}
public enum OCCopy {
    /// Copies silently on screen, so VoiceOver hears the confirmation instead.
    public static func text(_ text: String) {
        OCAnnouncer.post(localized("Copied", comment: "VoiceOver announcement after copying to the clipboard"))
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

import Foundation
import SwiftUI
import Textual
import OCRender
import OCModels

public protocol MarkdownBlockRenderer {
    func render(_ block: MarkdownBlock) -> AnyView
}
public struct TextualBlockRenderer: MarkdownBlockRenderer {
    public init() {}
    public func render(_ block: MarkdownBlock) -> AnyView {
        AnyView(TextualBlockContent(block: block))
    }
}
struct TextualBlockContent: View {
    @Environment(\.ocFileLinks) private var fileLinks
    let block: MarkdownBlock
    var body: some View {
        StructuredText(block.source, parser: PreparedMarkup(value: block.attributed))
            .textual.paragraphStyle(OCMarkdownParagraph())
            .textual.headingStyle(OCMarkdownHeading())
            .textual.blockQuoteStyle(OCMarkdownQuote())
            .textual.tableStyle(OCMarkdownTable())
            .textual.thematicBreakStyle(OCMarkdownBreak())
            .textual.inlineStyle(InlineStyle().code(.font(OCType.code)).link(.foregroundColor(OCColor.accent)))
            .font(OCType.body).foregroundStyle(OCColor.text)
            .environment(\.openURL, OpenURLAction { url in
                if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { return .systemAction }
                if let fileLinks { fileLinks.open(url.absoluteString); return .handled }
                return .discarded
            })
    }
}

private struct PreparedMarkup: MarkupParser {
    let value: AttributedString
    func attributedString(for input: String) throws -> AttributedString { value }
}
public struct MarkdownBlockView: View, Equatable {
    public let block: MarkdownBlock
    private let renderer: any MarkdownBlockRenderer
    public init(_ block: MarkdownBlock, renderer: any MarkdownBlockRenderer = TextualBlockRenderer()) {
        self.block = block; self.renderer = renderer
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.block == rhs.block }
    public var body: some View {
        if let code = block.code {
            // A diagram is drawn once its fence closes; while it streams it stays a code block.
            if block.closed && block.language?.lowercased() == "mermaid" { MermaidView(code) }
            else if block.closed && block.language?.lowercased() == "math" { MathBlockView(code) }
            else { CodeBlockView(code, language: block.language, closed: block.closed) }
        }
        else if block.closed, let tex = MathMarkdown.display(block.source) { MathBlockView(tex) }
        // Textual starts with empty content until its initial change handler runs.
        // Keep the lazy row measurable during that first layout pass.
        else { renderer.render(block).frame(minHeight: OCSpacing.xs) }
    }
}

public struct StreamingMarkdownView: View {
    @Environment(\.ocFileLinks) private var fileLinks
    let text: String
    let complete: Bool
    @State private var pipeline = StreamingMarkdown()
    @State private var blocks: [MarkdownBlock] = []
    public init(_ text: String, complete: Bool = true) { self.text = text; self.complete = complete }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.md) {
            if blocks.isEmpty {
                // A zero-height asynchronous row destabilizes LazyVStack's estimates.
                // Reserve text geometry until the off-main parse is ready.
                Text(text.isEmpty ? " " : text).font(OCType.body).hidden().accessibilityHidden(true)
            }
            ForEach(blocks) { MarkdownBlockView($0).equatable() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: Input(text: text, complete: complete)) {
            do {
                // Text never waits for file lookups. Confirmed paths become links once the host answers;
                // a streaming block skips the check because its last code span may still be half written.
                let candidates = complete && fileLinks != nil ? InlineCodeLinks.candidates(in: text) : []
                if let known = candidates.isEmpty ? nil : fileLinks?.known(candidates) {
                    let next = try await pipeline.update(InlineCodeLinks.link(text, existing: known), complete: complete)
                    try Task.checkCancellation(); blocks = next; return
                }
                let next = try await pipeline.update(text, complete: complete)
                try Task.checkCancellation(); blocks = next
                guard let fileLinks, !candidates.isEmpty else { return }
                let existing = await fileLinks.existing(candidates)
                try Task.checkCancellation()
                guard !existing.isEmpty else { return }
                let linked = try await pipeline.update(InlineCodeLinks.link(text, existing: existing), complete: complete)
                try Task.checkCancellation(); blocks = linked
            } catch is CancellationError {} catch { blocks = [MarkdownBlock(source: text)] }
        }
    }
    private struct Input: Equatable { let text: String; let complete: Bool }
}

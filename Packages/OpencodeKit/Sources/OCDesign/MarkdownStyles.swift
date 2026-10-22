import SwiftUI
import Textual

struct OCMarkdownParagraph: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.lineSpacing(OCSpacing.xs)
    }
}

struct OCMarkdownHeading: StructuredText.HeadingStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(configuration.headingLevel == 1 ? OCType.title : OCType.heading)
            .foregroundStyle(OCColor.text).padding(.vertical, OCSpacing.sm)
    }
}
struct OCMarkdownQuote: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(OCType.body).foregroundStyle(OCColor.textMuted)
            .padding(OCSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(OCColor.layer1)
            .overlay(alignment: .leading) { Rectangle().fill(OCColor.border).frame(width: OCSpacing.xs) }
    }
}
struct OCMarkdownBreak: StructuredText.ThematicBreakStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rectangle().fill(OCColor.borderMuted).frame(height: OCBorder.hairline).padding(.vertical, OCSpacing.md)
    }
}
struct OCMarkdownTable: StructuredText.TableStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView(.horizontal) {
            configuration.label.font(OCType.small).fixedSize(horizontal: true, vertical: true)
                .textual.tableCellSpacing(horizontal: OCBorder.hairline, vertical: OCBorder.hairline)
                .textual.tableOverlay { layout in
                    Canvas { context, _ in
                        for divider in layout.dividers() { context.fill(Path(divider), with: .color(OCColor.border)) }
                    }
                }
                .padding(OCBorder.hairline)
        }
    }
}

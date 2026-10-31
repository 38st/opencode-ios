import Foundation
import SwiftUI
import OCRender
#if canImport(UIKit)
import UIKit
#endif

extension OCType {
    /// Mathematics in the transcript: the system serif, as TeX's roman.
    static func math(_ size: CGFloat) -> Font { .system(size: size, design: .serif) }
    static let mathSize: CGFloat = 17
    static let diagramSize: CGFloat = 13
}

/// Display math (`$$…$$`, `\[…\]` or a `math` fence). A formula that does not parse shows its source and the reason.
public struct MathBlockView: View {
    let source: String
    public init(_ source: String) { self.source = source }
    public var body: some View {
        switch Result(catching: { try MathParser.parse(source) }) {
        case .success(let node):
            ScrollView(.horizontal) {
                MathNodeView(node: node, size: OCType.mathSize, display: true).padding(.vertical, OCSpacing.sm).padding(.horizontal, OCSpacing.xs)
            }.scrollBounceBehavior(.basedOnSize).frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement().accessibilityLabel(node.unicode).accessibilityIdentifier("mathBlock")
        case .failure(let error):
            DiagramFallback(source: source, language: "latex", reason: (error as? MathError)?.message ?? localized("This formula could not be rendered"))
        }
    }
}

struct MathNodeView: View {
    let node: MathNode
    let size: CGFloat
    var display = false
    var bold = false
    var body: some View {
        switch node {
        case .symbol(let value):
            let italic = value.count == 1 && (value.first?.isLetter ?? false) && value.first?.isASCII == true
            text(value, italic: italic)
        case .text(let value): text(value, italic: false)
        case .row(let items):
            HStack(alignment: .center, spacing: 0) { ForEach(Array(items.enumerated()), id: \.offset) { MathNodeView(node: $1, size: size, display: display, bold: bold) } }
        case .fraction(let top, let bottom):
            VStack(spacing: size * 0.12) {
                MathNodeView(node: top, size: size * (display ? 1 : 0.8), display: false, bold: bold)
                Rectangle().fill(OCColor.text).frame(height: max(1, size / 18))
                MathNodeView(node: bottom, size: size * (display ? 1 : 0.8), display: false, bold: bold)
            }.fixedSize().padding(.horizontal, size * 0.15)
        case .root(let body, let index):
            HStack(alignment: .bottom, spacing: 0) {
                if let index { MathNodeView(node: index, size: size * 0.55, bold: bold).offset(y: -size * 0.45) }
                text("√", italic: false).scaleEffect(y: 1.15, anchor: .bottom)
                MathNodeView(node: body, size: size, display: display, bold: bold).padding(.top, size * 0.12)
                    .overlay(alignment: .top) { Rectangle().fill(OCColor.text).frame(height: max(1, size / 18)) }
            }.fixedSize()
        case .scripts(let base, let sup, let sub):
            if case .largeOperator(let symbol, let limits) = base, limits && display {
                VStack(spacing: 0) {
                    if let sup { MathNodeView(node: sup, size: size * 0.7, bold: bold) }
                    MathNodeView(node: .largeOperator(symbol, limits: limits), size: size, display: display, bold: bold)
                    if let sub { MathNodeView(node: sub, size: size * 0.7, bold: bold) }
                }.fixedSize()
            } else {
                HStack(alignment: .center, spacing: size * 0.04) {
                    MathNodeView(node: base, size: size, display: display, bold: bold)
                    VStack(alignment: .leading, spacing: size * 0.1) {
                        if let sup { MathNodeView(node: sup, size: size * 0.7, bold: bold) } else if sub != nil { Color.clear.frame(width: 1, height: size * 0.4) }
                        if let sub { MathNodeView(node: sub, size: size * 0.7, bold: bold) } else { Color.clear.frame(width: 1, height: size * 0.35) }
                    }.fixedSize()
                }.fixedSize()
            }
        case .largeOperator(let symbol, _):
            let named = symbol.first?.isLetter == true
            Text(symbol).font(OCType.math(named ? size : size * (display ? 1.6 : 1.2))).foregroundStyle(OCColor.text).padding(.horizontal, size * 0.1)
        case .delimited(let left, let body, let right):
            let scale = max(1, CGFloat(Self.height(body)))
            HStack(alignment: .center, spacing: size * 0.05) {
                if !left.isEmpty { text(left, italic: false).scaleEffect(x: 1, y: scale) }
                MathNodeView(node: body, size: size, display: display, bold: bold)
                if !right.isEmpty { text(right, italic: false).scaleEffect(x: 1, y: scale) }
            }.padding(.vertical, (scale - 1) * size * 0.4).fixedSize()
        case .accent(let mark, let body):
            if case .symbol(let value) = body, value.count == 1 { text(value + mark, italic: value.first?.isLetter == true) }
            else {
                MathNodeView(node: body, size: size, display: display, bold: bold).padding(.top, size * 0.15)
                    .overlay(alignment: .top) { Rectangle().fill(OCColor.text).frame(height: max(1, size / 18)) }
            }
        case .bold(let body): MathNodeView(node: body, size: size, display: display, bold: true)
        case .matrix(let rows, let left, let right):
            let scale = CGFloat(max(1, rows.count))
            HStack(spacing: size * 0.2) {
                if !left.isEmpty { text(left, italic: false).scaleEffect(x: 1, y: scale) }
                Grid(alignment: left == "{" ? .leading : .center, horizontalSpacing: size * 0.8, verticalSpacing: size * 0.3) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { MathNodeView(node: $1, size: size, display: false, bold: bold) } }
                    }
                }
                if !right.isEmpty { text(right, italic: false).scaleEffect(x: 1, y: scale) }
            }.padding(.vertical, (scale - 1) * size * 0.4).fixedSize()
        case .space(let em): Color.clear.frame(width: max(0, CGFloat(em) * size), height: 1)
        }
    }
    private func text(_ value: String, italic: Bool) -> some View {
        Text(value).font(OCType.math(size)).italic(italic).bold(bold).foregroundStyle(OCColor.text).fixedSize()
    }
    /// The body's height in lines, for stretching delimiters.
    static func height(_ node: MathNode) -> Double {
        switch node {
        case .fraction(let a, let b): height(a) + height(b)
        case .row(let items): items.map(height).max() ?? 1
        case .matrix(let rows, _, _): Double(rows.count)
        case .scripts(let base, let sup, let sub): height(base) + (sup == nil ? 0 : 0.3) + (sub == nil ? 0 : 0.3)
        case .delimited(_, let body, _), .accent(_, let body), .bold(let body): height(body)
        case .root(let body, _): height(body) + 0.1
        case .largeOperator: 1.4
        default: 1
        }
    }
}

/// A `mermaid` fence drawn natively. Diagram types this renderer does not support show their source.
public struct MermaidView: View {
    let source: String
    public init(_ source: String) { self.source = source }
    public var body: some View {
        switch Result(catching: { try MermaidParser.parse(source) }) {
        case .success(let diagram):
            let layout = MermaidLayout.layout(diagram, measure: Self.measure)
            ScrollView(.horizontal) {
                MermaidCanvas(layout: layout).frame(width: layout.size.width, height: layout.size.height)
            }.scrollBounceBehavior(.basedOnSize)
                .padding(OCSpacing.sm).frame(maxWidth: .infinity, alignment: .leading)
                .background(OCColor.backgroundDeep, in: RoundedRectangle(cornerRadius: OCRadius.md))
                .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
                .accessibilityElement().accessibilityLabel(Self.summary(diagram)).accessibilityIdentifier("mermaidDiagram")
        case .failure(let error):
            DiagramFallback(source: source, language: "mermaid", reason: (error as? MermaidError)?.message ?? localized("This diagram could not be rendered"))
        }
    }
    static func measure(_ text: String) -> CGSize {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: OCType.diagramSize)
        let size = (text as NSString).boundingRect(with: CGSize(width: 220, height: 1_000), options: [.usesLineFragmentOrigin],
                                                   attributes: [.font: font], context: nil).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
        #else
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return CGSize(width: CGFloat(lines.map(\.count).max() ?? 0) * 7, height: CGFloat(lines.count) * 16)
        #endif
    }
    static func summary(_ diagram: MermaidDiagram) -> String {
        switch diagram {
        case .flowchart(let chart):
            let edges = chart.edges.map { edge in
                let name = { (id: String) in chart.nodes.first { $0.id == id }?.label ?? id }
                let from = name(edge.from), to = name(edge.to)
                return edge.label.map { localized("\(from) to \(to) (\($0))", comment: "Flowchart edge; %1$@ and %2$@ are node names, %3$@ the edge label") } ?? localized("\(from) to \(to)", comment: "Flowchart edge; %1$@ and %2$@ are node names")
            }.joined(separator: ", ")
            return localized("Flowchart: \(edges)", comment: "%@ is a list of flowchart edges")
        case .sequence(let sequence):
            let names = sequence.participants.map(\.label).joined(separator: ", ")
            return localized("Sequence diagram: \(names)", comment: "%@ is a list of participant names")
        }
    }
}

private struct MermaidCanvas: View {
    let layout: MermaidLayout
    var body: some View {
        Canvas { context, _ in
            for line in layout.lifelines { stroke(line, in: &context, color: OCColor.borderStrong) }
            for line in layout.lines {
                stroke(line, in: &context, color: OCColor.textMuted)
                if let frame = line.labelFrame, let label = line.label {
                    context.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(OCColor.backgroundDeep))
                    context.draw(Text(label).font(.system(size: OCType.diagramSize)).foregroundStyle(OCColor.textMuted), at: CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            for caption in layout.captions {
                context.fill(Path(roundedRect: caption.frame, cornerRadius: 4), with: .color(caption.note ? OCColor.warningBackground : OCColor.layer2))
                context.draw(Text(caption.text).font(.system(size: OCType.diagramSize)).foregroundStyle(OCColor.text),
                             at: CGPoint(x: caption.frame.midX, y: caption.frame.midY))
            }
            for box in layout.boxes {
                let path = shape(box)
                context.fill(path, with: .color(OCColor.layer2))
                context.stroke(path, with: .color(OCColor.borderStrong), lineWidth: 1)
                context.draw(Text(box.label).font(.system(size: OCType.diagramSize)).foregroundStyle(OCColor.text),
                             at: CGPoint(x: box.frame.midX, y: box.frame.midY))
            }
        }
    }
    private func stroke(_ line: MermaidLayout.Line, in context: inout GraphicsContext, color: Color) {
        guard let first = line.points.first, let last = line.points.last, line.points.count > 1 else { return }
        var path = Path(); path.move(to: first)
        for point in line.points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line.thick ? 2.5 : 1.2, dash: line.dashed ? [4, 3] : []))
        guard line.arrow else { return }
        let previous = line.points[line.points.count - 2]
        let angle = atan2(last.y - previous.y, last.x - previous.x)
        var head = Path(); head.move(to: last)
        head.addLine(to: CGPoint(x: last.x - 8 * cos(angle - .pi / 7), y: last.y - 8 * sin(angle - .pi / 7)))
        head.addLine(to: CGPoint(x: last.x - 8 * cos(angle + .pi / 7), y: last.y - 8 * sin(angle + .pi / 7)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
    private func shape(_ box: MermaidLayout.Box) -> Path {
        let r = box.frame
        switch box.shape {
        case .rounded, .subroutine: return Path(roundedRect: r, cornerRadius: 6)
        case .stadium: return Path(roundedRect: r, cornerRadius: r.height / 2)
        case .circle: return Path(ellipseIn: r)
        case .rhombus:
            var path = Path()
            path.move(to: CGPoint(x: r.midX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            path.addLine(to: CGPoint(x: r.midX, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX, y: r.midY)); path.closeSubpath()
            return path
        case .hexagon:
            let inset = r.height / 3
            var path = Path()
            path.move(to: CGPoint(x: r.minX + inset, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.midY)); path.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX, y: r.midY)); path.closeSubpath()
            return path
        case .flag:
            var path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX + r.height / 3, y: r.midY)); path.closeSubpath()
            return path
        case .cylinder, .rectangle: return Path(r)
        }
    }
}

/// The source of a diagram or formula that could not be drawn, with the reason.
struct DiagramFallback: View {
    let source: String
    let language: String
    let reason: String
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            CodeBlockView(source, language: language)
            Text(reason).font(OCType.micro).foregroundStyle(OCColor.textMuted)
        }.accessibilityIdentifier("diagramSource")
    }
}

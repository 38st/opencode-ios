import CoreGraphics
import Foundation
import Testing
@testable import OCRender

@Test func mathParsesTheCommonSubset() throws {
    #expect(try MathParser.parse("x^2") == .scripts(base: .symbol("x"), sup: .symbol("2"), sub: nil))
    #expect(try MathParser.parse("a_i^{n+1}") == .scripts(base: .symbol("a"), sup: .row([.symbol("n"), .symbol("+"), .symbol("1")]), sub: .symbol("i")))
    #expect(try MathParser.parse("\\frac{1}{2}") == .fraction(.symbol("1"), .symbol("2")))
    #expect(try MathParser.parse("\\sqrt[3]{x}") == .root(.symbol("x"), index: .symbol("3")))
    #expect(try MathParser.parse("\\sum_{i=1}^n i") == .row([.scripts(base: .largeOperator("∑", limits: true), sup: .symbol("n"),
        sub: .row([.symbol("i"), .symbol("="), .symbol("1")])), .symbol("i")]))
    #expect(try MathParser.parse("\\left( \\alpha \\right]") == .delimited(left: "(", .symbol("α"), right: "]"))
    #expect(try MathParser.parse("\\sin x") == .row([.text("sin"), .symbol("x")]))
    #expect(try MathParser.parse("\\mathbb{R}^n") == .scripts(base: .symbol("ℝ"), sup: .symbol("n"), sub: nil))
    #expect(try MathParser.parse("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}") ==
        .matrix([[.symbol("a"), .symbol("b")], [.symbol("c"), .symbol("d")]], left: "(", right: ")"))
    #expect(try MathParser.parse("f'(x) = 3.14") == .row([.scripts(base: .symbol("f"), sup: .symbol("′"), sub: nil), .symbol("("), .symbol("x"),
        .symbol(")"), .symbol("="), .symbol("3.14")]))
}

@Test func mathRejectsWhatItCannotDraw() {
    for source in ["\\unknowncommand{x}", "\\frac{1}", "{a", "a}", "\\left( x", "\\begin{tikzpicture}\\end{tikzpicture}", "\\begin{matrix} a \\end{pmatrix}", "a & b"] {
        #expect(throws: MathError.self, "\(source)") { try MathParser.parse(source) }
    }
}

@Test func mathUnicodeReadsInline() throws {
    #expect(try MathParser.parse("x^2 + y_1").unicode == "x² + y₁")
    #expect(try MathParser.parse("e^{i\\pi}").unicode == "e^(iπ)")
    #expect(try MathParser.parse("\\frac{a+b}{2}").unicode == "(a + b)/2")
    #expect(try MathParser.parse("\\sqrt{x}").unicode == "√x")
    #expect(try MathParser.parse("a \\leq b \\times c").unicode == "a ≤ b × c")
    #expect(try MathParser.parse("-x").unicode == "−x", "A leading sign stays tight")
}

@Test func inlineMathFollowsTheDesktopBoundaries() {
    #expect(MathMarkdown.inline("Area is $\\pi r^2$.") == "Area is πr².")
    #expect(MathMarkdown.inline("It costs $5 and $10 today") == "It costs $5 and $10 today", "Prices stay text")
    #expect(MathMarkdown.inline("Use `$x^2$` literally and $y_1$") == "Use `$x^2$` literally and y₁", "Code spans are untouched")
    #expect(MathMarkdown.inline("Inline \\(a_b\\) form") == "Inline a\\_(b) form", "Unmapped subscripts are escaped for Markdown")
    #expect(MathMarkdown.inline("$ x $ is not math") == "$ x $ is not math")
    #expect(MathMarkdown.inline("Bad $\\nope{x}$ stays") == "Bad $\\nope{x}$ stays", "A formula that does not parse shows its source")
    #expect(MathMarkdown.inline("$$E = mc^2$$ inline") == "E = mc² inline")
    #expect(MathMarkdown.inline("No math at all") == "No math at all")
}

@Test func displayMathIsAWholeBlock() {
    #expect(MathMarkdown.display("$$\n\\int_0^1 x\\,dx\n$$\n") == "\\int_0^1 x\\,dx")
    #expect(MathMarkdown.display("\\[ a^2 \\]") == "a^2")
    #expect(MathMarkdown.display("$$a$$ and $$b$$") == nil)
    #expect(MathMarkdown.display("Text $$a$$") == nil)
    #expect(MathMarkdown.display("$$$$") == nil)
}

@Test func mermaidFlowchartsParse() throws {
    let diagram = try MermaidParser.parse("""
    flowchart LR
      %% a comment
      A[Start] --> B{Ready?}
      B -->|yes| C(Run)
      B -- no --> D((Wait)) -.-> A
      C & D --> E
      classDef hot fill:#f00
      style A fill:#fff
    """)
    guard case .flowchart(let chart) = diagram else { Issue.record("Expected a flowchart"); return }
    #expect(chart.direction == .right)
    #expect(chart.nodes.map(\.id) == ["A", "B", "C", "D", "E"])
    #expect(chart.nodes.map(\.label) == ["Start", "Ready?", "Run", "Wait", "E"])
    #expect(chart.nodes.map(\.shape) == [.rectangle, .rhombus, .rounded, .circle, .rectangle])
    #expect(chart.edges.map { "\($0.from)>\($0.to)" } == ["A>B", "B>C", "B>D", "D>A", "C>E", "D>E"])
    #expect(chart.edges[1].label == "yes" && chart.edges[2].label == "no" && chart.edges[3].dotted && chart.edges[0].arrow)
}

@Test func mermaidSequenceDiagramsParse() throws {
    let diagram = try MermaidParser.parse("""
    sequenceDiagram
      participant A as App
      actor U
      U->>A: Tap send
      A-->>U: Done
      Note over A,U: Both agree
      loop Every minute
        A->>A: Poll
      end
    """)
    guard case .sequence(let sequence) = diagram else { Issue.record("Expected a sequence diagram"); return }
    #expect(sequence.participants.map(\.label) == ["App", "U"])
    #expect(sequence.events == [
        .message(from: "U", to: "A", text: "Tap send", dashed: false, arrow: true),
        .message(from: "A", to: "U", text: "Done", dashed: true, arrow: true),
        .note(over: ["A", "U"], text: "Both agree"), .block("loop Every minute"),
        .message(from: "A", to: "A", text: "Poll", dashed: false, arrow: true), .end,
    ])
}

@Test func mermaidOtherDiagramsAndBadTextShowSource() {
    for source in ["gantt\n  title Plan", "classDiagram\n  A <|-- B", "", "flowchart TD\n  A -->", "sequenceDiagram\n  this is not valid"] {
        #expect(throws: MermaidError.self, "\(source)") { try MermaidParser.parse(source) }
    }
}

private func measure(_ text: String) -> CGSize { CGSize(width: CGFloat(text.count) * 7, height: 16) }

@Test func flowchartLayoutRanksNodesAndClipsEdges() throws {
    let diagram = try MermaidParser.parse("graph TD\n A --> B\n A --> C\n B --> D\n C --> D\n D --> A")
    let layout = MermaidLayout.layout(diagram, measure: measure)
    let frame = Dictionary(uniqueKeysWithValues: layout.boxes.map { ($0.id, $0.frame) })
    let a = try #require(frame["A"]), b = try #require(frame["B"]), c = try #require(frame["C"]), d = try #require(frame["D"])
    #expect(a.maxY < b.minY && abs(b.minY - c.minY) < 0.5 && max(b.maxY, c.maxY) < d.minY, "Ranks run down; the cycle's back edge is ignored")
    #expect(b.maxX <= c.minX || c.maxX <= b.minX, "Nodes of one rank do not overlap")
    for box in layout.boxes { #expect(CGRect(origin: .zero, size: layout.size).contains(box.frame)) }
    let first = try #require(layout.lines.first)
    #expect(abs(first.points[0].y - a.maxY) < 0.5 && abs(first.points[1].y - b.minY) < 0.5, "Edges start and end on the boxes' borders")
    let horizontal = MermaidLayout.layout(try MermaidParser.parse("graph LR\n A --> B"), measure: measure)
    #expect(horizontal.boxes[0].frame.maxX < horizontal.boxes[1].frame.minX)
    let up = MermaidLayout.layout(try MermaidParser.parse("graph BT\n A --> B"), measure: measure)
    #expect(up.boxes[0].frame.minY > up.boxes[1].frame.maxY)
}

@Test func sequenceLayoutKeepsMessageTextBetweenParticipants() throws {
    let diagram = try MermaidParser.parse("sequenceDiagram\n A->>B: a very long message that needs room\n B-->>A: ok")
    let layout = MermaidLayout.layout(diagram, measure: measure)
    #expect(layout.lifelines.count == 2 && layout.lines.count == 2)
    let label = try #require(layout.lines[0].labelFrame)
    #expect(label.minX >= layout.lifelines[0].points[0].x - 1 && label.maxX <= layout.lifelines[1].points[0].x + 1)
    #expect(layout.lines[1].dashed && layout.lines[0].points[0].y < layout.lines[1].points[0].y)
}

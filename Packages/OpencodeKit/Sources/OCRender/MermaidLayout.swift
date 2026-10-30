import CoreGraphics
import Foundation

/// Positions for a parsed diagram. Flowcharts use layers: each node's rank is its longest path from a source
/// (back edges of cycles are ignored), and two barycentre sweeps order each rank.
public struct MermaidLayout: Equatable, Sendable {
    public struct Box: Equatable, Sendable {
        public let id: String
        public let label: String
        public let frame: CGRect
        public let shape: MermaidDiagram.Flowchart.Shape
    }
    public struct Line: Equatable, Sendable {
        public let points: [CGPoint]
        public let label: String?
        public let labelFrame: CGRect?
        public let arrow: Bool
        public let dashed: Bool
        public let thick: Bool
    }
    /// Sequence-diagram block labels and notes.
    public struct Caption: Equatable, Sendable { public let text: String; public let frame: CGRect; public let note: Bool }
    public var size: CGSize
    public var boxes: [Box]
    public var lines: [Line]
    public var captions: [Caption] = []
    /// Sequence diagrams: participant lifelines, top to bottom.
    public var lifelines: [Line] = []

    public static let padding: CGFloat = 8
    static let nodePadding = CGSize(width: 12, height: 8)
    static let gap: CGFloat = 28
    static let rankGap: CGFloat = 44

    public static func layout(_ diagram: MermaidDiagram, measure: (String) -> CGSize) -> MermaidLayout {
        switch diagram {
        case .flowchart(let chart): flowchart(chart, measure: measure)
        case .sequence(let sequence): self.sequence(sequence, measure: measure)
        }
    }

    // MARK: Flowcharts

    static func ranks(_ chart: MermaidDiagram.Flowchart) -> [String: Int] {
        let ids = chart.nodes.map(\.id)
        var outgoing: [String: [String]] = [:]
        for edge in chart.edges where edge.from != edge.to { outgoing[edge.from, default: []].append(edge.to) }
        // Depth-first order drops the edges that close a cycle.
        var state: [String: Int] = [:], forward: [String: [String]] = [:], order: [String] = []
        func visit(_ id: String) {
            state[id] = 1
            for next in outgoing[id] ?? [] {
                if state[next] == 1 { continue }
                forward[id, default: []].append(next)
                if state[next] == nil { visit(next) }
            }
            state[id] = 2; order.append(id)
        }
        for id in ids where state[id] == nil { visit(id) }
        var rank: [String: Int] = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for id in order.reversed() {
            for next in forward[id] ?? [] { rank[next] = max(rank[next] ?? 0, (rank[id] ?? 0) + 1) }
        }
        return rank
    }

    static func flowchart(_ chart: MermaidDiagram.Flowchart, measure: (String) -> CGSize) -> MermaidLayout {
        let rank = ranks(chart)
        let vertical = chart.direction == .down || chart.direction == .up
        var layers: [[String]] = Array(repeating: [], count: (rank.values.max() ?? 0) + 1)
        for node in chart.nodes { layers[rank[node.id] ?? 0].append(node.id) }
        let neighbours = Dictionary(grouping: chart.edges.flatMap { [($0.to, $0.from), ($0.from, $0.to)] }, by: \.0).mapValues { $0.map(\.1) }
        for sweep in 0..<2 {
            let range = sweep == 0 ? Array(layers.indices.dropFirst()) : Array(layers.indices.reversed().dropFirst())
            for layer in range {
                let reference = layers[sweep == 0 ? layer - 1 : layer + 1]
                let position = Dictionary(uniqueKeysWithValues: reference.enumerated().map { ($1, Double($0)) })
                let current = Dictionary(uniqueKeysWithValues: layers[layer].enumerated().map { ($1, Double($0)) })
                layers[layer].sort { a, b in
                    func centre(_ id: String) -> Double {
                        let values = (neighbours[id] ?? []).compactMap { position[$0] }
                        return values.isEmpty ? current[id] ?? 0 : values.reduce(0, +) / Double(values.count)
                    }
                    return (centre(a), current[a] ?? 0) < (centre(b), current[b] ?? 0)
                }
            }
        }
        var sizes: [String: CGSize] = [:]
        for node in chart.nodes {
            let text = measure(node.label)
            var size = CGSize(width: ceil(text.width) + nodePadding.width * 2, height: ceil(text.height) + nodePadding.height * 2)
            switch node.shape {
            case .rhombus, .hexagon: size = CGSize(width: size.width * 1.4, height: size.height * 1.4)
            case .circle: let side = max(size.width, size.height); size = CGSize(width: side, height: side)
            default: break
            }
            sizes[node.id] = size
        }
        // Along the rank axis every layer is as deep as its deepest node; across it, layers are centred.
        let depth = layers.map { layer in layer.map { vertical ? sizes[$0]?.height ?? 0 : sizes[$0]?.width ?? 0 }.max() ?? 0 }
        let breadth = layers.map { layer in layer.map { vertical ? sizes[$0]?.width ?? 0 : sizes[$0]?.height ?? 0 }.reduce(0, +) + gap * CGFloat(max(0, layer.count - 1)) }
        let widest = breadth.max() ?? 0
        var frames: [String: CGRect] = [:]
        var along: CGFloat = padding
        for (index, layer) in layers.enumerated() {
            var across = padding + (widest - breadth[index]) / 2
            for id in layer {
                let size = sizes[id] ?? .zero
                let offset = (depth[index] - (vertical ? size.height : size.width)) / 2
                frames[id] = vertical ? CGRect(x: across, y: along + offset, width: size.width, height: size.height)
                    : CGRect(x: along + offset, y: across, width: size.width, height: size.height)
                across += (vertical ? size.width : size.height) + gap
            }
            along += depth[index] + rankGap
        }
        let total = along - rankGap + padding
        var size = vertical ? CGSize(width: widest + padding * 2, height: total) : CGSize(width: total, height: widest + padding * 2)
        if chart.direction == .up || chart.direction == .left {
            for (id, frame) in frames {
                frames[id] = vertical ? CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
                    : CGRect(x: size.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
            }
        }
        var lines: [Line] = []
        for edge in chart.edges {
            guard let a = frames[edge.from], let b = frames[edge.to] else { continue }
            let points: [CGPoint]
            if edge.from == edge.to {
                let top = CGPoint(x: a.maxX, y: a.midY - 6)
                points = [top, CGPoint(x: a.maxX + 18, y: top.y), CGPoint(x: a.maxX + 18, y: a.midY + 6), CGPoint(x: a.maxX, y: a.midY + 6)]
            } else {
                points = [clip(a, toward: CGPoint(x: b.midX, y: b.midY)), clip(b, toward: CGPoint(x: a.midX, y: a.midY))]
            }
            var labelFrame: CGRect?
            if let label = edge.label, !label.isEmpty {
                let text = measure(label)
                let middle = CGPoint(x: (points[0].x + points[points.count - 1].x) / 2, y: (points[0].y + points[points.count - 1].y) / 2)
                labelFrame = CGRect(x: middle.x - text.width / 2 - 3, y: middle.y - text.height / 2 - 1, width: text.width + 6, height: text.height + 2)
            }
            lines.append(Line(points: points, label: edge.label, labelFrame: labelFrame, arrow: edge.arrow, dashed: edge.dotted, thick: edge.thick))
        }
        let boxes = chart.nodes.compactMap { node in frames[node.id].map { Box(id: node.id, label: node.label, frame: $0, shape: node.shape) } }
        let bounds = (boxes.map(\.frame) + lines.compactMap(\.labelFrame)).reduce(CGRect(origin: .zero, size: size)) { $0.union($1) }
        size = CGSize(width: ceil(bounds.maxX + (bounds.maxX > size.width ? padding : 0)), height: ceil(bounds.maxY))
        return MermaidLayout(size: size, boxes: boxes, lines: lines)
    }

    /// Where the segment from the box's centre to `point` leaves the box.
    static func clip(_ box: CGRect, toward point: CGPoint) -> CGPoint {
        let centre = CGPoint(x: box.midX, y: box.midY)
        let dx = point.x - centre.x, dy = point.y - centre.y
        guard dx != 0 || dy != 0 else { return centre }
        let scale = min(dx == 0 ? .infinity : (box.width / 2) / abs(dx), dy == 0 ? .infinity : (box.height / 2) / abs(dy))
        return CGPoint(x: centre.x + dx * scale, y: centre.y + dy * scale)
    }

    // MARK: Sequence diagrams

    static func sequence(_ diagram: MermaidDiagram.Sequence, measure: (String) -> CGSize) -> MermaidLayout {
        let heads = diagram.participants.map { measure($0.label) }
        let widths = heads.map { $0.width + nodePadding.width * 2 }
        let column = Dictionary(uniqueKeysWithValues: diagram.participants.enumerated().map { ($1.id, $0) })
        // Columns widen so each message's text fits between its participants.
        var spans = Array(repeating: CGFloat(80), count: max(0, diagram.participants.count - 1))
        for event in diagram.events {
            guard case .message(let from, let to, let text, _, _) = event, let a = column[from], let b = column[to], a != b else { continue }
            let low = min(a, b), high = max(a, b)
            let need = measure(text).width + 24
            let share = need / CGFloat(high - low)
            for index in low..<high { spans[index] = max(spans[index], share) }
        }
        let headHeight = (heads.map(\.height).max() ?? 16) + nodePadding.height * 2
        var x = padding, centres: [CGFloat] = []
        for index in widths.indices {
            let half = widths[index] / 2
            if index > 0 { x = max(x, centres[index - 1] + max(spans[index - 1], (widths[index - 1] / 2) + half + gap)) - half }
            centres.append(x + half)
            x += widths[index]
        }
        let boxes = diagram.participants.enumerated().map { index, participant in
            Box(id: participant.id, label: participant.label, frame: CGRect(x: centres[index] - widths[index] / 2, y: padding, width: widths[index], height: headHeight), shape: .rectangle)
        }
        var y = padding + headHeight + 16
        var lines: [Line] = [], captions: [Caption] = []
        let right = (boxes.map(\.frame.maxX).max() ?? 0) + padding
        for event in diagram.events {
            switch event {
            case .message(let from, let to, let text, let dashed, let arrow):
                guard let a = column[from], let b = column[to] else { continue }
                let label = measure(text)
                if a == b {
                    let start = CGPoint(x: centres[a], y: y + label.height + 4)
                    let points = [start, CGPoint(x: start.x + 30, y: start.y), CGPoint(x: start.x + 30, y: start.y + 16), CGPoint(x: start.x, y: start.y + 16)]
                    lines.append(Line(points: points, label: text, labelFrame: CGRect(x: start.x + 34, y: start.y, width: label.width, height: label.height), arrow: arrow, dashed: dashed, thick: false))
                    y += label.height + 32
                } else {
                    let lineY = y + label.height + 4
                    let points = [CGPoint(x: centres[a], y: lineY), CGPoint(x: centres[b], y: lineY)]
                    let middle = (centres[a] + centres[b]) / 2
                    lines.append(Line(points: points, label: text, labelFrame: CGRect(x: middle - label.width / 2, y: y, width: label.width, height: label.height), arrow: arrow, dashed: dashed, thick: false))
                    y = lineY + 16
                }
            case .note(let over, let text):
                let label = measure(text)
                let indexes = over.compactMap { column[$0] }
                let low = indexes.min().map { centres[$0] } ?? padding, high = indexes.max().map { centres[$0] } ?? padding
                let width = max(label.width + 16, high - low + 40)
                captions.append(Caption(text: text, frame: CGRect(x: (low + high) / 2 - width / 2, y: y, width: width, height: label.height + 10), note: true))
                y += label.height + 22
            case .block(let text):
                let label = measure(text)
                captions.append(Caption(text: text, frame: CGRect(x: padding, y: y, width: label.width + 12, height: label.height + 6), note: false))
                y += label.height + 12
            case .end:
                y += 6
            }
        }
        let bottom = y + 4
        let lifelines = centres.map { Line(points: [CGPoint(x: $0, y: padding + headHeight), CGPoint(x: $0, y: bottom)], label: nil, labelFrame: nil, arrow: false, dashed: true, thick: false) }
        let width = max(right, (lines.compactMap(\.labelFrame?.maxX) + captions.map(\.frame.maxX)).max() ?? 0) + padding
        return MermaidLayout(size: CGSize(width: ceil(width), height: ceil(bottom + padding)), boxes: boxes, lines: lines, captions: captions, lifelines: lifelines)
    }
}

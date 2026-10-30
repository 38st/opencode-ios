import Foundation

/// Mermaid diagrams drawn natively. Flowcharts (`graph`, `flowchart`) and sequence diagrams are parsed; other diagram
/// types, and text this parser does not understand, show their source (as the desktop app does when Mermaid fails).
public enum MermaidDiagram: Equatable, Sendable {
    case flowchart(Flowchart)
    case sequence(Sequence)

    public struct Flowchart: Equatable, Sendable {
        public enum Direction: String, Sendable { case down = "TD", up = "BT", right = "LR", left = "RL" }
        public enum Shape: Sendable, Equatable { case rectangle, rounded, stadium, circle, rhombus, hexagon, cylinder, subroutine, flag }
        public struct Node: Equatable, Sendable { public let id: String; public var label: String; public var shape: Shape }
        public struct Edge: Equatable, Sendable {
            public let from: String, to: String
            public let label: String?
            public let arrow: Bool
            public let dotted: Bool
            public let thick: Bool
        }
        public var direction: Direction
        public var nodes: [Node]
        public var edges: [Edge]
    }
    public struct Sequence: Equatable, Sendable {
        public struct Participant: Equatable, Sendable { public let id: String; public var label: String }
        public enum Event: Equatable, Sendable {
            case message(from: String, to: String, text: String, dashed: Bool, arrow: Bool)
            case note(over: [String], text: String)
            case block(String)
            case end
        }
        public var participants: [Participant]
        public var events: [Event]
    }
}

public struct MermaidError: Error, Equatable, Sendable { public let message: String }

public enum MermaidParser {
    public static func parse(_ source: String) throws -> MermaidDiagram {
        let lines = source.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("%%") ? "" : trimmed
        }.filter { !$0.isEmpty }
        guard let header = lines.first else { throw MermaidError(message: "Empty diagram") }
        let keyword = header.split(separator: " ").first.map(String.init) ?? ""
        switch keyword {
        case "graph", "flowchart": return .flowchart(try flowchart(header: header, lines: Array(lines.dropFirst())))
        case "sequenceDiagram": return .sequence(try sequence(Array(lines.dropFirst())))
        default: throw MermaidError(message: "“\(keyword)” diagrams are shown as source")
        }
    }

    // MARK: Flowcharts

    static func flowchart(header: String, lines: [String]) throws -> MermaidDiagram.Flowchart {
        let parts = header.split(separator: " ")
        let raw = parts.count > 1 ? String(parts[1]).uppercased() : "TD"
        var chart = MermaidDiagram.Flowchart(direction: raw == "TB" ? .down : .init(rawValue: raw) ?? .down, nodes: [], edges: [])
        var index: [String: Int] = [:]
        func node(_ id: String, label: String?, shape: MermaidDiagram.Flowchart.Shape?) {
            if let existing = index[id] {
                if let label { chart.nodes[existing].label = label }
                if let shape { chart.nodes[existing].shape = shape }
            } else {
                index[id] = chart.nodes.count
                chart.nodes.append(.init(id: id, label: label ?? id, shape: shape ?? .rectangle))
            }
        }
        let ignored = ["subgraph", "end", "classDef", "class", "style", "linkStyle", "click", "direction", "accTitle", "accDescr"]
        for statement in lines.flatMap({ $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) } }) where !statement.isEmpty {
            if let first = statement.split(separator: " ").first, ignored.contains(String(first)) { continue }
            var scanner = Scanner(Array(statement))
            var previous = try scanner.nodes()
            guard !previous.isEmpty else { throw MermaidError(message: "Cannot read “\(statement)”") }
            for item in previous { node(item.id, label: item.label, shape: item.shape) }
            while !scanner.atEnd {
                guard let link = scanner.link() else { throw MermaidError(message: "Cannot read “\(statement)”") }
                let next = try scanner.nodes()
                guard !next.isEmpty else { throw MermaidError(message: "A link needs a target in “\(statement)”") }
                for item in next { node(item.id, label: item.label, shape: item.shape) }
                for a in previous { for b in next {
                    chart.edges.append(.init(from: a.id, to: b.id, label: link.label, arrow: link.arrow, dotted: link.dotted, thick: link.thick))
                } }
                previous = next
            }
        }
        guard !chart.nodes.isEmpty else { throw MermaidError(message: "The flowchart has no nodes") }
        return chart
    }

    struct Scanner {
        struct Item { let id: String; let label: String?; let shape: MermaidDiagram.Flowchart.Shape? }
        struct Link { let label: String?; let arrow: Bool; let dotted: Bool; let thick: Bool }
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }
        var atEnd: Bool {
            var next = index
            while next < chars.count, chars[next] == " " { next += 1 }
            return next >= chars.count
        }
        mutating func spaces() { while index < chars.count, chars[index] == " " { index += 1 } }
        var rest: String { String(chars[index...]) }

        mutating func nodes() throws -> [Item] {
            var items: [Item] = []
            repeat {
                spaces()
                if index < chars.count, chars[index] == "&" { index += 1; spaces() }
                guard let item = try node() else { break }
                items.append(item); spaces()
            } while index < chars.count && chars[index] == "&"
            return items
        }
        mutating func node() throws -> Item? {
            var id = ""
            while index < chars.count, chars[index].isLetter || chars[index].isNumber || "_.:".contains(chars[index]) || chars[index] == "-" && !nextIsLink {
                id.append(chars[index]); index += 1
            }
            guard !id.isEmpty else { return nil }
            let shapes: [(String, String, MermaidDiagram.Flowchart.Shape)] = [
                ("(((", ")))", .circle), ("((", "))", .circle), ("([", "])", .stadium), ("[[", "]]", .subroutine), ("[(", ")]", .cylinder),
                ("{{", "}}", .hexagon), ("[/", "/]", .rectangle), ("[\\", "\\]", .rectangle), ("[", "]", .rectangle), ("(", ")", .rounded),
                ("{", "}", .rhombus), (">", "]", .flag),
            ]
            for (open, close, shape) in shapes where rest.hasPrefix(open) {
                let body = String(chars[(index + open.count)...])
                guard let end = body.range(of: close) else { throw MermaidError(message: "Missing “\(close)”") }
                var label = String(body[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                if label.hasPrefix("\""), label.hasSuffix("\""), label.count >= 2 { label = String(label.dropFirst().dropLast()) }
                index += open.count + body.distance(from: body.startIndex, to: end.upperBound)
                return Item(id: id, label: Self.clean(label), shape: shape)
            }
            return Item(id: id, label: nil, shape: nil)
        }
        private var nextIsLink: Bool {
            index + 1 < chars.count && (chars[index + 1] == "-" || chars[index + 1] == "." || chars[index + 1] == ">")
        }
        static func clean(_ label: String) -> String {
            label.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n").replacingOccurrences(of: "&quot;", with: "\"")
        }

        mutating func link() -> Link? {
            spaces()
            let text = rest
            // `A -- label --> B`, `A -. label .-> B`, `A == label ==> B`
            if let match = text.firstMatch(of: /^(--|==|-\.)\s+(.+?)\s+(-{2,}>?|={2,}>?|\.+-+>?)/) {
                index += text.distance(from: text.startIndex, to: match.range.upperBound)
                let token = String(match.output.3)
                return Link(label: Self.clean(String(match.output.2)), arrow: token.hasSuffix(">"), dotted: match.output.1 == "-.", thick: match.output.1 == "==")
            }
            guard let match = text.firstMatch(of: /^<?(-{2,}|={2,}|-\.+-|~~~)(>|x|o)?/) else { return nil }
            index += text.distance(from: text.startIndex, to: match.range.upperBound)
            let body = String(match.output.1)
            var label: String?
            let after = rest
            if after.hasPrefix("|"), let close = after.dropFirst().firstIndex(of: "|") {
                label = Self.clean(String(after[after.index(after: after.startIndex)..<close]).trimmingCharacters(in: .whitespaces))
                index += after.distance(from: after.startIndex, to: close) + 1
            }
            return Link(label: label, arrow: match.output.2 != nil, dotted: body.contains("."), thick: body.hasPrefix("="))
        }
    }

    // MARK: Sequence diagrams

    static func sequence(_ lines: [String]) throws -> MermaidDiagram.Sequence {
        var diagram = MermaidDiagram.Sequence(participants: [], events: [])
        func participant(_ raw: String) -> String {
            let id = raw.trimmingCharacters(in: CharacterSet(charactersIn: " +-"))
            if !diagram.participants.contains(where: { $0.id == id }) { diagram.participants.append(.init(id: id, label: id)) }
            return id
        }
        for line in lines {
            if let match = line.firstMatch(of: /^(participant|actor)\s+(.+?)(?:\s+as\s+(.+))?$/) {
                let id = participant(String(match.output.2))
                if let alias = match.output.3, let at = diagram.participants.firstIndex(where: { $0.id == id }) {
                    diagram.participants[at].label = String(alias)
                }
                continue
            }
            if let match = line.firstMatch(of: /^[Nn]ote\s+(?:over|left of|right of)\s+([^:]+):\s*(.*)$/) {
                let ids = match.output.1.split(separator: ",").map { participant(String($0)) }
                diagram.events.append(.note(over: ids, text: MermaidParser.Scanner.clean(String(match.output.2)))); continue
            }
            if let match = line.firstMatch(of: /^(loop|alt|else|opt|par|and|critical|break|rect|box)\b\s*(.*)$/) {
                let label = [String(match.output.1), String(match.output.2)].filter { !$0.isEmpty }.joined(separator: " ")
                diagram.events.append(.block(label)); continue
            }
            if line == "end" { diagram.events.append(.end); continue }
            if line.hasPrefix("activate ") || line.hasPrefix("deactivate ") || line.hasPrefix("autonumber") || line.hasPrefix("title") { continue }
            if let match = line.firstMatch(of: /^([^-<>:]+?)\s*(-->>|->>|-->|->|--x|-x|--\)|-\))\s*([^:]+?)\s*:\s*(.*)$/) {
                let arrow = String(match.output.2)
                diagram.events.append(.message(from: participant(String(match.output.1)), to: participant(String(match.output.3)),
                    text: MermaidParser.Scanner.clean(String(match.output.4)), dashed: arrow.hasPrefix("--"), arrow: arrow.contains(">") || arrow.contains("x") || arrow.contains(")")))
                continue
            }
            throw MermaidError(message: "Cannot read “\(line)”")
        }
        guard !diagram.participants.isEmpty else { throw MermaidError(message: "The diagram has no participants") }
        return diagram
    }
}

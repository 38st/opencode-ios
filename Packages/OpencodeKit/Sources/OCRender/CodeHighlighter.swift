import Foundation
import SwiftTreeSitter
import Grammar_swift
import Grammar_typescript
import Grammar_tsx
import Grammar_javascript
import Grammar_python
import Grammar_json
import Grammar_bash
import Grammar_go
import Grammar_rust
import Grammar_markdown
import Grammar_yaml
import Grammar_html
import Grammar_css

public struct HighlightSpan: Equatable, Sendable {
    public enum Kind: String, Sendable { case comment, keyword, string, number, type, property, punctuation }
    public let range: NSRange
    public let kind: Kind
}

/// The cache is actor-owned. Each parser and tree stays inside one concurrent worker.
public actor CodeHighlighter {
    public static let shared = CodeHighlighter()
    private var cache: [String: (spans: [HighlightSpan], bytes: Int)] = [:]
    private var order: [String] = []
    private var cacheBytes = 0
    public init() {}
    public func highlight(_ source: String, language: String?, characterLimit: Int? = nil) async -> [HighlightSpan] {
        guard characterLimit.map({ source.count <= $0 }) ?? (source.utf8.count <= 262_144), let language else { return [] }
        let key = language + ":" + MarkdownBlock.hash(source)
        if let cached = cache[key] { return cached.spans }
        let spans = await Self.spans(source, language: language)
        if cache[key] != nil { return spans }
        let cost = spans.count * MemoryLayout<HighlightSpan>.stride + key.utf8.count + 64
        guard cost <= 8 * 1024 * 1024 else { return spans }
        cache[key] = (spans, cost); order.append(key); cacheBytes += cost
        while cacheBytes > 8 * 1024 * 1024, !order.isEmpty {
            cacheBytes -= cache.removeValue(forKey: order.removeFirst())?.bytes ?? 0
        }
        return spans
    }
    @concurrent private static func spans(_ source: String, language: String) async -> [HighlightSpan] {
        guard let grammar = grammar(language.lowercased()) else { return [] }
        let parser = Parser()
        guard (try? parser.setLanguage(grammar)) != nil, let root = parser.parse(source)?.rootNode else { return [] }
        // A cursor visits each node once. Node.child(at:) is linear in its index, so walking a large
        // file's top-level children that way is quadratic. Each grammar symbol is classified once.
        let cursor = root.treeCursor
        var classes: [Int: Classification] = [:], spans: [HighlightSpan] = [], visited = 0
        walk: while let node = cursor.currentNode {
            visited += 1
            if visited & 4_095 == 0, Task.isCancelled { return [] }
            let symbol = node.symbol
            let value = classes[symbol] ?? Classification(type: node.nodeType ?? "", named: node.isNamed)
            classes[symbol] = value
            if let kind = value.kind ?? (node.childCount == 0 ? value.leafKind : nil) {
                let range = node.range
                if range.length > 0 { spans.append(.init(range: range, kind: kind)) }
            } else if cursor.goToFirstChild() { continue }
            while !cursor.gotoNextSibling() { if !cursor.gotoParent() { break walk } }
        }
        // Pre-order traversal already yields spans in document order.
        return spans
    }
    private struct Classification {
        /// The kind of every node with this symbol, and the kind it has only as a leaf.
        let kind: HighlightSpan.Kind?, leafKind: HighlightSpan.Kind?
        init(type: String, named: Bool) {
            kind = CodeHighlighter.kind(type, named: named, leaf: false)
            leafKind = CodeHighlighter.kind(type, named: named, leaf: true)
        }
    }
    private static func kind(_ type: String, named: Bool, leaf: Bool) -> HighlightSpan.Kind? {
        if type.contains("comment") { return .comment }
        if ["string", "string_literal", "line_string_literal", "multi_line_string_literal", "raw_string_literal", "interpreted_string_literal", "string_value", "quoted_attribute_value", "string_content"].contains(type) { return .string }
        if type.contains("integer") || type.contains("float") || ["number", "number_literal", "boolean", "true", "false", "null", "nil"].contains(type) { return .number }
        if ["type_identifier", "type_name", "primitive_type", "tag_name"].contains(type) { return .type }
        if ["property_identifier", "attribute_name", "field_identifier"].contains(type) { return .property }
        if ["atx_heading", "setext_heading"].contains(type) { return .keyword }
        if leaf && !named {
            return type.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) || $0 == "_" } ? .keyword : .punctuation
        }
        return nil
    }
    private static func grammar(_ language: String) -> OpaquePointer? {
        switch language {
        case "swift": tree_sitter_swift()
        case "typescript", "ts": tree_sitter_typescript()
        case "tsx": tree_sitter_tsx()
        case "javascript", "js", "jsx": tree_sitter_javascript()
        case "python", "py": tree_sitter_python()
        case "json", "jsonc": tree_sitter_json()
        case "bash", "sh", "shell", "zsh": tree_sitter_bash()
        case "go", "golang": tree_sitter_go()
        case "rust", "rs": tree_sitter_rust()
        case "markdown", "md": tree_sitter_markdown()
        case "yaml", "yml": tree_sitter_yaml()
        case "html": tree_sitter_html()
        case "css": tree_sitter_css()
        default: nil
        }
    }
}

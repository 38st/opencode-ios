import Foundation

public enum FileLanguage {
    public static func language(for path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "ts", "mts", "cts": "typescript"
        case "tsx": "tsx"
        case "js", "jsx", "mjs", "cjs": "javascript"
        case "py", "pyi": "python"
        case "json", "jsonc": "json"
        case "sh", "bash", "zsh": "bash"
        case "go": "go"
        case "rs": "rust"
        case "md", "markdown": "markdown"
        case "yaml", "yml": "yaml"
        case "html", "htm", "svg": "html"
        case "css": "css"
        default: nil
        }
    }
}

public actor DiffHighlighter {
    public static let shared = DiffHighlighter()
    private var cache: [String: DiffDocument] = [:]
    private var order: [String] = []
    private var bytes = 0
    public func highlight(_ document: DiffDocument, path: String, hash: String) async -> DiffDocument {
        let key = path + ":" + hash + ":" + String(document.fullFile) + ":" + document.kind.rawValue
        if let cached = cache[key] { return cached }
        var value = document
        let oldText = document.oldText, newText = document.newText
        async let oldSpans = CodeHighlighter.shared.highlight(oldText, language: FileLanguage.language(for: path), characterLimit: 500_000)
        async let newSpans = CodeHighlighter.shared.highlight(newText, language: FileLanguage.language(for: path), characterLimit: 500_000)
        let both = await (oldSpans, newSpans)
        for old in [true, false] {
            let indices = value.lines.indices.filter { old ? value.lines[$0].oldLine != nil : value.lines[$0].newLine != nil }
            let text = indices.map { value.lines[$0].text }.joined(separator: "\n")
            guard text.count <= 500_000 else { continue }
            let spans = old ? both.0 : both.1
            var offset = 0, cursor = 0
            for i in indices {
                let line = value.lines[i].text, count = line.utf16.count
                if line.count <= 1_000 {
                    while cursor < spans.count && NSMaxRange(spans[cursor].range) <= offset { cursor += 1 }
                    var j = cursor, mapped: [HighlightSpan] = []
                    while j < spans.count && spans[j].range.location < offset + count {
                        let range = NSIntersectionRange(spans[j].range, NSRange(location: offset, length: count))
                        if range.length > 0 { mapped.append(.init(range: .init(location: range.location - offset, length: range.length), kind: spans[j].kind)) }
                        j += 1
                    }
                    value.lines[i].syntax = mapped
                }
                offset += count + 1
            }
        }
        let cost = Self.cost(value, key: key)
        if cost <= 20 * 1024 * 1024 {
            cache[key] = value; order.append(key); bytes += cost
            while bytes > 20 * 1024 * 1024, let oldest = order.first {
                order.removeFirst()
                if let evicted = cache.removeValue(forKey: oldest) { bytes -= Self.cost(evicted, key: oldest) }
            }
        }
        return value
    }
    private static func cost(_ document: DiffDocument, key: String) -> Int {
        document.lines.reduce(0) { $0 + $1.text.utf8.count + $1.syntax.count * 32 + $1.words.count * 16 + 128 }
            + document.headers.reduce(0) { $0 + $1.utf8.count } + key.utf8.count + 128
    }
}

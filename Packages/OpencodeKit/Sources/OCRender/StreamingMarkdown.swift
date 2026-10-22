import Foundation
import Markdown
import OCModels

public struct MarkdownBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public let source: String
    public let code: String?
    public let language: String?
    public let closed: Bool
    public let attributed: AttributedString
    public init(source: String, code: String? = nil, language: String? = nil, closed: Bool = true, identity: String? = nil, attributed: AttributedString? = nil) {
        self.source = source; self.code = code; self.language = language; self.closed = closed
        self.id = identity ?? Self.hash(source)
        var parsed = attributed ?? ((try? AttributedString(markdown: source)) ?? AttributedString(source))
        for run in parsed.runs {
            // Strip image attributes before Textual ever resolves attachments.
            if run.imageURL != nil { parsed[run.range].imageURL = nil }
            if let url = run.link {
                let scheme = url.scheme?.lowercased()
                let file = FileLink(url.absoluteString)
                let fileLink = scheme == nil || scheme == "file" || file.isAbsolute || (file.selection != nil && (scheme?.contains(".") ?? false))
                if !fileLink && !["http", "https", "mailto"].contains(scheme ?? "") { parsed[run.range].link = nil }
            }
        }
        self.attributed = parsed
    }
    public static func hash(_ string: String) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(value, radix: 16)
    }
}

/// One instance per visible text item. The actor serializes parsing and throttling;
/// cancellation never publishes a partial parse or advances the frozen prefix.
public actor StreamingMarkdown {
    private var prefix = ""
    private var finished: [MarkdownBlock] = []
    private var cache: [String: MarkdownBlock] = [:]
    private var lastParse: ContinuousClock.Instant?
    public private(set) var parseCount = 0
    public private(set) var parsedBytes = 0
    public init() {}

    public func update(_ raw: String, complete: Bool = false) async throws -> [MarkdownBlock] {
        while let lastParse {
            let deadline = lastParse.advanced(by: .nanoseconds(83_333_334))
            guard deadline > .now else { break }
            try await Task.sleep(until: deadline, clock: .continuous)
        }
        try Task.checkCancellation()
        let text = ModelOutputCleanup.clean(raw)
        if !text.hasPrefix(prefix) { prefix = ""; finished = [] }
        let tail = String(text.dropFirst(prefix.count))
        let fence = MarkdownFence.unclosed(in: tail)
        let parseSource = fence.map { tail + "\n" + $0 } ?? tail
        let document = Document(parsing: parseSource, options: [.parseBlockDirectives])
        lastParse = .now; parseCount += 1; parsedBytes += parseSource.utf8.count
        let children = Array(document.children)
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var tailBlocks: [MarkdownBlock] = []
        var freezeEnd = 0
        for (index, child) in children.enumerated() {
            let startLine = max(0, (child.range?.lowerBound.line ?? 1) - 1)
            let nextLine = index + 1 < children.count ? max(0, (children[index + 1].range?.lowerBound.line ?? 1) - 1) : lines.count
            let endLine = min(lines.count, nextLine)
            guard startLine < endLine else { continue }
            let source = lines[startLine..<endLine].joined(separator: "\n") + (endLine < lines.count ? "\n" : "")
            let closed = fence == nil || index != children.count - 1
            let key = MarkdownBlock.hash(source)
            let block: MarkdownBlock
            if let cached = cache[key], cached.source == source, cached.closed == closed { block = cached }
            else {
                let code = child as? CodeBlock
                block = MarkdownBlock(source: source, code: code?.code, language: code?.language, closed: closed)
                if closed { cache[key] = block }
            }
            tailBlocks.append(block)
            if index < children.count - 1 || complete { freezeEnd = endLine }
        }
        let count = complete ? tailBlocks.count : max(0, tailBlocks.count - 1)
        let result = finished + tailBlocks
        if count > 0 {
            let consumed = lines.prefix(freezeEnd).joined(separator: "\n") + (freezeEnd < lines.count ? "\n" : "")
            prefix += consumed; finished += tailBlocks.prefix(count)
        }
        if cache.count > 512 { cache = Dictionary(finished.suffix(256).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
        return result.enumerated().map { index, block in
            // Repeated identical paragraphs must have distinct SwiftUI identities.
            MarkdownBlock(source: block.source, code: block.code, language: block.language, closed: block.closed, identity: "\(index)", attributed: block.attributed)
        }
    }
}

enum MarkdownFence {
    static func containerContent(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        while value.hasPrefix(">") { value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if value.hasPrefix("- ") || value.hasPrefix("* ") || value.hasPrefix("+ ") { value = String(value.dropFirst(2)) }
        if let range = value.range(of: #"^\d+[.)] "#, options: .regularExpression) { value.removeSubrange(range) }
        return value
    }

    static func marker(_ line: String) -> String? {
        let trimmed = containerContent(line).trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = String(trimmed.prefix { $0 == first })
        return run.count >= 3 ? run : nil
    }
    static func unclosed(in text: String) -> String? {
        var fence: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let marker = marker(String(line)) else { continue }
            if let open = fence {
                if marker.first == open.first && marker.count >= open.count && containerContent(String(line)).trimmingCharacters(in: .whitespaces) == marker { fence = nil }
            } else { fence = marker }
        }
        return fence
    }
}

import Foundation

public struct DiffLine: Equatable, Sendable {
    public enum Kind: String, Sendable { case context, addition, deletion, noNewline, raw }
    public var kind: Kind
    public var text: String
    public var oldLine: Int?
    public var newLine: Int?
    public var hasNewline = true
    public var words: [NSRange] = []
    public var syntax: [HighlightSpan] = []
    public init(kind: Kind, text: String, oldLine: Int? = nil, newLine: Int? = nil) {
        self.kind = kind; self.text = text; self.oldLine = oldLine; self.newLine = newLine
    }
    public var displayText: String { text.replacingOccurrences(of: "\t", with: "  ").replacingOccurrences(of: "\r", with: "␍") }
}

public struct DiffHunk: Equatable, Sendable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var heading: String
    public var lines: Range<Int>
}

public struct DiffDocument: Equatable, Sendable {
    public enum Kind: String, Sendable { case text, empty, binary, headerOnly, raw }
    public var kind: Kind
    public var headers: [String]
    public var hunks: [DiffHunk]
    public var lines: [DiffLine]
    public var fullFile: Bool
    public init(kind: Kind = .text, headers: [String] = [], hunks: [DiffHunk] = [], lines: [DiffLine] = [], fullFile: Bool = true) {
        self.kind = kind; self.headers = headers; self.hunks = hunks; self.lines = lines; self.fullFile = fullFile
    }
    public var firstChangedLine: Int? {
        for hunk in hunks {
            var next = max(1, hunk.newStart)
            for line in lines[hunk.lines] {
                if line.kind == .addition || line.kind == .deletion { return line.newLine ?? next }
                if let number = line.newLine { next = number < Int.max ? number + 1 : number }
            }
        }
        return nil
    }
    public var oldText: String { sideText(old: true) }
    public var newText: String { sideText(old: false) }
    private func sideText(old: Bool) -> String {
        lines.filter { old ? $0.oldLine != nil : $0.newLine != nil }.map { $0.text + ($0.hasNewline ? "\n" : "") }.joined()
    }
}

public enum DiffParser {
    @concurrent public static func prepare(_ patch: String, fullFile: Bool = true) async -> DiffDocument {
        var result = parse(patch, fullFile: fullFile)
        WordDiff.apply(to: &result)
        return result
    }
    public static func parse(_ patch: String, fullFile: Bool = true) -> DiffDocument {
        if patch.isEmpty { return .init(kind: .empty, fullFile: fullFile) }
        let input = patch.components(separatedBy: "\n")
        var doc = DiffDocument(fullFile: fullFile), old = 0, new = 0, consumedOld = 0, consumedNew = 0
        func raw() -> DiffDocument { .init(kind: .raw, lines: input.map { .init(kind: .raw, text: $0) }, fullFile: false) }
        func valid() -> Bool { guard let h = doc.hunks.last else { return true }; return consumedOld == h.oldCount && consumedNew == h.newCount }
        let regex = try? NSRegularExpression(pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@([^\n]*)$"#)
        for (index, text) in input.enumerated() {
            if index == input.count - 1 && text.isEmpty { break }
            if text.hasPrefix("@@") {
                guard valid(), let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return raw() }
                func number(_ i: Int, default fallback: Int) -> Int? {
                    if match.range(at: i).location == NSNotFound { return fallback }
                    guard let range = Range(match.range(at: i), in: text) else { return nil }; return Int(text[range])
                }
                guard let os = number(1, default: 0), let oc = number(2, default: 1), let ns = number(3, default: 0), let nc = number(4, default: 1),
                      os < Int.max - oc, ns < Int.max - nc else { return raw() }
                old = os; new = ns; consumedOld = 0; consumedNew = 0
                doc.hunks.append(.init(oldStart: os, oldCount: oc, newStart: ns, newCount: nc, heading: text, lines: doc.lines.count..<doc.lines.count))
                continue
            }
            if doc.hunks.isEmpty {
                doc.headers.append(text)
                if text.hasPrefix("Binary files ") || text.hasPrefix("GIT binary patch") { doc.kind = .binary }
                continue
            }
            let line: DiffLine
            if text.hasPrefix("\\ No newline at end of file") {
                if !doc.lines.isEmpty { doc.lines[doc.lines.count - 1].hasNewline = false }
                line = .init(kind: .noNewline, text: text)
            }
            else if text.hasPrefix("+") {
                guard new < Int.max else { return raw() }
                line = .init(kind: .addition, text: String(text.dropFirst()), newLine: new); new += 1; consumedNew += 1
            } else if text.hasPrefix("-") {
                guard old < Int.max else { return raw() }
                line = .init(kind: .deletion, text: String(text.dropFirst()), oldLine: old); old += 1; consumedOld += 1
            } else if text.hasPrefix(" ") {
                guard old < Int.max, new < Int.max else { return raw() }
                line = .init(kind: .context, text: String(text.dropFirst()), oldLine: old, newLine: new); old += 1; new += 1; consumedOld += 1; consumedNew += 1
            } else { return raw() }
            doc.lines.append(line)
            let last = doc.hunks.count - 1
            doc.hunks[last].lines = doc.hunks[last].lines.lowerBound..<doc.lines.count
            if consumedOld > doc.hunks[last].oldCount || consumedNew > doc.hunks[last].newCount { return raw() }
        }
        guard valid() else { return raw() }
        if doc.hunks.isEmpty && doc.kind != .binary {
            let headers = doc.headers.contains { $0.hasPrefix("--- ") || $0.hasPrefix("diff --git ") || $0.hasPrefix("Index: ") }
            if !headers { return raw() }; doc.kind = .headerOnly
        }
        if doc.hunks.count != 1 || (doc.hunks.first?.oldStart ?? 0) > 1 || (doc.hunks.first?.newStart ?? 0) > 1 { doc.fullFile = false }
        return doc
    }
}

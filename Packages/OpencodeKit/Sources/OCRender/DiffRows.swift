import Foundation

public struct DiffRow: Equatable, Sendable, Identifiable {
    public var id: Int
    public var left: DiffLine?
    public var right: DiffLine?
    public var hidden: Range<Int>?
    public var expandable = false
    public var commentID: String?
    public var commentOnOldSide = false
    public var label: String?
    public init(id: Int, left: DiffLine? = nil, right: DiffLine? = nil, hidden: Range<Int>? = nil, expandable: Bool = false, label: String? = nil, commentID: String? = nil) {
        self.id = id; self.left = left; self.right = right; self.hidden = hidden; self.expandable = expandable; self.label = label; self.commentID = commentID
    }
}

public struct DiffExpansion: Equatable, Sendable {
    public var revealed: Set<Int> = []
    public init() {}
    public mutating func expand(_ range: Range<Int>, fromEnd: Bool = false, all: Bool = false) {
        if all { revealed.formUnion(range) }
        else if fromEnd { revealed.formUnion(range.suffix(20)) }
        else { revealed.formUnion(range.prefix(20)) }
    }
}

public enum DiffRows {
    @concurrent public static func prepare(_ document: DiffDocument, split: Bool = false, showAll: Bool = false, expansion: DiffExpansion = .init()) async -> [DiffRow] {
        make(document, split: split, showAll: showAll, expansion: expansion)
    }
    public static func make(_ document: DiffDocument, split: Bool = false, showAll: Bool = false, expansion: DiffExpansion = .init()) -> [DiffRow] {
        var visible = IndexSet(integersIn: document.lines.indices), folded: [Int: Range<Int>] = [:]
        if !showAll && document.fullFile {
            var index = 0
            while index < document.lines.count {
                guard document.lines[index].kind == .context else { index += 1; continue }
                let start = index
                while index < document.lines.count && document.lines[index].kind == .context { index += 1 }
                let lower = start == 0 ? start : min(index, start + 4)
                let upper = index == document.lines.count ? index : max(lower, index - 4)
                var run: Int?
                for i in lower..<upper {
                    if expansion.revealed.contains(i) {
                        if let r = run { folded[r] = r..<i; run = nil }
                    } else { visible.remove(i); if run == nil { run = i } }
                }
                if let r = run { folded[r] = r..<upper }
            }
        }
        var rows: [DiffRow] = [], index = 0
        let hunkStarts = Dictionary(document.hunks.enumerated().map { ($0.element.lines.lowerBound, $0.offset) }, uniquingKeysWith: { a, _ in a })
        while index < document.lines.count {
            if !document.fullFile, let h = hunkStarts[index] {
                rows.append(.init(id: -h - 1, label: document.hunks[h].heading))
            }
            if let range = folded[index] {
                rows.append(.init(id: index, hidden: range, expandable: true, label: localized("\(range.count) hidden lines", comment: "%lld is the number of folded unchanged lines"))); index = range.upperBound; continue
            }
            if !visible.contains(index) { index += 1; continue }
            let line = document.lines[index]
            if split && [.addition, .deletion].contains(line.kind) {
                var a: [(Int, DiffLine)] = [], b: [(Int, DiffLine)] = [], notes: [(Int, DiffLine)] = []
                while index < document.lines.count && [.addition, .deletion, .noNewline].contains(document.lines[index].kind) {
                    let next = document.lines[index]
                    if next.kind == .deletion { a.append((index, next)) }
                    else if next.kind == .addition { b.append((index, next)) }
                    else { notes.append((index, next)) }
                    index += 1
                }
                for i in 0..<max(a.count, b.count) {
                    rows.append(.init(id: i < a.count ? a[i].0 : b[i].0, left: i < a.count ? a[i].1 : nil, right: i < b.count ? b[i].1 : nil))
                }
                rows += notes.map { .init(id: $0.0, left: $0.1) }
            } else {
                rows.append(.init(id: index, left: line, right: split && line.kind == .context ? line : nil)); index += 1
            }
        }
        return rows
    }
}

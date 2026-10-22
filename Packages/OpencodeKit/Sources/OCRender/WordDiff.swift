import Foundation

public enum WordDiff {
    public struct Token: Equatable, Sendable {
        public let text: String
        public let range: NSRange
    }
    public static func tokens(_ text: String) -> [Token] {
        var result: [Token] = [], start = text.startIndex, position = 0, category: Int?
        func kind(_ c: Character) -> Int { c.isWhitespace ? 1 : c.isLetter || c.isNumber || c == "_" ? 2 : 3 }
        for index in text.indices {
            let next = kind(text[index])
            if let category, next != category || next == 3 {
                let value = String(text[start..<index]); result.append(.init(text: value, range: NSRange(location: position, length: value.utf16.count)))
                position += value.utf16.count; start = index
            }
            category = next
        }
        if start < text.endIndex { let value = String(text[start...]); result.append(.init(text: value, range: NSRange(location: position, length: value.utf16.count))) }
        return result
    }
    public static func changed(_ old: String, _ new: String) -> ([NSRange], [NSRange]) {
        guard old.count <= 1_000, new.count <= 1_000 else { return ([], []) }
        let a = tokens(old), b = tokens(new)
        var removed: [NSRange] = [], added: [NSRange] = []
        for change in b.map(\.text).difference(from: a.map(\.text)) {
            switch change {
            case .remove(let i, _, _): removed.append(a[i].range)
            case .insert(let i, _, _): added.append(b[i].range)
            }
        }
        return (removed, added)
    }
    public static func apply(to document: inout DiffDocument) {
        let oldPlain = document.oldText.count > 500_000, newPlain = document.newText.count > 500_000
        var index = 0
        while index < document.lines.count {
            guard [.addition, .deletion].contains(document.lines[index].kind) else { index += 1; continue }
            var removed: [Int] = [], added: [Int] = []
            while index < document.lines.count, [.addition, .deletion, .noNewline].contains(document.lines[index].kind) {
                if document.lines[index].kind == .deletion { removed.append(index) }
                if document.lines[index].kind == .addition { added.append(index) }
                index += 1
            }
            for pair in 0..<max(removed.count, added.count) {
                let a = pair < removed.count ? removed[pair] : nil, b = pair < added.count ? added[pair] : nil
                let spans = changed(a.map { document.lines[$0].text } ?? "", b.map { document.lines[$0].text } ?? "")
                if let a, !oldPlain { document.lines[a].words = spans.0 }
                if let b, !newPlain { document.lines[b].words = spans.1 }
            }
        }
    }
}

import Foundation

/// Finds TeX in Markdown with the desktop app's rules (`ui/src/context/marked-parser.tsx`): `$$…$$` and a block of
/// `$$` lines are display math; `$…$` needs a non-space after the opening and before the closing `$`, and no digit
/// after it, so prices stay text; `\(…\)` is inline. Code spans are never touched.
public enum MathMarkdown {
    /// The TeX of a block that is display math only, or nil.
    public static func display(_ block: String) -> String? {
        let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > open.count + close.count {
            let inner = String(text.dropFirst(open.count).dropLast(close.count))
            guard !inner.contains(open), !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Replaces inline formulas that parse with their Unicode form, escaped for Markdown. A formula that does not parse
    /// stays as written.
    public static func inline(_ markdown: String) -> String {
        guard markdown.contains("$") || markdown.contains("\\(") else { return markdown }
        let chars = Array(markdown)
        var out = "", index = 0
        while index < chars.count {
            let c = chars[index]
            if c == "`" {
                // Copy a code span through its closing run of the same length.
                var run = 0
                while index + run < chars.count && chars[index + run] == "`" { run += 1 }
                let fence = String(repeating: "`", count: run)
                let rest = String(chars[(index + run)...])
                if let end = rest.range(of: fence) {
                    let length = run + rest.distance(from: rest.startIndex, to: end.upperBound)
                    out += String(chars[index..<index + length]); index += length
                } else { out += fence; index += run }
                continue
            }
            if c == "\\" && index + 1 < chars.count {
                if chars[index + 1] == "(", let end = find(")", escaped: true, in: chars, from: index + 2),
                   let replaced = render(String(chars[(index + 2)..<end])) {
                    out += replaced; index = end + 2; continue
                }
                out.append(c); out.append(chars[index + 1]); index += 2; continue
            }
            if c == "$" {
                let display = index + 1 < chars.count && chars[index + 1] == "$"
                let start = index + (display ? 2 : 1)
                if let end = closing(in: chars, from: start, display: display), let replaced = render(String(chars[start..<end])) {
                    out += replaced; index = end + (display ? 2 : 1); continue
                }
                out.append(c); index += 1
                if display { out.append("$"); index += 1 }
                continue
            }
            out.append(c); index += 1
        }
        return out
    }

    private static func closing(in chars: [Character], from start: Int, display: Bool) -> Int? {
        guard start < chars.count else { return nil }
        if !display && chars[start].isWhitespace { return nil }
        var index = start
        while index < chars.count {
            if chars[index] == "\n" && index + 1 < chars.count && chars[index + 1] == "\n" { return nil }
            if chars[index] == "\\" { index += 2; continue }
            if chars[index] == "$" {
                if display {
                    if index + 1 < chars.count && chars[index + 1] == "$" { return index > start ? index : nil }
                } else {
                    let before = chars[index - 1]
                    let after = index + 1 < chars.count ? chars[index + 1] : " "
                    if index > start && !before.isWhitespace && !after.isNumber && !(after.isLetter || after == "_") { return index }
                    return nil
                }
            }
            index += 1
        }
        return nil
    }
    private static func find(_ close: Character, escaped: Bool, in chars: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "\\" && chars[index + 1] == close { return index }
            if chars[index] == "\n" && chars[index + 1] == "\n" { return nil }
            index += 1
        }
        return nil
    }
    private static func render(_ tex: String) -> String? {
        guard !tex.trimmingCharacters(in: .whitespaces).isEmpty, let node = try? MathParser.parse(tex) else { return nil }
        var escaped = ""
        for c in node.unicode {
            if "\\`*_[]<>#|~".contains(c) { escaped.append("\\") }
            escaped.append(c)
        }
        return escaped
    }
}

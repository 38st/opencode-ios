import Foundation

/// Inline code that may name a file (`markdown-inline-code-kind.ts` and `markdown.tsx` in the reference).
/// A candidate becomes a link only after the host confirms the file exists, so this stays a cheap syntax check.
public enum InlineCodeLinks {
    /// Common files with no extension. Anything else needs a `.`, `/` or `\` to look like a file.
    static let fileNames: Set<String> = ["CHANGELOG", "CODEOWNERS", "Containerfile", "Dockerfile", "Gemfile", "Justfile",
                                         "LICENSE", "Makefile", "Procfile", "README", "Rakefile", "Vagrantfile"]

    public static func isPath(_ text: String) -> Bool {
        guard !text.isEmpty, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              text.range(of: #"^[a-z][a-z0-9+.-]*://"#, options: [.regularExpression, .caseInsensitive]) == nil,
              // Code, globs and markup, not paths.
              text.rangeOfCharacter(from: CharacterSet(charactersIn: "{}<>\"'`;=|&*,")) == nil,
              // A network share would make the server connect to the host just to check it.
              text.range(of: #"^[\\/]{2}"#, options: .regularExpression) == nil else { return false }
        let path = FileLink(text, normalizingPath: false).path
        if fileNames.contains(path) { return true }
        return path.range(of: #"[./\\]"#, options: .regularExpression) != nil && path.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    /// Distinct path-like inline code, in order of appearance, outside fenced code and link text.
    public static func candidates(in markdown: String, limit: Int = 24) -> [String] {
        var seen: Set<String> = [], result: [String] = []
        for span in spans(in: markdown) where seen.insert(span.text).inserted {
            result.append(span.text)
            if result.count == limit { break }
        }
        return result
    }

    /// Rewrites each confirmed inline code span as a link to its own text.
    public static func link(_ markdown: String, existing: Set<String>) -> String {
        guard !existing.isEmpty else { return markdown }
        var result = markdown
        for span in spans(in: markdown).reversed() where existing.contains(span.text) {
            let href = span.text.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: " ", with: "%20")
                .replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
            result.replaceSubrange(span.range, with: "[`\(span.text)`](\(href))")
        }
        return result
    }

    private struct Span { let range: Range<String.Index>; let text: String }

    private static func spans(in markdown: String) -> [Span] {
        guard let code = try? NSRegularExpression(pattern: #"(?<!`)`([^`\n]+)`(?!`)"#) else { return [] }
        var result: [Span] = [], fence: (character: Character, count: Int)?
        var lineStart = markdown.startIndex
        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = markdown[lineStart..<lineEnd]
            let trimmed = line.drop { $0 == " " }
            if line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" {
                let run = trimmed.prefix { $0 == first }.count
                if run >= 3 {
                    if let open = fence { if open.character == first && run >= open.count && trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil } }
                    else { fence = (first, run) }
                    lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : lineEnd
                    continue
                }
            }
            if fence == nil {
                let text = String(line)
                for match in code.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
                    let value = text[inner].trimmingCharacters(in: .whitespaces)
                    // Code inside a link already goes where the link does.
                    guard isPath(value), !insideLinkText(text, whole) else { continue }
                    let offset = text.distance(from: text.startIndex, to: whole.lowerBound)
                    let lower = markdown.index(lineStart, offsetBy: offset)
                    let upper = markdown.index(lower, offsetBy: text.distance(from: whole.lowerBound, to: whole.upperBound))
                    result.append(Span(range: lower..<upper, text: value))
                }
            }
            lineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : lineEnd
        }
        return result
    }

    private static func insideLinkText(_ line: String, _ span: Range<String.Index>) -> Bool {
        let before = line[..<span.lowerBound], after = line[span.upperBound...]
        guard let open = before.lastIndex(of: "["), !before[open...].contains("]") else { return false }
        guard let close = after.firstIndex(of: "]") else { return false }
        return !after[..<close].contains("[") && after[close...].hasPrefix("](")
    }
}

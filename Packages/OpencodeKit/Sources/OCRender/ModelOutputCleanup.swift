import Foundation

/// Removes `<think>` … `</think>` reasoning that leaks into a model's answer text.
/// Literal tags in fenced, indented and inline code are preserved byte for byte.
public enum ModelOutputCleanup {
    public static func clean(_ text: String) -> String {
        var fence: String?, inlineFence: String?, thinking = false
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            if let marker = MarkdownFence.marker(line) {
                if let open = fence {
                    if marker.first == open.first && marker.count >= open.count && MarkdownFence.containerContent(line).trimmingCharacters(in: .whitespaces) == marker { fence = nil }
                } else { fence = marker }
                result.append(line); continue
            }
            if fence != nil || isIndentedCode(line) { result.append(line); continue }
            var output = "", cursor = line.startIndex
            while cursor < line.endIndex {
                if let delimiter = inlineFence {
                    if let close = line.range(of: delimiter, range: cursor..<line.endIndex) {
                        output += line[cursor..<close.upperBound]; cursor = close.upperBound; inlineFence = nil; continue
                    }
                    output += line[cursor...]; break
                }
                if line[cursor] == "`" {
                    let end = line[cursor...].firstIndex { $0 != "`" } ?? line.endIndex
                    let delimiter = String(line[cursor..<end])
                    if let close = line.range(of: delimiter, range: end..<line.endIndex) {
                        output += line[cursor..<close.upperBound]; cursor = close.upperBound; continue
                    }
                    inlineFence = delimiter; output += line[cursor...]; break
                }
                if line[cursor] == "<", line[cursor...].prefix(7).lowercased() == "<think>" {
                    thinking = true; cursor = line.index(cursor, offsetBy: 7); continue
                }
                if line[cursor] == "<", line[cursor...].prefix(8).lowercased() == "</think>" {
                    thinking = false; cursor = line.index(cursor, offsetBy: 8); continue
                }
                if !thinking { output.append(line[cursor]) }
                cursor = line.index(after: cursor)
            }
            result.append(output)
        }
        return result.joined(separator: "\n")
    }
    private static func isIndentedCode(_ line: String) -> Bool {
        var content = line[...]
        while true {
            var marker = content
            for _ in 0..<3 where marker.first == " " { marker = marker.dropFirst() }
            guard marker.first == ">" else { break }
            content = marker.dropFirst()
            if content.first == " " { content = content.dropFirst() }
        }
        return content.hasPrefix("    ") || content.hasPrefix("\t")
    }
}

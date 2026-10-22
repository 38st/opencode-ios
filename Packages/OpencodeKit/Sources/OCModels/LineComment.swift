import Foundation
import OCFoundation

public struct LineSelection: Codable, Equatable, Hashable, Sendable {
    public enum Side: String, Codable, Sendable { case additions, deletions }
    public var start: Int
    public var end: Int
    public var side: Side
    public var endSide: Side
    public var newStart: Int?
    public var newEnd: Int?
    public init(start: Int, end: Int? = nil, side: Side = .additions, endSide: Side? = nil) {
        self.start = max(1, start); self.end = max(1, end ?? start); self.side = side; self.endSide = endSide ?? side
    }
    public var lower: Int { min(start, end) }
    public var upper: Int { max(start, end) }
    public var deleted: Bool { side == .deletions && endSide == .deletions }
    public var label: String { lower == upper ? "line \(lower)" : "lines \(lower)-\(upper)" }
    /// A mixed range has only one known new-side endpoint. Do not send old-side coordinates.
    public var newRange: ClosedRange<Int> {
        if let a = newStart, let b = newEnd { return min(a, b)...max(a, b) }
        return side == endSide ? lower...upper : (side == .additions ? start...start : end...end)
    }
}

public struct LineComment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var file: String
    public var selection: LineSelection?
    public var comment: String
    public var time: Date
    public var origin: String
    public var preview: String
    public var deletedText: String
    public init(id: String = UUID().uuidString, file: String, selection: LineSelection? = nil, comment: String,
                time: Date = Date(), origin: String = "review", preview: String = "", deletedText: String = "") {
        self.id = id; self.file = file; self.selection = selection; self.comment = comment; self.time = time
        self.origin = origin; self.preview = preview; self.deletedText = deletedText
    }
    public var note: String {
        let range: String
        if let selection {
            let bounds = selection.deleted ? selection.lower...selection.upper : selection.newRange
            let prefix = selection.deleted ? "deleted " : ""
            range = bounds.lowerBound == bounds.upperBound ? "\(prefix)line \(bounds.lowerBound)" : "\(prefix)lines \(bounds.lowerBound) through \(bounds.upperBound)"
        } else { range = "this file" }
        var result = "The user made the following comment regarding \(range) of \(file): \(comment.trimmingCharacters(in: .whitespacesAndNewlines))"
        if selection?.deleted == true {
            let text = deletedText.components(separatedBy: "\n").prefix(20).joined(separator: "\n")
            let fence = String(repeating: "`", count: max(3, (text.components(separatedBy: CharacterSet(charactersIn: "`\n").inverted).map(\.count).max() ?? 0) + 1))
            result += "\n\(fence)\n\(text)\n\(fence)"
        }
        return result
    }
    public var metadata: JSONValue {
        var value: JSONValue = .object(["path": .string(file), "comment": .string(comment.trimmingCharacters(in: .whitespacesAndNewlines)),
                                       "preview": .string(preview), "origin": .string(origin)])
        if let selection {
            let range = selection.deleted ? selection.lower...selection.upper : selection.newRange
            value.set("selection", .object(["startLine": .integer(Int64(range.lowerBound)), "startChar": .integer(0),
                                             "endLine": .integer(Int64(range.upperBound)), "endChar": .integer(0)]))
            if selection.deleted { value.set("side", .string("deletions")); value.set("deletedText", .string(deletedText)) }
        }
        return value
    }
    public static func restore(_ raw: JSONValue) -> [Self] {
        if raw["metadata"]?["displayText"]?.stringValue != nil, let entries = raw["metadata"]?["comments"]?.arrayValue {
            return entries.compactMap { entry in
                guard let file = entry["path"]?.stringValue, let comment = entry["comment"]?.stringValue else { return nil }
                if let type = entry["type"], !type.isNull, type.stringValue != "file" { return nil }
                if let preview = entry["preview"], !preview.isNull, preview.stringValue == nil { return nil }
                if let origin = entry["origin"], !origin.isNull, !["review", "file"].contains(origin.stringValue ?? "") { return nil }
                var selection: LineSelection?
                if let value = entry["selection"], !value.isNull {
                    guard let start = value["startLine"]?.wireInt, let end = value["endLine"]?.wireInt,
                          start > 0, end > 0, value["startChar"]?.wireInt != nil, value["endChar"]?.wireInt != nil else { return nil }
                    selection = .init(start: start, end: end, side: entry["side"]?.stringValue == "deletions" ? .deletions : .additions)
                }
                return .init(file: file, selection: selection, comment: comment, origin: entry["origin"]?.stringValue ?? "review",
                             preview: entry["preview"]?.stringValue ?? "", deletedText: entry["deletedText"]?.stringValue ?? "")
            }
        }
        return parseNote(raw["text"]?.stringValue ?? "").map { [$0] } ?? []
    }
    private static let notePattern = try? NSRegularExpression(pattern: #"^The user made the following comment regarding (this file|line (\d+)|lines (\d+) through (\d+)) of (.+?): ([\s\S]+)$"#)
    private static let mentionPattern = try? NSRegularExpression(pattern: #"(?:^|[\s(\[{"'])@(\S+)"#)
    public static func parseNote(_ text: String) -> Self? {
        guard text.hasPrefix("The user made the following comment regarding "), let regex = notePattern,
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func part(_ n: Int) -> String? { Range(m.range(at: n), in: text).map { String(text[$0]) } }
        guard let file = part(5), let comment = part(6) else { return nil }
        let start = part(2).flatMap(Int.init) ?? part(3).flatMap(Int.init)
        let end = part(2).flatMap(Int.init) ?? part(4).flatMap(Int.init)
        return .init(file: file, selection: start.map { .init(start: $0, end: end) }, comment: comment)
    }
    public static func mentions(_ text: String) -> [String] {
        guard let regex = mentionPattern else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            var path = String(text[r])
            while let last = path.last, ".,!?;:)}]\"'".contains(last) { path.removeLast() }
            return path.isEmpty ? nil : path
        }
    }
}

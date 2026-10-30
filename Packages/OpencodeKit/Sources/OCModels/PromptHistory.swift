import Foundation
import OCFoundation

/// Earlier prompts to recall in the composer: this session's first, newest first, then the project's other sessions.
/// The same text appears once, at its newest position.
public enum PromptHistory {
    public struct Entry: Hashable, Sendable, Identifiable {
        public let text: String
        public let sessionID: String
        public let created: Double
        public var id: String { sessionID + "\u{0}" + text }
        public init(text: String, sessionID: String, created: Double) { self.text = text; self.sessionID = sessionID; self.created = created }
    }
    public static let limit = 100

    /// - Parameters:
    ///   - session: user prompts of the current session, in any order.
    ///   - project: user prompts of the project's other sessions.
    public static func entries(session: [Entry], project: [Entry], limit: Int = limit) -> [Entry] {
        var seen = Set<String>(), result: [Entry] = []
        for entry in session.sorted(by: newest) + project.sorted(by: newest) {
            let key = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }
    private static func newest(_ a: Entry, _ b: Entry) -> Bool { a.created > b.created || a.created == b.created && a.text < b.text }

    /// Steps through the entries with ↑ (older) and ↓ (newer). Stepping down past the newest restores the unsent draft.
    public struct Cursor: Equatable, Sendable {
        public private(set) var index: Int?
        public private(set) var draft: String?
        public init() {}
        public mutating func older(_ entries: [Entry], current: String) -> String? {
            let next = (index ?? -1) + 1
            guard entries.indices.contains(next) else { return nil }
            if index == nil { draft = current }
            index = next
            return entries[next].text
        }
        public mutating func newer(_ entries: [Entry]) -> String? {
            guard let index else { return nil }
            if index == 0 { self.index = nil; defer { draft = nil }; return draft ?? "" }
            self.index = index - 1
            return entries.indices.contains(index - 1) ? entries[index - 1].text : nil
        }
        public mutating func reset() { index = nil; draft = nil }
    }
}

/// A requested move, from the request to `session.moved`: the server holds it as a `move` inbox item until the
/// session reaches a delivery boundary.
public enum SessionMove: Equatable, Sendable {
    case pending(directory: String, delivery: Delivery)
    case applied(directory: String)
    case failed(directory: String, message: String)

    /// The session's state seen from its inbox and location. A pending item wins over a requested move the server
    /// has not echoed yet.
    public static func state(requested: SessionMove?, pending: [InboxItem], location: String) -> SessionMove? {
        if let item = pending.last(where: { $0.type == "move" }) {
            return .pending(directory: item.fields.payload["location"]?["directory"]?.stringValue ?? "", delivery: item.delivery)
        }
        switch requested {
        case .pending(let directory, _)?: return directory == location ? .applied(directory: directory) : requested
        case let other: return other
        }
    }
    public var directory: String {
        switch self { case .pending(let value, _), .applied(let value), .failed(let value, _): value }
    }
}

/// The working timer's text, as the desktop app writes durations: "42s", "1m 05s", "2h 03m".
public enum ElapsedTime {
    public static func format(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m " + pad(seconds % 60) + "s" }
        return "\(seconds / 3_600)h " + pad(seconds / 60 % 60) + "m"
    }
    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}

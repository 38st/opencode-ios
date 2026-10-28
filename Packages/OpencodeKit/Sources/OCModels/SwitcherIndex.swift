// Sources: packages/app/src/shell/commands/{palette.ts,dialog.tsx}, home/sessions/search.ts and session/search.ts.
// The desktop asks one server to search; this index ranks the sessions every paired server has cached, so the
// switcher also works offline.
import Foundation

public struct SwitcherEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case command(WorkspaceCommand)
        case session(SessionRef)
        /// A Home project filter value, `<server UUID>:<project ID>`.
        case project(String)
    }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var shortcut: String?
    public init(id: String, kind: Kind, title: String, detail: String = "", shortcut: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail; self.shortcut = shortcut
    }
}
public struct SwitcherGroup: Equatable, Sendable, Identifiable {
    public var title: String
    public var entries: [SwitcherEntry]
    public var id: String { title }
    public init(title: String, entries: [SwitcherEntry]) { self.title = title; self.entries = entries }
}

public enum SwitcherIndex {
    public struct Session: Equatable, Sendable {
        public var ref: SessionRef
        public var title: String
        public var project: String
        public var updated: Double
        public init(ref: SessionRef, title: String, project: String, updated: Double) {
            self.ref = ref; self.title = title; self.project = project; self.updated = updated
        }
    }
    public struct Project: Equatable, Sendable {
        /// Home's project filter value.
        public var filter: String
        public var name: String
        public var path: String
        public var server: String
        public init(filter: String, name: String, path: String, server: String) {
            self.filter = filter; self.name = name; self.path = path; self.server = server
        }
    }
    public static let recentLimit = 5
    /// The palette opens with these, in this order (desktop `COMMON_COMMAND_IDS` and `COMMON_VIEW_COMMAND_IDS`).
    public static let preferred: [WorkspaceCommand] = [.newSession, .previousSession, .nextSession, .toggleReview]
    /// Desktop `looksLikeSessionID`.
    public static func looksLikeSessionID(_ value: String) -> Bool { value.count > 20 && value.hasPrefix("ses_") }

    /// `commands` are the enabled ones; the desktop leaves disabled commands out of its palette.
    public static func groups(query: String, commands: [WorkspaceCommand], sessions: [Session], projects: [Project]) -> [SwitcherGroup] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recent = sessions.sorted(by: newer)
        guard !search.isEmpty else {
            let picked = preferred.filter(commands.contains)
            let shown = picked.isEmpty ? Array(commands.prefix(recentLimit)) : picked
            return [SwitcherGroup(title: "Commands", entries: shown.map(entry)),
                    SwitcherGroup(title: "Recent sessions", entries: recent.prefix(recentLimit).map(entry))].filter { !$0.entries.isEmpty }
        }
        let value = search.lowercased()
        let exact = looksLikeSessionID(search) ? recent.filter { $0.ref.sessionID == search } : []
        let matchedSessions = rank(recent.filter { !exact.contains($0) }, value) { $0.title + " " + $0.project }
        let matchedCommands = rank(commands, value) { $0.title + " " + $0.menu.rawValue }
        let matchedProjects = rank(projects, value) { $0.name + " " + $0.path }
        return [SwitcherGroup(title: "Commands", entries: matchedCommands.map(entry)),
                SwitcherGroup(title: "Sessions", entries: (exact + matchedSessions).map(entry)),
                SwitcherGroup(title: "Projects", entries: matchedProjects.map(entry))].filter { !$0.entries.isEmpty }
    }
    /// Substring matches first, in the given order, then subsequence matches by score.
    static func rank<Item>(_ items: [Item], _ value: String, text: (Item) -> String) -> [Item] {
        var contained: [Item] = [], fuzzy: [(Int, Int, Item)] = []
        for (index, item) in items.enumerated() {
            let candidate = text(item).lowercased()
            if candidate.contains(value) { contained.append(item) }
            else if let score = fuzzyScore(value, in: candidate) { fuzzy.append((score, index, item)) }
        }
        return contained + fuzzy.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.2)
    }
    /// The query's characters in order, spaces ignored. Lower is better: each skipped character costs one, and a
    /// match that does not start a word costs one more.
    public static func fuzzyScore(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.filter { !$0.isWhitespace }), haystack = Array(candidate)
        guard !needle.isEmpty else { return nil }
        var score = 0, position = 0, previous: Int?
        for character in needle {
            guard let found = haystack[position...].firstIndex(of: character) else { return nil }
            if let previous { score += found - previous - 1 }
            if found > 0, haystack[found - 1].isLetter || haystack[found - 1].isNumber { score += 1 }
            previous = found; position = found + 1
        }
        return score
    }
    /// Updated first, then ID: the order Home and the desktop's session list use.
    static func newer(_ a: Session, _ b: Session) -> Bool { a.updated != b.updated ? a.updated > b.updated : a.ref.id < b.ref.id }
    static func entry(_ command: WorkspaceCommand) -> SwitcherEntry {
        .init(id: "command:" + command.id, kind: .command(command), title: command.title, detail: command.menu.rawValue, shortcut: command.chord.description)
    }
    static func entry(_ session: Session) -> SwitcherEntry {
        .init(id: "session:" + session.ref.id, kind: .session(session.ref), title: session.title, detail: session.project)
    }
    static func entry(_ project: Project) -> SwitcherEntry {
        .init(id: "project:" + project.filter, kind: .project(project.filter), title: project.name, detail: project.server)
    }
}

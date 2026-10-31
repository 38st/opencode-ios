import Foundation

/// The widget sizes the extension draws, with how many session rows each one lists.
public enum WidgetSize: String, CaseIterable, Sendable {
    case small, medium, large, circular, rectangular, inline
    public var capacity: Int {
        switch self {
        case .small, .rectangular: 1
        case .medium: 3
        case .large: 6
        case .circular, .inline: 0
        }
    }
    public var isAccessory: Bool { [.circular, .rectangular, .inline].contains(self) }
}

/// What one widget shows, built from the snapshot and the push store's pending counts. The extension only draws it.
public struct WidgetContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The gallery's sample, drawn redacted.
        case placeholder
        /// The app has never written a snapshot, or wrote one this extension cannot read.
        case noData
        /// A newer app wrote it; the app needs to run once more.
        case needsApp
        case noServer
        /// The widget's server was removed from the app.
        case serverRemoved
        case empty
        case rows
    }
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// "project · server", or the project alone when one server is shown.
        public var detail: String
        public var status: SystemSnapshot.Status
        public var requestKind: SystemSnapshot.Request.Kind?
        public var requests: Int
        public var unread: Bool
        /// The start of the run for a running row, else the last activity.
        public var date: Date
        public var url: URL?
        public init(id: String, title: String, detail: String, status: SystemSnapshot.Status, requestKind: SystemSnapshot.Request.Kind? = nil,
                    requests: Int = 0, unread: Bool = false, date: Date, url: URL? = nil) {
            self.id = id; self.title = title; self.detail = detail; self.status = status; self.requestKind = requestKind
            self.requests = requests; self.unread = unread; self.date = date; self.url = url
        }
        /// Home's words for the row's state; `stale` rows only say what was last seen.
        public func label(stale: Bool) -> String {
            switch status {
            case .needsYou: requestKind == .question ? localized("Question", comment: "Session status: waiting on a question") : localized("Permission", comment: "Session status: waiting on a permission request")
            case .failed: localized("Failed", comment: "Session status")
            case .running: stale ? localized("Last seen running") : localized("Running", comment: "Session status")
            case .retrying: stale ? localized("Last seen retrying") : localized("Retrying", comment: "Session status")
            case .idle: unread ? localized("Unread", comment: "Session status") : localized("Idle", comment: "Session status")
            }
        }
    }
    public var kind: WidgetKind
    public var state: State
    /// The configured server's name; nil when the widget shows every server.
    public var serverName: String?
    /// Needs you: waiting permissions and questions. Running: running sessions. Recent: listed sessions.
    public var count: Int
    public var rows: [Row]
    /// Rows that did not fit.
    public var overflow: Int
    public var stale: Bool
    /// When the shown data was last in sync with its servers.
    public var updated: Date?
    public init(kind: WidgetKind, state: State, serverName: String? = nil, count: Int = 0, rows: [Row] = [], overflow: Int = 0, stale: Bool = false, updated: Date? = nil) {
        self.kind = kind; self.state = state; self.serverName = serverName; self.count = count; self.rows = rows
        self.overflow = overflow; self.stale = stale; self.updated = updated
    }
    /// Where a tap outside the rows goes: the first row, or the app when there is none.
    public var url: URL? { rows.first?.url }
}

public extension WidgetContent {
    /// - Parameters:
    ///   - pending: each server's waiting requests from `PushSnapshotStore`; a server it lacks counts its rows' requests.
    ///   - server: the configured server's ID, or nil for all servers.
    static func make(_ read: SystemSnapshotStore.Read, pending: [String: Int], kind: WidgetKind, server: String?, size: WidgetSize, now: Date) -> WidgetContent {
        let snapshot: SystemSnapshot
        switch read {
        case .missing, .unreadable: return .init(kind: kind, state: .noData)
        case .newer: return .init(kind: kind, state: .needsApp)
        case .snapshot(let value): snapshot = value
        }
        guard !snapshot.servers.isEmpty else { return .init(kind: kind, state: .noServer) }
        if let server, snapshot.server(server) == nil { return .init(kind: kind, state: .serverRemoved) }
        let servers = snapshot.servers.filter { server == nil || $0.id == server }
        let sessions: [SystemSnapshot.Session] = switch kind {
        case .needsYou: snapshot.needsYou(server: server)
        case .running: snapshot.running(server: server)
        case .recent: snapshot.recent(server: server)
        }
        let showsServer = server == nil && snapshot.servers.count > 1
        let rows = sessions.map { session in
            Row(id: session.id, title: session.title, detail: showsServer ? session.project + " · " + (snapshot.server(session.server)?.name ?? "") : session.project,
                status: session.status, requestKind: session.request?.kind, requests: session.requests, unread: session.unread,
                date: kind == .running ? (session.runningSince ?? session.activity) : session.activity, url: session.url)
        }
        let count: Int = switch kind {
        case .needsYou: servers.reduce(0) { total, item in
            total + (pending[item.id] ?? snapshot.sessions.filter { $0.server == item.id }.reduce(0) { $0 + $1.requests })
        }
        case .running: rows.count
        case .recent: rows.count
        }
        let stale = now >= staleDate(snapshot, server: server)
        let synced = servers.contains { $0.reachability == .online } ? snapshot.writtenAt : (servers.compactMap(\.syncedAt).max() ?? snapshot.writtenAt)
        // A medium widget has room for three rows, or two and the footer that counts the rest or says they are stale.
        let capacity = size == .medium && (rows.count > size.capacity || stale) ? size.capacity - 1 : size.capacity
        return .init(kind: kind, state: rows.isEmpty ? .empty : .rows, serverName: server.flatMap { snapshot.server($0)?.name },
                     count: count, rows: Array(rows.prefix(capacity)), overflow: max(0, rows.count - capacity),
                     stale: stale, updated: synced)
    }
    /// When the data turns stale from time alone: a server that is not online 15 minutes after its last sync, and any
    /// snapshot an hour after it was written.
    static func staleDate(_ snapshot: SystemSnapshot, server: String?) -> Date {
        let abandoned = snapshot.writtenAt.addingTimeInterval(SystemDefaults.abandonedAfter)
        let servers = snapshot.servers.filter { server == nil || $0.id == server }
        guard !servers.isEmpty, !servers.contains(where: { $0.reachability == .online }) else { return abandoned }
        let synced = servers.compactMap(\.syncedAt).max() ?? snapshot.writtenAt
        return min(abandoned, synced.addingTimeInterval(SystemDefaults.staleAfter))
    }
    /// The gallery's sample, drawn redacted.
    static func placeholder(kind: WidgetKind, size: WidgetSize) -> WidgetContent {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [("Review the connection changes", "opencode-ios"), ("Port the session panel widths", "desktop"), ("Fix the pairing flow", "opencode-ios"),
                       ("Write the release notes", "docs"), ("Tidy the review fixtures", "opencode-ios"), ("Profile the transcript", "opencode-ios")]
        let status: SystemSnapshot.Status = kind == .needsYou ? .needsYou : kind == .running ? .running : .idle
        let rows = samples.prefix(size.capacity).enumerated().map { index, sample in
            Row(id: "sample-\(index)", title: sample.0, detail: sample.1, status: status, requestKind: kind == .needsYou ? .permission : nil,
                requests: kind == .needsYou ? 1 : 0, date: now.addingTimeInterval(Double(-index) * 600))
        }
        return .init(kind: kind, state: .placeholder, count: kind == .recent ? rows.count : 2, rows: rows)
    }
}

/// A widget's timeline: the content now and, when it will turn stale from time alone, again at that moment.
public struct WidgetTimelinePlan: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var date: Date
        public var content: WidgetContent
    }
    public var entries: [Entry]
    /// When WidgetKit should ask again; the app reloads the timeline whenever it writes new content.
    public var refresh: Date
    public static func make(_ read: SystemSnapshotStore.Read, pending: [String: Int], kind: WidgetKind, server: String?, size: WidgetSize, now: Date) -> WidgetTimelinePlan {
        let current = WidgetContent.make(read, pending: pending, kind: kind, server: server, size: size, now: now)
        guard current.state == .rows || current.state == .empty, !current.stale, let snapshot = read.snapshot else {
            return .init(entries: [.init(date: now, content: current)], refresh: now.addingTimeInterval(SystemDefaults.abandonedAfter))
        }
        let staleAt = WidgetContent.staleDate(snapshot, server: server)
        var later = current; later.stale = true
        return .init(entries: [.init(date: now, content: current), .init(date: staleAt, content: later)],
                     refresh: staleAt.addingTimeInterval(SystemDefaults.abandonedAfter))
    }
}

/// What the two controls show.
public enum ControlContent {
    /// New prompt's project, if the app knows one.
    public static func newPromptProject(_ read: SystemSnapshotStore.Read) -> String? { read.snapshot?.lastProject?.name }
    /// Review approval's waiting requests: the app icon badge's number.
    public static func waitingRequests(_ pending: [String: Int]) -> Int { pending.values.reduce(0) { $0 + max(0, $1) } }
    public static func waitingText(_ count: Int) -> String { count == 0 ? localized("None waiting", comment: "No approval requests are waiting") : localized("\(count) waiting", comment: "%lld is the number of waiting approval requests") }
}

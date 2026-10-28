import Darwin
import Foundation
import OCFoundation

/// What the app shares with its widgets, controls and intents: the servers, the sessions that need you, running and
/// recent sessions, projects for Shortcuts, and New prompt's project. Titles and names only: no credentials,
/// addresses, paths, prompts, transcript text or request details. Pending counts stay in `PushSnapshotStore`.
public struct SystemSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = SystemSnapshot.currentVersion
    public var writtenAt: Date
    public var servers: [Server] = []
    /// Root sessions: every one that needs you or runs (each capped), then the most recent others.
    public var sessions: [Session] = []
    public var projects: [Project] = []
    /// Where the user last opened or sent to a session; New prompt starts there.
    public var lastProject: ProjectRef?
    /// Whether Siri and Shortcuts may suggest session titles: the app's Spotlight switch.
    public var suggestsSessions = true

    public init(writtenAt: Date, servers: [Server] = [], sessions: [Session] = [], projects: [Project] = [], lastProject: ProjectRef? = nil,
                suggestsSessions: Bool = true) {
        self.writtenAt = writtenAt; self.servers = servers; self.sessions = sessions; self.projects = projects; self.lastProject = lastProject
        self.suggestsSessions = suggestsSessions
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 0
        writtenAt = (try? container.decodeIfPresent(Date.self, forKey: .writtenAt)) ?? .distantPast
        servers = (try? container.decodeIfPresent(Lossy<Server>.self, forKey: .servers))?.values ?? []
        sessions = (try? container.decodeIfPresent(Lossy<Session>.self, forKey: .sessions))?.values ?? []
        projects = (try? container.decodeIfPresent(Lossy<Project>.self, forKey: .projects))?.values ?? []
        lastProject = (try? container.decodeIfPresent(ProjectRef.self, forKey: .lastProject)) ?? nil
        suggestsSessions = (try? container.decodeIfPresent(Bool.self, forKey: .suggestsSessions)) ?? true
    }
    /// Equal apart from when it was written: an unchanged snapshot is not written again.
    public func hasSameContent(as other: SystemSnapshot) -> Bool {
        var copy = other; copy.writtenAt = writtenAt
        return self == copy
    }

    /// Coarse, so a reconnect that retries does not rewrite the file at every attempt.
    public enum Reachability: String, Codable, Sendable {
        case online, offline, paused, needsRepair, unsupported
        public init(from decoder: any Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .offline }
    }
    public struct Server: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var reachability: Reachability
        /// The last full sync with the server; what the rows of a server that is not online date from.
        public var syncedAt: Date?
        public init(id: String, name: String, reachability: Reachability, syncedAt: Date? = nil) {
            self.id = id; self.name = name; self.reachability = reachability; self.syncedAt = syncedAt
        }
    }
    public enum Status: String, Codable, Sendable {
        case needsYou, failed, running, retrying, idle
        public init(from decoder: any Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .idle }
        public var needsYou: Bool { self == .needsYou || self == .failed }
        public var isRunning: Bool { self == .running || self == .retrying }
    }
    /// What a needs-you row opens: the first waiting request, or the failure.
    public struct Request: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case permission, question, failure
            public init(from decoder: any Decoder) throws { self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .permission }
        }
        public var id: String
        public var kind: Kind
        /// The session that owns it when that is a subagent of the row's session.
        public var session: String?
        public init(id: String, kind: Kind, session: String? = nil) { self.id = id; self.kind = kind; self.session = session }
    }
    public struct Session: Codable, Sendable, Equatable, Identifiable {
        public var server: String
        public var session: String
        public var title: String
        /// The project's display name; never its path.
        public var project: String
        public var projectID: String
        public var status: Status
        public var unread: Bool
        /// Last activity, to the minute.
        public var activity: Date
        public var runningSince: Date?
        /// Waiting permissions and questions in the session and its subagents.
        public var requests: Int
        public var request: Request?
        public init(server: String, session: String, title: String, project: String, projectID: String, status: Status, unread: Bool = false,
                    activity: Date, runningSince: Date? = nil, requests: Int = 0, request: Request? = nil) {
            self.server = server; self.session = session; self.title = title; self.project = project; self.projectID = projectID
            self.status = status; self.unread = unread; self.activity = activity; self.runningSince = runningSince
            self.requests = requests; self.request = request
        }
        public var id: String { server + ":" + session }
        /// The session, or the request or failure it waits on, in the session that owns it.
        public var url: URL? {
            guard let serverID = UUID(uuidString: server) else { return nil }
            guard status.needsYou, let request else { return DeepLink.url(serverID: serverID, sessionID: session) }
            return DeepLink.url(serverID: serverID, sessionID: request.session ?? session, requestID: request.id)
        }
    }
    public struct Project: Codable, Sendable, Equatable, Identifiable {
        public var server: String
        public var project: String
        public var name: String
        public var activity: Date
        public init(server: String, project: String, name: String, activity: Date) {
            self.server = server; self.project = project; self.name = name; self.activity = activity
        }
        public var id: String { server + ":" + project }
    }
    public struct ProjectRef: Codable, Sendable, Equatable {
        public var server: String
        public var project: String
        public var name: String
        public init(server: String, project: String, name: String) { self.server = server; self.project = project; self.name = name }
    }
}

public extension SystemSnapshot {
    func server(_ id: String) -> Server? { servers.first { $0.id == id } }
    /// The sessions a widget lists, newest first within each list; `server` limits them to one server.
    func needsYou(server: String? = nil) -> [Session] {
        sessions.filter { $0.status.needsYou && (server == nil || $0.server == server) }
            .sorted { ($0.status == .needsYou ? 0 : 1, -$0.activity.timeIntervalSince1970) < ($1.status == .needsYou ? 0 : 1, -$1.activity.timeIntervalSince1970) }
    }
    func running(server: String? = nil) -> [Session] {
        sessions.filter { $0.status.isRunning && (server == nil || $0.server == server) }.sorted { $0.activity > $1.activity }
    }
    func recent(server: String? = nil) -> [Session] {
        sessions.filter { server == nil || $0.server == server }.sorted { $0.activity > $1.activity }
    }
}

/// Decodes what it can of an array and drops the rest, so one bad row never hides the others.
private struct Lossy<Element: Decodable>: Decodable {
    var values: [Element] = []
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) { values.append(value); continue }
            // A failed decode leaves the container where it was: step over the element as raw JSON.
            guard (try? container.decode(JSONValue.self)) != nil else { break }
        }
    }
}

/// The snapshot file in the App Group, written atomically under the same cross-process lock and protection class as
/// the push store: readable after the first unlock, so widgets draw on a locked phone.
public struct SystemSnapshotStore: Sendable {
    public enum Read: Equatable, Sendable {
        case missing, unreadable
        /// Written by a newer app version than this reader knows.
        case newer(Int)
        case snapshot(SystemSnapshot)
        public var snapshot: SystemSnapshot? { if case .snapshot(let value) = self { value } else { nil } }
    }
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func appGroup(bundle: Bundle = .main) throws -> Self {
        guard let id = bundle.object(forInfoDictionaryKey: "OCAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return .init(directory: directory.appending(path: "System"))
    }
    private var file: URL { directory.appending(path: "snapshot.json") }
    public func read() -> Read {
        do {
            return try transaction {
                guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
                let snapshot = try Self.decoder.decode(SystemSnapshot.self, from: Data(contentsOf: file))
                if snapshot.version > SystemSnapshot.currentVersion { return .newer(snapshot.version) }
                return snapshot.version == SystemSnapshot.currentVersion ? .snapshot(snapshot) : .unreadable
            }
        } catch { return .unreadable }
    }
    public func write(_ snapshot: SystemSnapshot) throws {
        try transaction { try write(Self.encoder.encode(snapshot), to: file) }
    }
    public func remove() throws {
        try transaction { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
    }
    #if DEBUG
    /// Which process ran each intent, for the UI tests.
    public func recordIntent(_ line: String) throws {
        try transaction {
            let url = directory.appending(path: "intent-trace.json")
            var lines = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode([String].self, from: Data(contentsOf: url)) : []
            lines.append(line)
            try write(JSONEncoder().encode(Array(lines.suffix(100))), to: url)
        }
    }
    public func intentTrace() -> [String] {
        (try? transaction {
            let url = directory.appending(path: "intent-trace.json")
            return FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode([String].self, from: Data(contentsOf: url)) : []
        }) ?? []
    }
    public func resetUITestState() throws {
        try transaction {
            for name in ["snapshot.json", "intent-trace.json"] {
                let url = directory.appending(path: name)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
    }
    #endif
    static var encoder: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; return encoder }
    static var decoder: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970; return decoder }
    private func write(_ data: Data, to url: URL) throws {
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url, options: options)
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        let fd = Darwin.open(directory.appending(path: ".lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

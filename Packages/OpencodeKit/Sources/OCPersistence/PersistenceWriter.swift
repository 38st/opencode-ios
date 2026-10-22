import Foundation
import GRDB
import OCFoundation
import OCModels

public struct CachedTranscript: Sendable, Equatable {
    public var messages: [SessionMessage]
    public var olderCursor: String?
    public init(messages: [SessionMessage], olderCursor: String? = nil) { self.messages = messages; self.olderCursor = olderCursor }
}
public struct CacheSnapshot: Sendable {
    public var serverID: String
    public var projects: [Project]
    public var sessions: [SessionInfo]
    public var transcripts: [String: CachedTranscript]
    public init(serverID: String, projects: [Project] = [], sessions: [SessionInfo] = [], transcripts: [String: CachedTranscript] = [:]) {
        self.serverID = serverID; self.projects = projects; self.sessions = sessions; self.transcripts = transcripts
    }
}

public actor PersistenceWriter {
    let database: any DatabaseWriter
    private let sleep: @Sendable (Duration) async throws -> Void
    private let date: @Sendable () -> Date
    private var pending: [String: CacheSnapshot] = [:]
    private var task: Task<Void, Never>?
    public private(set) var lastError: String?
    public private(set) var writeCount = 0
    public let maximumSessions: Int
    public let maximumBytes: Int
    public let metadataOnly: Bool

    public init(url: URL? = nil, maximumSessions: Int = 200, maximumBytes: Int = 300 * 1024 * 1024, metadataOnly: Bool = false,
                date: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) throws {
        self.sleep = sleep; self.date = date
        self.metadataOnly = metadataOnly
        self.maximumSessions = maximumSessions; self.maximumBytes = maximumBytes
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.deletingLastPathComponent().path)
            #endif
            database = try DatabasePool(path: url.path)
            #if os(iOS)
            for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            }
            #endif
        } else { database = try DatabaseQueue() }
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL") }
        try Self.migrator().migrate(database)
        if metadataOnly { try database.write { try $0.execute(sql: "DELETE FROM message; DELETE FROM transcript_window") } }
    }
    deinit { task?.cancel() }
    public static func applicationSupport() throws -> PersistenceWriter {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try .init(url: root.appending(path: "Opencode/cache.sqlite"))
    }
    public func enqueue(_ snapshot: CacheSnapshot) {
        var snapshot = snapshot
        if metadataOnly { snapshot.transcripts = [:] }
        if var old = pending[snapshot.serverID] {
            old.projects = snapshot.projects
            let sessions = Dictionary(old.sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                .merging(Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })) { _, new in new }
            old.sessions = Array(sessions.values)
            old.transcripts.merge(snapshot.transcripts) { _, new in new }
            pending[snapshot.serverID] = old
        } else { pending[snapshot.serverID] = snapshot }
        task?.cancel()
        task = Task { [weak self, sleep] in
            do { try await sleep(.seconds(2)); try Task.checkCancellation(); try await self?.flush() }
            catch is CancellationError {} catch { await self?.failed() }
        }
    }
    private func failed() { lastError = "Could not save the cache." }
    public func flush() throws {
        task?.cancel(); task = nil
        guard !pending.isEmpty else { return }
        let batch = Array(pending.values), now = date().timeIntervalSince1970
        try database.write { db in
            for snapshot in batch { try Self.write(snapshot, at: now, db: db) }
            try Self.retain(db: db, count: maximumSessions, bytes: maximumBytes)
        }
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA incremental_vacuum") }
        pending.removeAll(); writeCount += 1; lastError = nil
    }
    public func stop() throws { try flush(); task?.cancel(); task = nil }
    public func load(serverID: String) throws -> CacheSnapshot {
        try database.read { db in
            let projects = try Self.decode(Project.self, db: db, sql: "SELECT json FROM project WHERE server_id=? ORDER BY active_at DESC", arguments: [serverID])
            let sessions = try Self.decode(SessionInfo.self, db: db, sql: "SELECT json FROM session WHERE server_id=? ORDER BY updated_at DESC", arguments: [serverID])
            return .init(serverID: serverID, projects: projects, sessions: sessions)
        }
    }
    public func transcript(serverID: String, sessionID: String) throws -> CachedTranscript? {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT older_cursor FROM transcript_window WHERE server_id=? AND session_id=?", arguments: [serverID, sessionID]) else { return nil }
            let messages = try Self.decode(SessionMessage.self, db: db, sql: "SELECT json FROM message WHERE server_id=? AND session_id=? ORDER BY position", arguments: [serverID, sessionID])
            try db.execute(sql: "UPDATE session SET accessed_at=? WHERE server_id=? AND id=?", arguments: [date().timeIntervalSince1970, serverID, sessionID])
            return .init(messages: messages, olderCursor: row["older_cursor"])
        }
    }
    public func deleteSession(serverID: String, sessionID: String) throws {
        pending[serverID]?.sessions.removeAll { $0.id == sessionID }
        pending[serverID]?.transcripts.removeValue(forKey: sessionID)
        try database.write { db in try Self.deleteSession(db: db, server: serverID, session: sessionID) }
    }
    static func deleteSession(db: Database, server: String, session: String) throws {
        for table in ["message", "transcript_window", "local_meta"] {
            try db.execute(sql: "DELETE FROM \(table) WHERE server_id=? AND session_id=?", arguments: [server, session])
        }
        try db.execute(sql: "DELETE FROM session WHERE server_id=? AND id=?", arguments: [server, session])
    }
    static func decode<T: Decodable>(_ type: T.Type, db: Database, sql: String, arguments: StatementArguments) throws -> [T] {
        try Data.fetchAll(db, sql: sql, arguments: arguments).compactMap { try? JSONDecoder().decode(type, from: $0) }
    }
    static func bytes(_ raw: JSONValue) throws -> Data { try JSONEncoder().encode(raw) }
    static func write(_ snapshot: CacheSnapshot, at now: Double, db: Database) throws {
        let server = snapshot.serverID
        for p in snapshot.projects {
            try db.execute(sql: "INSERT OR REPLACE INTO project(server_id,id,active_at,json) VALUES (?,?,?,?)", arguments: [server, p.id, p.time.active, try bytes(p.raw)])
        }
        for s in snapshot.sessions {
            try db.execute(sql: """
                INSERT INTO session(server_id,id,parent_id,project_id,directory,title,updated_at,idle_at,viewed_at,outcome,json,accessed_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(server_id,id) DO UPDATE SET
                parent_id=excluded.parent_id,project_id=excluded.project_id,directory=excluded.directory,title=excluded.title,
                updated_at=excluded.updated_at,idle_at=excluded.idle_at,viewed_at=excluded.viewed_at,outcome=excluded.outcome,json=excluded.json
                """, arguments: [server, s.id, s.parentID, s.projectID, s.location.directory, s.title, s.time.updated,
                                   s.time.idle, s.time.viewed, s.outcome, try bytes(s.raw), now])
        }
        for (id, transcript) in snapshot.transcripts {
            try db.execute(sql: "DELETE FROM message WHERE server_id=? AND session_id=?", arguments: [server, id])
            for (position, message) in transcript.messages.enumerated() {
                let complete = message.type != "assistant" || message.time.completed != nil
                try db.execute(sql: "INSERT INTO message(server_id,session_id,id,position,type,complete,json) VALUES (?,?,?,?,?,?,?)",
                               arguments: [server, id, message.id, position, message.type, complete, try bytes(message.raw)])
            }
            try db.execute(sql: "INSERT OR REPLACE INTO transcript_window(server_id,session_id,older_cursor,fetched_at) VALUES (?,?,?,?)",
                           arguments: [server, id, transcript.olderCursor, now])
            try db.execute(sql: "UPDATE session SET accessed_at=? WHERE server_id=? AND id=?", arguments: [now, server, id])
        }
    }
    static func retain(db: Database, count: Int, bytes: Int) throws {
        var rows = try Row.fetchAll(db, sql: "SELECT server_id,id FROM session ORDER BY accessed_at DESC,updated_at DESC")
        let pageSize = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
        while let oldest = rows.last {
            let pages = try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0
            let free = try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
            guard rows.count > max(0, count) || (pages - free) * pageSize > bytes else { break }
            try deleteSession(db: db, server: oldest["server_id"], session: oldest["id"])
            rows.removeLast()
        }
    }
    public func tableNames() throws -> [String] {
        try database.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") }
    }
}

public struct CacheStore: Sendable {
    public let writer: PersistenceWriter
    public init(writer: PersistenceWriter) { self.writer = writer }
    public func save(_ snapshot: CacheSnapshot) async { await writer.enqueue(snapshot) }
    public func load(serverID: String) async throws -> CacheSnapshot { try await writer.load(serverID: serverID) }
    public func transcript(serverID: String, sessionID: String) async throws -> CachedTranscript? { try await writer.transcript(serverID: serverID, sessionID: sessionID) }
    public func flush() async throws { try await writer.flush() }
}

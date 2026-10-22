import Foundation
import GRDB
import OCFoundation
import OCModels

public struct Draft: Codable, Sendable, Equatable {
    public var id: String
    public var serverID: String
    public var sessionID: String?
    public var directory: String?
    /// JSONEncoder's archive of AttributedString; attachments are stored separately.
    public var text: Data
    public var attachments: JSONValue
    public var delivery: String
    public var updatedAt: Date
    public var comments: [LineComment]
    public var options: ComposerOptions
    public init(id: String = UUID().uuidString, serverID: String, sessionID: String? = nil, directory: String? = nil,
                text: Data, attachments: JSONValue = .array([]), delivery: String = "steer", updatedAt: Date = Date(), options: ComposerOptions = .init(), comments: [LineComment] = []) {
        self.id = id; self.serverID = serverID; self.sessionID = sessionID; self.directory = directory
        self.text = text; self.attachments = attachments; self.delivery = delivery; self.updatedAt = updatedAt; self.options = options; self.comments = comments
    }
}
public struct OutboxEntry: Codable, Sendable, Equatable {
    public var id: String
    public var serverID: String
    public var sessionID: String
    public var prelude: Data
    public var body: Data
    public var createdAt: Date
    public var attempts: Int
    public var state: String
    public var operation: String
    public var needsLaunchConfirmation: Bool { state == "needsConfirmation" }
    public init(id: String, serverID: String, sessionID: String, prelude: Data = Data("{}".utf8), body: Data,
                createdAt: Date = Date(), attempts: Int = 0, state: String = "pending", operation: String = "prompt") {
        self.id = id; self.serverID = serverID; self.sessionID = sessionID; self.prelude = prelude
        self.body = body; self.createdAt = createdAt; self.attempts = attempts; self.state = state
        self.operation = operation
    }
}
public actor DraftStore {
    private let writer: PersistenceWriter
    let filesRoot: URL?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var pending: [String: Draft] = [:]
    private var discarded: Set<String> = []
    private var task: Task<Void, Never>?
    public private(set) var lastError: String?
    public init(writer: PersistenceWriter, filesRoot: URL? = nil, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.writer = writer; self.sleep = sleep; self.filesRoot = filesRoot
    }
    deinit { task?.cancel() }
    public func save(_ draft: Draft) {
        guard !discarded.contains(draft.id) else { return }
        pending = pending.filter { _, old in
            old.serverID != draft.serverID || old.sessionID != draft.sessionID ||
                (draft.sessionID == nil && old.directory != draft.directory)
        }
        pending[draft.id] = draft; task?.cancel()
        task = Task { [weak self, sleep] in
            do { try await sleep(.milliseconds(300)); try Task.checkCancellation(); try await self?.flush() }
            catch is CancellationError {} catch { await self?.failed() }
        }
    }
    private func failed() { lastError = "Could not save the draft." }
    public func flush() async throws {
        task?.cancel(); task = nil
        let batch = pending
        for draft in batch.values where !discarded.contains(draft.id) { try await writer.saveDraft(draft) }
        for (id, draft) in batch where pending[id] == draft { pending.removeValue(forKey: id) }
        lastError = nil
    }
    public func load(serverID: String, sessionID: String? = nil, directory: String? = nil) async throws -> Draft? {
        if let draft = pending.values.first(where: { $0.serverID == serverID && $0.sessionID == sessionID && (sessionID != nil || $0.directory == directory) }) { return draft }
        return try await writer.loadDraft(serverID: serverID, sessionID: sessionID, directory: directory)
    }
    /// Call only after the prompt admission is durable. A stale debounce cannot resurrect it.
    public func delete(_ draft: Draft) async throws {
        discarded.insert(draft.id)
        pending.removeValue(forKey: draft.id)
        try await writer.deleteDraft(id: draft.id)
        try removeFiles(draft.id)
    }
    /// The caller locks both composers and flushes their edits before relocating.
    /// INSERT OR REPLACE changes the directory and replaces its old draft atomically;
    /// retaining the source ID also retains every attachment file.
    public func relocate(_ draft: Draft, replacing previous: Draft?) async throws {
        try await flush()
        try await writer.saveDraft(draft)
        if let previous, previous.id != draft.id {
            discarded.insert(previous.id)
            pending.removeValue(forKey: previous.id)
            try? removeFiles(previous.id)
        }
    }
    public static func attachmentDirectory(id: String) throws -> URL {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\") else { throw DraftError.invalidPath }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = root.appending(path: "Drafts").appendingPathComponent(id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
public struct OutboxStore: Sendable {
    public let writer: PersistenceWriter
    public init(writer: PersistenceWriter) { self.writer = writer }
    public func save(_ entry: OutboxEntry) async throws { try await writer.saveOutbox(entry) }
    public func entries(serverID: String) async throws -> [OutboxEntry] { try await writer.outbox(serverID: serverID) }
    public func remove(id: String) async throws { try await writer.removeOutbox(id: id) }
    public func removeSession(serverID: String, sessionID: String) async throws { try await writer.removeSessionOutbox(serverID: serverID, sessionID: sessionID) }
    /// Updating a removed row is a no-op: an echo can acknowledge it during a send.
    public func update(id: String, state: String, attempts: Int? = nil) async throws {
        try await writer.updateOutbox(id: id, state: state, attempts: attempts)
    }
}

extension PersistenceWriter {
    public func loadServers(importing url: URL? = nil) throws -> [ServerRecord] {
        try database.write { db -> [ServerRecord] in
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM cache_migration WHERE key='servers-json')") != true,
               let url {
                if FileManager.default.fileExists(atPath: url.path) {
                    let records = try JSONDecoder().decode([ServerRecord].self, from: Data(contentsOf: url))
                    for record in records {
                        try db.execute(sql: "INSERT OR IGNORE INTO server(id,json) VALUES (?,?)", arguments: [record.id.rawValue.uuidString, try JSONEncoder().encode(record)])
                    }
                }
                try db.execute(sql: "INSERT INTO cache_migration(key) VALUES ('servers-json')")
            }
            return try Self.decode(ServerRecord.self, db: db, sql: "SELECT json FROM server ORDER BY rowid", arguments: [])
        }
    }
    public func saveServers(_ records: [ServerRecord]) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM server")
            for record in records {
                try db.execute(sql: "INSERT INTO server(id,json) VALUES (?,?)", arguments: [record.id.rawValue.uuidString, try JSONEncoder().encode(record)])
            }
        }
    }
    public func saveCatalog(serverID: String, locationKey: String, kind: String, raw: JSONValue) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO catalog(server_id,location_key,kind,fetched_at,json) VALUES (?,?,?,?,?)",
                           arguments: [serverID, locationKey, kind, Date().timeIntervalSince1970, try Self.bytes(raw)])
        }
    }
    public func catalogs(serverID: String) throws -> [String: [String: JSONValue]] {
        try database.read { db -> [String: [String: JSONValue]] in
            var result: [String: [String: JSONValue]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT location_key,kind,json FROM catalog WHERE server_id=?", arguments: [serverID]) {
                let data: Data = row["json"]
                result[row["location_key"], default: [:]][row["kind"]] = try JSONDecoder().decode(JSONValue.self, from: data)
            }
            return result
        }
    }
    func saveDraft(_ draft: Draft) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO draft(id,server_id,session_id,directory,text,attachments_json,delivery,updated_at,options_json,comments_json) VALUES (?,?,?,?,?,?,?,?,?,?)",
                           arguments: [draft.id, draft.serverID, draft.sessionID, draft.directory, draft.text, try Self.bytes(draft.attachments), draft.delivery, draft.updatedAt.timeIntervalSinceReferenceDate, try JSONEncoder().encode(draft.options), try JSONEncoder().encode(draft.comments)])
        }
    }
    func loadDraft(serverID: String, sessionID: String?, directory: String?) throws -> Draft? {
        try database.read { db -> Draft? in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM draft WHERE server_id=? AND session_id IS ? AND (? IS NOT NULL OR directory IS ?)", arguments: [serverID, sessionID, sessionID, directory]) else { return nil }
            let attachments: Data = row["attachments_json"]
            let options: Data = row["options_json"]
            let comments: Data = row["comments_json"]
            return Draft(id: row["id"], serverID: serverID, sessionID: row["session_id"], directory: row["directory"], text: row["text"],
                         attachments: try JSONDecoder().decode(JSONValue.self, from: attachments), delivery: row["delivery"], updatedAt: Date(timeIntervalSinceReferenceDate: row["updated_at"]), options: try JSONDecoder().decode(ComposerOptions.self, from: options), comments: (try? JSONDecoder().decode([LineComment].self, from: comments)) ?? [])
        }
    }
    func deleteDraft(id: String) throws { try database.write { try $0.execute(sql: "DELETE FROM draft WHERE id=?", arguments: [id]) } }
    func saveOutbox(_ entry: OutboxEntry) throws {
        try database.write { db in
            if let old = try Row.fetchOne(db, sql: "SELECT body,prelude,server_id,session_id,operation FROM outbox WHERE id=?", arguments: [entry.id]) {
                let body: Data = old["body"], prelude: Data = old["prelude"]
                guard body == entry.body, prelude == entry.prelude, old["server_id"] as String == entry.serverID,
                      old["session_id"] as String == entry.sessionID, old["operation"] as String == entry.operation else {
                    throw OutboxError.changedAdmission
                }
                return
            }
            try db.execute(sql: "INSERT INTO outbox(id,server_id,session_id,prelude,body,created_at,attempts,state,operation) VALUES (?,?,?,?,?,?,?,?,?)",
                           arguments: [entry.id, entry.serverID, entry.sessionID, entry.prelude, entry.body, entry.createdAt.timeIntervalSinceReferenceDate, entry.attempts, entry.state, entry.operation])
        }
    }
    func outbox(serverID: String) throws -> [OutboxEntry] {
        try database.read { db -> [OutboxEntry] in
            try Row.fetchAll(db, sql: "SELECT * FROM outbox WHERE server_id=? ORDER BY rowid", arguments: [serverID]).map { row -> OutboxEntry in
                OutboxEntry(id: row["id"], serverID: row["server_id"], sessionID: row["session_id"], prelude: row["prelude"], body: row["body"],
                      createdAt: Date(timeIntervalSinceReferenceDate: row["created_at"]), attempts: row["attempts"], state: row["state"], operation: row["operation"])
            }
        }
    }
    func removeOutbox(id: String) throws { try database.write { try $0.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [id]) } }
    func removeSessionOutbox(serverID: String, sessionID: String) throws {
        try database.write { try $0.execute(sql: "DELETE FROM outbox WHERE server_id=? AND session_id=?", arguments: [serverID, sessionID]) }
    }
    func updateOutbox(id: String, state: String, attempts: Int?) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE outbox SET state=?,attempts=COALESCE(?,attempts) WHERE id=?", arguments: [state, attempts, id])
        }
    }
}

public enum OutboxError: Error, Sendable { case changedAdmission }

import Darwin
import Foundation

public struct ShownNotification: Codable, Sendable, Equatable {
    public let id: String
    public let receipt: UUID
    public let keyID: String
    public let server: String
    public let sessionID: String?
    public let rootSessionID: String?
    public let kind: String
    public let digest: String?
    public let summary: String
    public let expiresAt: Date
    public let displayedAt: Date
    public init(id: String, keyID: String, server: String, sessionID: String?, rootSessionID: String?, kind: String,
                digest: String?, summary: String, expiresAt: Date, displayedAt: Date) {
        self.receipt = UUID()
        self.id = id; self.keyID = keyID; self.server = server; self.sessionID = sessionID
        self.rootSessionID = rootSessionID; self.kind = kind; self.digest = digest; self.summary = summary
        self.expiresAt = expiresAt; self.displayedAt = displayedAt
    }
    public var url: URL? {
        guard let serverID = UUID(uuidString: server) else { return nil }
        return DeepLink.url(serverID: serverID, sessionID: sessionID ?? rootSessionID,
                            requestID: ["permission", "question", "resolved"].contains(kind) ? id : nil)
    }
}

public struct NotificationAuditEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public let server: String
    public let requestID: String
    public let action: String
    public var result: String
    public let date: Date
    public init(server: String, requestID: String, action: String, result: String, date: Date) {
        self.server = server; self.requestID = requestID; self.action = action; self.result = result; self.date = date
    }
}

public struct PushPreferences: Codable, Sendable, Equatable {
    public var lockScreenApprovals = true
    public var liveActivities = true
    /// Notification kinds the user turned off (`permission`, `question`, `finished`, `failed`). Off kinds still arrive
    /// but without sound or banner.
    public var silencedKinds: Set<String> = []
    /// Muted sessions as `server/sessionID`; a muted root session mutes its subagents.
    public var mutedSessions: Set<String> = []
    public var quietHours: QuietHours?
    public init() {}
    public init(from decoder: any Decoder) throws {
        // Every field is optional on disk: older files and newer ones with unknown fields both load.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lockScreenApprovals = try container.decodeIfPresent(Bool.self, forKey: .lockScreenApprovals) ?? true
        liveActivities = try container.decodeIfPresent(Bool.self, forKey: .liveActivities) ?? true
        silencedKinds = (try? container.decodeIfPresent(Set<String>.self, forKey: .silencedKinds)) ?? []
        mutedSessions = (try? container.decodeIfPresent(Set<String>.self, forKey: .mutedSessions)) ?? []
        quietHours = try? container.decodeIfPresent(QuietHours.self, forKey: .quietHours)
    }
    public static func muteKey(server: String, session: String) -> String { server + "/" + session }
    public func muted(server: String, sessionID: String?, rootSessionID: String?) -> Bool {
        [sessionID, rootSessionID].contains { $0.map { mutedSessions.contains(Self.muteKey(server: server, session: $0)) } ?? false }
    }
}

/// A daily window, in minutes after local midnight; `start > end` spans midnight.
public struct QuietHours: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return false }
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}

/// Each transaction holds a cross-process lock. Atomic rename protects readers from partial JSON,
/// and the lock prevents the app and NSE from losing each other's count updates or unpair cleanup.
public struct PushSnapshotStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public static func appGroup(bundle: Bundle = .main) throws -> Self {
        guard let id = bundle.object(forInfoDictionaryKey: "OCAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return .init(directory: directory.appending(path: "Push"))
    }
    #if DEBUG
    public func markNSEInvocation() throws {
        try transaction { try write(Date().timeIntervalSince1970, to: directory.appending(path: "nse-probe.json")) }
    }
    public func nseInvocation() throws -> Double? {
        try transaction { try read(directory.appending(path: "nse-probe.json")) }
    }
    public func resetUITestState() throws {
        try transaction {
            for name in ["keys", "pending", "shown", "audit.json", "preferences.json", "nse-probe.json"] {
                let file = directory.appending(path: name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            }
        }
    }
    public func clearNSEInvocation() throws {
        try transaction {
            let file = directory.appending(path: "nse-probe.json")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
    #endif
    public func register(keyID: String, server: String) throws {
        try transaction { try write(server, to: file("keys", keyID)) }
    }
    public func server(keyID: String) throws -> String? { try transaction { try read(file("keys", keyID)) } }
    @discardableResult public func setPending(_ count: Int, server: String) throws -> Int {
        try transaction { try write(max(0, count), to: file("pending", server)); return try sum() }
    }
    public func badge() throws -> Int { try transaction { try sum() } }
    /// Each server's waiting permissions and questions, as the app or the NSE last wrote them.
    public func pendingCounts() throws -> [String: Int] {
        try transaction {
            try files("pending").reduce(into: [:]) { counts, url in
                counts[url.deletingPathExtension().lastPathComponent] = max(0, (try read(url) as Int?) ?? 0)
            }
        }
    }
    public func record(_ shown: ShownNotification, pending: Int) throws -> Int {
        try transaction {
            guard try read(file("keys", shown.keyID)) as String? == shown.server else { throw CocoaError(.fileReadNoPermission) }
            try write(shown, to: file("shown", shown.id))
            try write(max(0, pending), to: file("pending", shown.server))
            try pruneUnlocked(now: shown.displayedAt)
            return try sum()
        }
    }
    public func shown(_ id: String) throws -> ShownNotification? { try transaction { try read(file("shown", id)) } }
    public func remove(server: String) throws {
        try transaction {
            for url in try files("keys") where (try read(url) as String?) == server { try FileManager.default.removeItem(at: url) }
            for url in try files("shown") where (try read(url) as ShownNotification?)?.server == server { try FileManager.default.removeItem(at: url) }
            let pending = try file("pending", server)
            if FileManager.default.fileExists(atPath: pending.path) { try FileManager.default.removeItem(at: pending) }
        }
    }
    public func prune(now: Date = .now) throws { try transaction { try pruneUnlocked(now: now) } }
    public func preferences() throws -> PushPreferences { try transaction { try read(directory.appending(path: "preferences.json")) ?? .init() } }
    public func save(preferences: PushPreferences) throws { try transaction { try write(preferences, to: directory.appending(path: "preferences.json")) } }
    public func audit() throws -> [NotificationAuditEntry] { try transaction { try read(directory.appending(path: "audit.json")) ?? [] } }
    public func append(_ entry: NotificationAuditEntry) throws {
        try transaction {
            let url = directory.appending(path: "audit.json")
            var entries: [NotificationAuditEntry] = try read(url) ?? []
            entries.removeAll { $0.id == entry.id }
            entries.insert(entry, at: 0)
            try write(Array(entries.prefix(500)), to: url)
        }
    }
    private func pruneUnlocked(now: Date) throws {
        for url in try files("shown") {
            if let shown: ShownNotification = try? read(url), shown.expiresAt > now { continue }
            try FileManager.default.removeItem(at: url)
        }
    }
    private func sum() throws -> Int {
        try files("pending").reduce(0) { total, url in
            let (sum, overflow) = total.addingReportingOverflow(max(0, (try read(url) as Int?) ?? 0))
            return overflow ? Int.max : sum
        }
    }
    private func files(_ subdirectory: String) throws -> [URL] {
        let url = directory.appending(path: subdirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
    }
    private func file(_ folder: String, _ id: String) throws -> URL {
        guard !id.isEmpty, id.utf8.count <= 256, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directory.appending(path: folder).appending(path: id + ".json")
    }
    private func read<T: Decodable>(_ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try makeDirectory(url.deletingLastPathComponent())
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(value).write(to: url, options: options)
    }
    private func makeDirectory(_ url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try makeDirectory(directory)
        let fd = Darwin.open(directory.appending(path: ".lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

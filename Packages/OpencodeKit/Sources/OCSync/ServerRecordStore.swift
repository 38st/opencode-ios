import Foundation
import OCModels
import OCPersistence

// Keep the contract outside this MainActor-default module. Xcode 27.0 misapplies
// protocol-level nonisolated to conforming actors' synthesized initializers.
public typealias ServerRecordStore = OCPersistence.ServerRecordStore

public actor JSONServerRecordStore: ServerRecordStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func applicationSupport() throws -> JSONServerRecordStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        return JSONServerRecordStore(url: directory.appending(path: "Opencode/servers.json"))
    }
    public func load() throws -> [ServerRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ServerRecord].self, from: Data(contentsOf: url))
    }
    public func save(_ records: [ServerRecord]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

public actor GRDBServerRecordStore: ServerRecordStore {
    public let writer: PersistenceWriter
    private let legacyURL: URL?
    public init(writer: PersistenceWriter, legacyURL: URL? = nil) { self.writer = writer; self.legacyURL = legacyURL }
    public func load() async throws -> [ServerRecord] { try await writer.loadServers(importing: legacyURL) }
    public func save(_ records: [ServerRecord]) async throws { try await writer.saveServers(records) }
}

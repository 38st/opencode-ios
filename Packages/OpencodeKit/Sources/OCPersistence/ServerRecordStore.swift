import OCModels

public protocol ServerRecordStore: Sendable {
    // Preserve the caller-isolation behavior originally supplied by OCSync's settings.
    nonisolated(nonsending) func load() async throws -> [ServerRecord]
    nonisolated(nonsending) func save(_ records: [ServerRecord]) async throws
}

import Foundation
import Testing
import Clocks
import OCFoundation
import OCModels
@testable import OCPersistence

private func session(_ id: String) -> SessionInfo { .init(raw: .object(["id": .string(id), "projectID": .string("p"), "title": .string(id), "time": .object(["updated": .integer(1)]), "future": .string("preserved")])) }
@Test func migrationsAndRawRoundTrip() async throws {
    let writer = try PersistenceWriter()
    let names = try await writer.tableNames()
    for name in ["server", "project", "session", "message", "transcript_window", "catalog", "draft", "outbox", "pty_cursor", "local_meta", "openapi_ops"] { #expect(names.contains(name)) }
    let info = session("s"), row = SessionMessage(raw: .object(["id": .string("m"), "type": .string("future"), "future": .integer(3)]))
    await writer.enqueue(.init(serverID: "server", sessions: [info], transcripts: [info.id: .init(messages: [row], olderCursor: "older")]))
    #expect(try await writer.load(serverID: "server").sessions.isEmpty)
    try await writer.flush()
    #expect(try await writer.load(serverID: "server").sessions == [info])
    #expect(try await writer.transcript(serverID: "server", sessionID: "s") == .init(messages: [row], olderCursor: "older"))
}
@Test func writeBehindDebouncesWithTestClock() async throws {
    let clock = TestClock<Duration>()
    let writer = try PersistenceWriter(sleep: { try await clock.sleep(for: $0) })
    await writer.enqueue(.init(serverID: "server", sessions: [session("a")]))
    await clock.advance(by: .seconds(1))
    #expect(await writer.writeCount == 0)
    await writer.enqueue(.init(serverID: "server", sessions: [session("b")]))
    await clock.advance(by: .seconds(1))
    #expect(await writer.writeCount == 0)
    await clock.advance(by: .seconds(2))
    for _ in 0..<1000 where await writer.writeCount == 0 { await Task.yield() }
    #expect(await writer.writeCount == 1)
    #expect(try await writer.load(serverID: "server").sessions.count == 2)
}
@Test func retentionUsesAccessAndByteBudget() async throws {
    let writer = try PersistenceWriter(maximumSessions: 2)
    for id in ["a", "b"] {
        await writer.enqueue(.init(serverID: "server", sessions: [session(id)], transcripts: [id: .init(messages: [])])); try await writer.flush()
    }
    _ = try await writer.transcript(serverID: "server", sessionID: "a")
    await writer.enqueue(.init(serverID: "server", sessions: [session("c")])); try await writer.flush()
    #expect(Set(try await writer.load(serverID: "server").sessions.map(\.id)) == ["a", "c"])
    let small = try PersistenceWriter(maximumBytes: 1)
    await small.enqueue(.init(serverID: "server", sessions: [session("a")])); try await small.flush()
    #expect(try await small.load(serverID: "server").sessions.isEmpty)
}
@Test func serverImportIsAtomicAndOneTime() async throws {
    let writer = try PersistenceWriter(), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    let first = ServerRecord(name: "One", endpoints: [])
    try JSONEncoder().encode([first]).write(to: url)
    #expect(try await writer.loadServers(importing: url) == [first])
    try await writer.saveServers([])
    #expect(try await writer.loadServers(importing: url).isEmpty)
}
@Test func draftsAndOutboxPreserveExactBytes() async throws {
    let writer = try PersistenceWriter(), drafts = DraftStore(writer: writer), outbox = OutboxStore(writer: writer)
    let draft = Draft(serverID: "server", sessionID: "s", text: Data("attributed archive".utf8))
    await drafts.save(draft); try await drafts.flush()
    #expect(try await drafts.load(serverID: "server", sessionID: "s") == draft)
    let entry = OutboxEntry(id: "msg", serverID: "server", sessionID: "s", body: Data("{ \"id\": \"msg\", \"text\": \"hi\" }".utf8))
    try await outbox.save(entry)
    let restored = try #require(try await outbox.entries(serverID: "server").first)
    #expect(restored.body == entry.body && restored.prelude == entry.prelude && restored.id == entry.id)
    #expect(abs(restored.createdAt.timeIntervalSince(entry.createdAt)) < 0.000001)
    try await outbox.remove(id: entry.id)
    #expect(try await outbox.entries(serverID: "server").isEmpty)
}

@Test func draftsUseTheSessionKeyBeforeAndAfterTheDebounce() async throws {
    let drafts = DraftStore(writer: try PersistenceWriter())
    let old = Draft(serverID: "server", sessionID: "s", text: Data("old".utf8))
    let latest = Draft(serverID: "server", sessionID: "s", text: Data("latest".utf8))
    await drafts.save(old); await drafts.save(latest)
    #expect(try await drafts.load(serverID: "server", sessionID: "s") == latest)
    try await drafts.flush()
    #expect(try await drafts.load(serverID: "server", sessionID: "s") == latest)
}

@Test func metadataOnlyLeavesDraftsAndOutboxIntact() async throws {
    let writer = try PersistenceWriter(metadataOnly: true)
    await writer.enqueue(.init(serverID: "server", sessions: [session("s")], transcripts: ["s": .init(messages: [.init(raw: .object(["id": .string("m"), "type": .string("user")]))])]))
    try await writer.flush()
    #expect(try await writer.load(serverID: "server").sessions.count == 1)
    #expect(try await writer.transcript(serverID: "server", sessionID: "s") == nil)
}

@Test func failedServerImportCanBeRetriedWithoutLosingExistingRecords() async throws {
    let writer = try PersistenceWriter(), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    let existing = ServerRecord(name: "Existing", endpoints: []), imported = ServerRecord(name: "Imported", endpoints: [])
    try await writer.saveServers([existing])
    try Data("[broken]".utf8).write(to: url)
    do { _ = try await writer.loadServers(importing: url); Issue.record("Expected corrupt import failure") } catch is DecodingError {}
    #expect(try await writer.loadServers() == [existing])
    try JSONEncoder().encode([imported]).write(to: url)
    #expect(try await writer.loadServers(importing: url) == [existing, imported])
}

@Test func draftsDebounceForThreeHundredMillisecondsAndFlushOnDemand() async throws {
    let clock = TestClock<Duration>(), writer = try PersistenceWriter()
    let drafts = DraftStore(writer: writer, sleep: { try await clock.sleep(for: $0) })
    let first = Draft(serverID: "server", sessionID: "s", text: Data("first".utf8))
    var latest = first; latest.text = Data("latest".utf8)
    await drafts.save(first)
    await clock.advance(by: .milliseconds(200))
    await drafts.save(latest)
    await clock.advance(by: .milliseconds(200))
    #expect(try await writer.loadDraft(serverID: "server", sessionID: "s", directory: nil) == nil)
    await clock.advance(by: .milliseconds(100))
    for _ in 0..<1000 {
        if try await writer.loadDraft(serverID: "server", sessionID: "s", directory: nil) != nil { break }
        await Task.yield()
    }
    #expect(try await writer.loadDraft(serverID: "server", sessionID: "s", directory: nil) == latest)
    latest.text = Data("background".utf8); await drafts.save(latest); try await drafts.flush()
    #expect(try await writer.loadDraft(serverID: "server", sessionID: "s", directory: nil) == latest)
}

import Foundation
import Clocks
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence
import OCSecurity
@testable import OCSync

private actor RequestLog {
    var paths: [String] = []
    func record(_ path: String) { paths.append(path) }
}
@Test @MainActor func fallbackBurstsUseOneTrailingDebounceAndFetchNewestPage() async throws {
    let time = SyncTime(), log = RequestLog(), store = ReadStore(serverID: "server", clock: time.clock)
    store.seed(info: readInfo(), messages: [])
    store.client = { readAPI { request in
        let path = request.url?.path ?? ""
        await log.record(path)
        if path == "/api/session/s" { return .object(["data": readInfo().raw]) }
        return .object(["data": .array([]), "cursor": .object([:])])
    } }
    store.apply(try readEvent("session.future", seq: 1))
    await time.test.advance(by: .milliseconds(300))
    // A known event with invalid payload takes the same recovery path.
    store.apply(try readEvent("session.renamed", seq: 2, data: ["title": .integer(42)]))
    await time.test.advance(by: .milliseconds(200))
    #expect(await log.paths.isEmpty)
    await time.test.advance(by: .milliseconds(300))
    await settle { store.refreshTasks.isEmpty }
    #expect(await log.paths.sorted() == ["/api/session/s", "/api/session/s/form", "/api/session/s/inbox", "/api/session/s/message", "/api/session/s/permission"])
    await time.test.advance(by: .seconds(2))
    #expect(await log.paths.count == 5)
    store.apply(try readEvent("session.future")) // Ephemeral unknowns do not refetch.
    await time.test.advance(by: .seconds(1))
    #expect(await log.paths.count == 5)
    await store.stop()
}

@Test @MainActor func firstDurableEventRecordsSequenceAndUnknownActiveSessionIsFetched() async throws {
    let store = ReadStore(serverID: "server")
    store.apply(try readEvent("session.created", seq: 10))
    #expect(store.sessions["s"]?.lastSeq == 10)
    store.apply(try readEvent("session.renamed", seq: 10, data: ["title": .string("duplicate")]))
    #expect(store.sessions["s"]?.info.title == nil)
    let time = SyncTime(), live = ReadStore(serverID: "server", clock: time.clock)
    live.client = { readAPI { request in
        if request.url?.path == "/api/session/new" { return .object(["data": readInfo("new").raw]) }
        return .object(["data": .array([]), "cursor": .object([:])])
    } }
    live.apply(try readEvent("session.execution.started", session: "new", seq: 20))
    #expect(live.running == ["new"])
    await time.test.advance(by: .milliseconds(500))
    await settle { live.sessions["new"] != nil }
    #expect(live.sessions["new"]?.status.isRunning == true)
    await live.stop()
}

@Test(arguments: ["shell", "compaction"]) @MainActor
func snapshotProtectsCompletionBeyondTheLastTenRows(kind: String) async throws {
    let store = ReadStore(serverID: "server")
    var raw = readRow("old", type: kind).raw
    raw.set("status", .string("running")); raw.set("shellID", .string("sh"))
    let rows = [SessionMessage(raw: raw)] + (0..<15).map { readRow("row-\($0)") }
    store.seed(info: readInfo(), messages: rows)
    store.client = { readAPI { request in
        if request.url?.path.hasSuffix("/message") == true {
            try await MainActor.run {
                if kind == "shell" {
                    store.apply(try readEvent("session.shell.ended", seq: 20, data: ["shell": .object(["id": .string("sh"), "status": .string("exited"), "exit": .integer(0)]), "output": .object(["output": .string("done")])]))
                } else {
                    store.apply(try readEvent("session.compaction.ended", seq: 20, data: ["inputID": .string("old"), "text": .string("summary"), "recent": .string("")]))
                }
            }
            return .object(["data": .array(rows.reversed().map(\.raw)), "cursor": .object([:])])
        }
        if request.url?.path == "/api/session/s" { return .object(["data": readInfo().raw]) }
        return .object(["data": .array([])])
    } }
    try await store.refreshSession("s")
    let updated = try #require(store.sessions["s"]?.transcript?.messages["old"])
    #expect(updated.fields.status == (kind == "shell" ? "exited" : "completed"))
    if kind == "shell" { #expect(updated.fields.output?.output == "done") }
    else { #expect(updated.fields.summary == "summary") }
    await store.stop()
}

@Test @MainActor func concurrentCacheOpensKeepOnlySixTranscripts() async throws {
    let cache = CacheStore(writer: try PersistenceWriter())
    await cache.save(.init(serverID: "server", sessions: (0..<12).map { readInfo(String($0)) },
                           transcripts: Dictionary(uniqueKeysWithValues: (0..<12).map { (String($0), CachedTranscript(messages: [readRow(String($0))])) })))
    try await cache.flush()
    let store = ReadStore(serverID: "server", cache: cache)
    try await store.loadCache()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<12 { group.addTask { try await store.open(String(i)) } }
        try await group.waitForAll()
    }
    #expect(store.sessions.values.filter { $0.transcript != nil }.count == 6)
    #expect(store.lru.count == 6)
    for id in store.lru { #expect(store.sessions[id]?.transcript?.order == [id]) }
    let evicted = try #require(store.sessions.keys.first { !store.lru.contains($0) })
    try await store.open(evicted)
    #expect(store.sessions[evicted]?.transcript?.order == [evicted])
    #expect(store.sessions.values.filter { $0.transcript != nil }.count == 6)
    await store.stop()
}

private actor ReadBarrier {
    var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { waiting = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
@Test @MainActor func cachedProjectsSessionsCatalogsAndTranscriptAppearBeforeNetworkAnswers() async throws {
    let cache = CacheStore(writer: try PersistenceWriter()), gate = ReadBarrier()
    let project = Project(raw: .object(["id": .string("p")]))
    await cache.save(.init(serverID: "server", projects: [project], sessions: [readInfo()], transcripts: ["s": .init(messages: [readRow("cached")])]))
    try await cache.flush()
    try await cache.writer.saveCatalog(serverID: "server", locationKey: Location(directory: "/p").key, kind: "agent", raw: .array([.object(["id": .string("build"), "name": .string("Build"), "color": .string("blue")])]))
    let store = ReadStore(serverID: "server", cache: cache)
    store.client = { readAPI { request in
        if request.url?.path == "/api/session/s" {
            await gate.wait()
            var info = readInfo().raw; info.set("title", .string("network"))
            return .object(["data": info])
        }
        if request.url?.path.hasSuffix("/message") == true {
            return .object(["data": .array([readRow("network").raw]), "cursor": .object([:])])
        }
        return .object(["data": request.url?.path == "/api/model/default" ? .null : .array([]), "location": .object(["directory": .string("/p")])])
    } }
    try await store.loadCache()
    let opening = Task { try await store.open("s") }
    await settle { await gate.waiting }
    #expect(store.projects == [project])
    #expect(store.sessions["s"]?.info.title == nil)
    #expect(store.sessions["s"]?.transcript?.order == ["cached"])
    #expect(store.catalog(for: Location(directory: "/p")).agents.value?.first?.name == "Build")
    await gate.release(); try await opening.value
    #expect(store.sessions["s"]?.info.title == "network")
    #expect(store.sessions["s"]?.transcript?.order == ["network"])
    await store.stop()
}

@Test @MainActor func pendingStatusesMatchReferenceTurnBoundaries() {
    let session = SessionModel(info: readInfo(), transcript: TranscriptModel())
    func item(_ delivery: String, created: Int64 = 2) -> InboxItem {
        .init(raw: .object(["id": .string("pending"), "type": .string("user"), "delivery": .string(delivery), "time": .object(["created": .integer(created)])]))
    }
    session.pending = [item("queue")]
    #expect(session.pendingStatus("pending") == .queued)
    session.pending = [item("steer")]
    #expect(session.pendingStatus("pending") == .starting)
    var idle = readRow("idle", type: "idle").raw; idle.set("time", .object(["created": .integer(3)]))
    session.transcript?.upsert(.init(raw: idle))
    #expect(session.pendingStatus("pending") == .stranded)
    session.status = .running(since: 4)
    #expect(session.pendingStatus("pending") == .starting)
    session.transcript?.upsert(readRow("delivered"))
    #expect(session.pendingStatus("pending") == .steering)
    session.pending = [.init(raw: .object(["id": .string("pending"), "type": .string("compaction")]))]
    #expect(session.pendingStatus("pending") == nil)
}

@Test @MainActor func jumpToStartUsesAscendingQueryWithoutCursor() async throws {
    let store = ReadStore(serverID: "server")
    store.seed(info: readInfo(), messages: [readRow("newest")])
    store.sessions["s"]?.transcript?.olderCursor = "descending-cursor"
    store.client = { readAPI { request in
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(.init(name: "order", value: "asc")))
        #expect(query.contains(.init(name: "limit", value: "50")))
        #expect(!query.contains { $0.name == "cursor" })
        return .object(["data": .array([readRow("first").raw, readRow("second").raw]), "cursor": .object(["next": .string("forward")])])
    } }
    try await store.jumpToStart("s")
    #expect(store.sessions["s"]?.transcript?.order == ["first", "second"])
    #expect(store.sessions["s"]?.transcript?.olderCursor == nil)
    #expect(store.sessions["s"]?.transcript?.isAtStart == true)
    await store.stop()
}

@Test @MainActor func transcriptBudgetIsSharedAcrossRegistryServers() async throws {
    let registry = ServerRegistry(records: MemoryRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()),
                                  pathMonitor: nil, factory: { _, _, _ in FakeConnection() })
    await registry.load()
    let first = try await registry.add(syncRecord(), credential: .password("test")), second = try await registry.add(syncRecord(), credential: .password("test"))
    for server in [first, second] {
        server.readPath.client = nil
        for i in 0..<4 {
            let id = String(i)
            server.readPath.seed(info: readInfo(id))
            try await server.readPath.open(id)
        }
    }
    #expect(first.sessions.values.filter { $0.transcript != nil }.count == 2)
    #expect(second.sessions.values.filter { $0.transcript != nil }.count == 4)
    #expect(first.sessions["0"]?.transcript == nil && first.sessions["1"]?.transcript == nil)
    try await first.readPath.open("0")
    #expect(first.sessions["2"]?.transcript == nil)
    #expect(first.sessions["0"]?.transcript != nil)
    await registry.shutdown()
}

@Test @MainActor func terminalEventsMatchProjectorOptionalFieldRules() throws {
    let store = ReadStore(serverID: "server")
    var assistant = readRow("m", type: "assistant").raw
    assistant.set("cost", .integer(3)); assistant.set("tokens", .object(["input": .integer(10)]))
    assistant.set("content", .array([.object(["type": .string("text"), "text": .string("partial"), "state": .object(["old": .bool(true)])])]))
    var compaction = readRow("c", type: "compaction").raw
    compaction.set("status", .string("running")); compaction.set("metadata", .object(["old": .bool(true), "replace": .integer(1)]))
    store.seed(info: readInfo(), messages: [.init(raw: assistant), .init(raw: compaction)])
    store.apply(try readEvent("session.step.failed", seq: 10, data: ["assistantMessageID": .string("m"), "error": .object(["type": .string("provider"), "message": .string("failed")])]))
    let message = try #require(store.sessions["s"]?.transcript?.messages["m"])
    #expect(message.fields.cost == 3 && message.fields.tokens?.input == 10)
    store.apply(try readEvent("session.text.ended", seq: 11, data: ["assistantMessageID": .string("m"), "ordinal": .integer(0), "text": .string("complete")]))
    #expect(message.items.first?.fields["state"] == nil)
    var event = try readEvent("session.compaction.ended", seq: 12, data: ["text": .string("summary"), "recent": .string("")]).raw
    event.set("metadata", .object(["new": .bool(true), "replace": .integer(2)]))
    store.apply(ServerEvent.decode(try JSONEncoder().encode(event)))
    #expect(store.sessions["s"]?.transcript?.messages["c"]?.fields.metadata == .object(["old": .bool(true), "new": .bool(true), "replace": .integer(2)]))
}

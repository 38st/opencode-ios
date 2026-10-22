import Foundation
import Testing
import Clocks
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence
@testable import OCSync

private actor AdmissionServer {
    var bodies: [Data] = []
    var admitted: [String: Data] = [:]
    var loseResponse = true
    func send(_ request: URLRequest) throws -> JSONValue {
        let body = try #require(request.httpBody)
        let raw = try JSONDecoder().decode(JSONValue.self, from: body)
        let id = try #require(raw["id"]?.stringValue)
        bodies.append(body)
        if let prior = admitted[id] { #expect(prior == body) } else { admitted[id] = body }
        if loseResponse { loseResponse = false; throw URLError(.networkConnectionLost) }
        return .object(["data": .object(["id": .string(id), "sessionID": .string("s"), "type": .string("user"), "payload": .object(["text": raw["text"] ?? .string("")])])])
    }
}

@Test func killedAfterAdmissionRelaunchUsesIdenticalIDAndBytesWithoutDuplicate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.sqlite")
    let writer = try PersistenceWriter(url: url), store = OutboxStore(writer: writer), server = AdmissionServer()
    let body = Data(#"{ "text": "survives kill", "id": "msg_same" }"#.utf8)
    try await store.save(.init(id: "msg_same", serverID: "server", sessionID: "s", body: body))
    let api = readAPI { try await server.send($0) }
    let first = OutboxProcessor(store: store, serverID: "server")
    do { try await first.drain(using: api); Issue.record("Expected lost response") } catch APIError.transport {}
    await first.stop()
    let reopened = OutboxStore(writer: try PersistenceWriter(url: url))
    let second = OutboxProcessor(store: reopened, serverID: "server")
    try await second.prepareLaunch(); try await second.drain(using: api)
    #expect(await server.bodies == [body, body])
    #expect(await server.admitted.count == 1)
    #expect(try await reopened.entries(serverID: "server").isEmpty)
}

private actor WriteTrace {
    var paths: [String] = []
    var failed = false
    func respond(_ request: URLRequest) throws -> JSONValue {
        let path = request.url?.path ?? ""
        let raw = try request.httpBody.map { try JSONDecoder().decode(JSONValue.self, from: $0) } ?? .object([:])
        paths.append(path + ":" + (raw["id"]?.stringValue ?? ""))
        if raw["id"]?.stringValue == "a", !failed { failed = true; throw URLError(.timedOut) }
        if raw["id"]?.stringValue == "conflict" { throw APIError.server(tag: "ConflictError", status: 409, body: .object([:])) }
        if request.httpMethod == "GET" { return .object(["data": .object(["id": .string("s"), "agent": .string("build"), "model": .object(["providerID": .string("p"), "id": .string("m")]), "revert": .object(["messageID": .string("old")])])]) }
        return .object(["data": .object(["id": raw["id"] ?? .string(""), "sessionID": .string("s"), "type": .string("user")])])
    }
}
@Test func transportFailureBlocksOnlyItsSessionAnd409RequiresEditing() async throws {
    let store = OutboxStore(writer: try PersistenceWriter()), trace = WriteTrace()
    for (id, session) in [("a", "s"), ("b", "s"), ("other", "t"), ("conflict", "t"), ("after", "t")] {
        try await store.save(.init(id: id, serverID: "server", sessionID: session, body: JSONEncoder().encode(["id": id, "text": id])))
    }
    let processor = OutboxProcessor(store: store, serverID: "server"), api = readAPI { try await trace.respond($0) }
    do { try await processor.drain(using: api) } catch APIError.transport {}
    #expect(await trace.paths == ["/api/session/s/prompt:a", "/api/session/t/prompt:other", "/api/session/t/prompt:conflict", "/api/session/t/prompt:after"])
    try await processor.drain(using: api)
    #expect(await trace.paths.suffix(2) == ["/api/session/s/prompt:a", "/api/session/s/prompt:b"])
    let entries = try await store.entries(serverID: "server")
    #expect(entries.map(\.id) == ["conflict"] && entries.first?.state == "failed")
}
@Test func preludeSkipsUnchangedSelectionsAndCommitsBeforePrompt() async throws {
    let store = OutboxStore(writer: try PersistenceWriter()), trace = WriteTrace()
    let prelude = WritePrelude(agent: "build", model: .init(raw: .object(["providerID": .string("p"), "id": .string("m")])), commitRevert: true)
    try await store.save(.init(id: "prompt", serverID: "server", sessionID: "s", prelude: JSONEncoder().encode(prelude), body: Data(#"{"id":"prompt","text":"next"}"#.utf8)))
    try await OutboxProcessor(store: store, serverID: "server").drain(using: readAPI { try await trace.respond($0) })
    #expect(await trace.paths == ["/api/session/s:", "/api/session/s/revert/commit:", "/api/session/s/model:", "/api/session/s/prompt:prompt"])
}
@Test func immutableAdmissionAndEchoCannotBeResurrectedByFailedUpdate() async throws {
    let store = OutboxStore(writer: try PersistenceWriter())
    let entry = OutboxEntry(id: "id", serverID: "server", sessionID: "s", body: Data(#"{"id":"id"}"#.utf8))
    try await store.save(entry)
    var changed = entry; changed.body = Data(#"{"id":"id","text":"changed"}"#.utf8)
    await #expect(throws: OutboxError.self) { try await store.save(changed) }
    try await store.remove(id: entry.id)
    try await store.update(id: entry.id, state: "failed", attempts: 2)
    #expect(try await store.entries(serverID: "server").isEmpty)
}
@Test @MainActor func optimisticRowIsReplacedByEchoBeforeLostHTTPResponse() async throws {
    let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer))
    store.seed(info: readInfo(), messages: [])
    let id = try await store.sendPrompt("s", input: .init(text: "local"))
    #expect(store.sessions["s"]?.transcript?.messages[id]?.acknowledged == false)
    store.client = {
        readAPI { _ in
            let event = try readEvent("session.inbox.enqueued", data: ["inboxID": .string(id), "item": .object(["type": .string("user"), "delivery": .string("steer"), "payload": .object(["text": .string("server")])])], created: 20)
            await MainActor.run { store.apply(event) }
            throw URLError(.networkConnectionLost)
        }
    }
    await store.flushWrites()
    for _ in 0..<100 { if try await OutboxStore(writer: writer).entries(serverID: "server").isEmpty { break }; await Task.yield() }
    #expect(store.sessions["s"]?.transcript?.order == [id])
    #expect(store.sessions["s"]?.transcript?.messages[id]?.fields.text == "server")
    #expect(store.sessions["s"]?.transcript?.messages[id]?.fields.time.created == 20)
    #expect(store.sessions["s"]?.transcript?.messages[id]?.acknowledged == true)
    #expect(try await OutboxStore(writer: writer).entries(serverID: "server").isEmpty)
    await store.stop()
}
@Test @MainActor func reconnectDrainsSavedPromptAndTenMinuteRuleNeedsExplicitConfirmation() async throws {
    let now = Date(), writer = try PersistenceWriter(), outbox = OutboxStore(writer: writer)
    try await outbox.save(.init(id: "old", serverID: "server", sessionID: "s", body: Data(#"{"id":"old","text":"old"}"#.utf8), createdAt: now.addingTimeInterval(-601)))
    await writer.enqueue(.init(serverID: "server", sessions: [readInfo()]))
    try await writer.flush()
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer))
    try await store.loadCache()
    #expect(store.outboxEntries["old"]?.needsLaunchConfirmation == true)
    let server = AdmissionServer()
    store.client = { readAPI { try await server.send($0) } }
    await store.flushWrites()
    #expect(await server.bodies.isEmpty)
    try await store.confirmOutbox("old")
    await store.flushWrites() // first response is lost
    #expect(store.outboxEntries["old"] != nil)
    store.setWritesConnected(true)
    for _ in 0..<1000 { if store.outboxEntries.isEmpty { break }; await Task.yield() }
    #expect(store.outboxEntries.isEmpty)
    #expect(await server.admitted.count == 1)
    await store.stop()
}
@Test @MainActor func optimisticCreateGatesPromptsAndRecoversAcknowledgedCreate() async throws {
    let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer)), trace = WriteTrace()
    let id = try await store.createSession(location: .init(directory: "/p"))
    #expect(id.hasPrefix("ses_")); #expect(store.sessions[id] != nil)
    let prompt = try await store.sendPrompt(id, input: .init(text: "first"))
    #expect(prompt.hasPrefix("msg_"))
    store.client = { readAPI { request in
        if request.url?.path == "/api/session" {
            let event = try readEvent("session.created", session: id, data: ["location": .object(["directory": .string("/p")])])
            await MainActor.run { store.apply(event) }
            return .object(["data": .object(["id": .string(id), "location": .object(["directory": .string("/p")])])])
        }
        return try await trace.respond(request)
    } }
    await store.flushWrites()
    #expect(store.sessions[id] != nil)
    #expect(await trace.paths.contains("/api/session/\(id)/prompt:\(prompt)"))
    #expect(store.outboxEntries.isEmpty)
    await store.stop()
}

@Test @MainActor func transportRetriesWhileConnectedUsingTheSameAdmission() async throws {
    let clock = TestClock<Duration>(), writer = try PersistenceWriter(), server = AdmissionServer()
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), clock: .init(sleep: { try await clock.sleep(for: $0) }))
    store.seed(info: readInfo(), messages: [])
    store.client = { readAPI { try await server.send($0) } }
    store.setWritesConnected(true)
    let id = try await store.sendPrompt("s", input: .init(text: "Retry while connected"))
    for _ in 0..<1000 { if await server.bodies.count == 1 { break }; await Task.yield() }
    #expect(await server.bodies.count == 1)
    for _ in 0..<20 {
        await clock.advance(by: .seconds(1))
        for _ in 0..<30 { await Task.yield() }
        if store.outboxEntries[id] == nil { break }
    }
    #expect(store.outboxEntries[id] == nil)
    let bodies = await server.bodies
    #expect(bodies.count == 2 && bodies.first == bodies.last)
    await store.stop()
}

@Test @MainActor func coalescedCompactionConsumedBeforeResponseRetractsSpeculativeRow() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    store.seed(info: readInfo(), messages: [])
    let id = try await store.compact("s")
    #expect(store.sessions["s"]?.pending.map(\.id) == [id])
    store.consumedInputs.insert("canonical")
    store.acknowledgeResponse(id, result: .prompt(.init(raw: .object(["id": .string("canonical"), "sessionID": .string("s"), "type": .string("compaction")]))))
    #expect(store.sessions["s"]?.pending.isEmpty == true)
    #expect(store.outboxEntries[id] == nil)
    await store.stop()
}

@Test func changedRevertIsNeverCommittedByARetry() async throws {
    let store = OutboxStore(writer: try PersistenceWriter()), trace = WriteTrace()
    let prelude = Data(#"{"commitRevert":true,"revertMessageID":"confirmed-boundary"}"#.utf8)
    try await store.save(.init(id: "next", serverID: "server", sessionID: "s", prelude: prelude, body: Data(#"{"id":"next","text":"next"}"#.utf8)))
    try await OutboxProcessor(store: store, serverID: "server").drain(using: readAPI { try await trace.respond($0) })
    #expect(await trace.paths == ["/api/session/s:"])
    #expect(try await store.entries(serverID: "server").first?.state == "failed")
}

@Test @MainActor func inboxMutationsSurviveSnapshotsTakenBeforeTheReply() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    let item = InboxItem(raw: .object(["id": .string("queued"), "sessionID": .string("s"), "type": .string("user"),
                                      "delivery": .string("queue"), "payload": .object(["text": .string("Recover this prompt")])]))
    store.seed(info: readInfo(), messages: [], pending: [item])
    store.client = { readAPI { request in
        await MainActor.run {
            store.applyInbox([item], id: "s", overlay: FetchOverlay())
            if request.httpMethod == "PATCH" { #expect(store.sessions["s"]?.pending.first?.raw["delivery"] == .string("steer")) }
            else { #expect(store.sessions["s"]?.pending.isEmpty == true) }
        }
        return .object([:])
    } }
    try await store.changeDelivery("s", itemID: "queued", delivery: .steer)
    try await store.cancelPending("s", itemID: "queued")
    store.applyInbox([item], id: "s", overlay: FetchOverlay())
    #expect(store.sessions["s"]?.pending.isEmpty == true)
    #expect(store.sessions["s"]?.transcript?.messages["queued"] == nil)
    #expect(try await store.drafts?.load(serverID: "server", sessionID: "s")?.attributedText == AttributedString("Recover this prompt"))
    await store.stop()
}

@Test func staleAdmissionBlocksNewerPromptsUntilTheUserDecides() async throws {
    let store = OutboxStore(writer: try PersistenceWriter()), trace = WriteTrace()
    try await store.save(.init(id: "old", serverID: "server", sessionID: "s", body: Data(#"{"id":"old"}"#.utf8), createdAt: Date().addingTimeInterval(-601)))
    try await store.save(.init(id: "new", serverID: "server", sessionID: "s", body: Data(#"{"id":"new"}"#.utf8)))
    let processor = OutboxProcessor(store: store, serverID: "server"), api = readAPI { try await trace.respond($0) }
    try await processor.prepareLaunch()
    try await processor.drain(using: api)
    #expect(await trace.paths.isEmpty)
    try await store.update(id: "old", state: "pending")
    try await processor.drain(using: api)
    #expect(await trace.paths == ["/api/session/s/prompt:old", "/api/session/s/prompt:new"])
}

@Test @MainActor func deliveryEchoSurvivesALostHTTPResponse() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    let item = InboxItem(raw: .object(["id": .string("queued"), "type": .string("user"), "delivery": .string("queue")]))
    store.seed(info: readInfo(), messages: [], pending: [item])
    store.client = { readAPI { _ in
        let event = try readEvent("session.inbox.delivery.changed", data: ["inboxID": .string("queued"), "delivery": .string("steer")])
        await MainActor.run { store.apply(event) }
        throw URLError(.networkConnectionLost)
    } }
    do { try await store.changeDelivery("s", itemID: "queued", delivery: .steer); Issue.record("Expected lost response") }
    catch APIError.transport {}
    #expect(store.sessions["s"]?.pending.first?.delivery == .steer)
    await store.stop()
}

@Test @MainActor func editAndResendDoesNotReuseConsentForADifferentRevert() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    var info = readInfo(); info["revert"] = .object(["messageID": .string("confirmed")])
    store.seed(info: info, messages: [])
    let id = try await store.sendPrompt("s", input: .init(text: "next"), prelude: .init(commitRevert: true))
    store.outboxEntries[id]?.state = "failed"
    store.sessions["s"]?.info["revert"] = .object(["messageID": .string("changed")])
    await #expect(throws: WriteStoreError.self) { try await store.editSavedPrompt(id, text: "edited") }
    #expect(store.outboxEntries.count == 1)
    await store.stop()
}

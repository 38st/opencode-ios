import Foundation
import Testing
import Observation
import Synchronization
import OCFoundation
import OCModels
import OCPersistence
import OCNetworking
@testable import OCSync

private actor PreludeOrder {
    var paths: [String] = []
    func respond(_ request: URLRequest) -> JSONValue {
        paths.append(request.url?.path ?? "")
        if request.httpMethod == "GET" { return .object(["data": .object(["id": .string("s"), "agent": .string("build"), "revert": .object(["messageID": .string("old")])])]) }
        return .object(["data": .object(["id": .string("prompt"), "sessionID": .string("s"), "type": .string("user")])])
    }
}
@Test func agentThenRevertThenModelThenAdmission() async throws {
    let trace = PreludeOrder(), store = OutboxStore(writer: try PersistenceWriter())
    let prelude = WritePrelude(agent: "review", model: .init(raw: .object(["id": .string("m"), "providerID": .string("p")])), commitRevert: true)
    try await store.save(.init(id: "prompt", serverID: "server", sessionID: "s", prelude: JSONEncoder().encode(prelude), body: Data(#"{"id":"prompt","text":"next"}"#.utf8)))
    try await OutboxProcessor(store: store, serverID: "server").drain(using: readAPI { await trace.respond($0) })
    #expect(await trace.paths == ["/api/session/s", "/api/session/s/agent", "/api/session/s/revert/commit", "/api/session/s/model", "/api/session/s/prompt"])
}

@Test @MainActor func cancellationCanRestoreOrRemoveWithoutChangingDraft() async throws {
    let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), client: { readAPI { _ in .object([:]) } })
    let item = InboxItem(raw: .object(["id": .string("q"), "sessionID": .string("s"), "type": .string("user"), "delivery": .string("queue"), "payload": .object(["text": .string("queued")])]))
    store.seed(info: readInfo(), messages: [], pending: [item])
    try await store.cancelPending("s", itemID: "q", restore: false)
    #expect(try await store.drafts?.load(serverID: "server", sessionID: "s") == nil)
    store.seed(info: readInfo(), messages: [], pending: [item])
    let draft = try Draft(serverID: "server", sessionID: "s", attributedText: AttributedString("existing"))
    await store.drafts?.save(draft)
    try await store.cancelPending("s", itemID: "q")
    #expect(try await store.drafts?.load(serverID: "server", sessionID: "s")?.attributedText == AttributedString("existing\n\nqueued"))
    await store.stop()
}

@Test @MainActor func droppedItemsKeepTheComposerLimitsAndErrors() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try PersistenceWriter(), drafts = DraftStore(writer: writer, filesRoot: root)
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), drafts: drafts)
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/project")
    await composer.load()
    // A dropped file is attached through the same path as one picked in Add files, with the same limit.
    await composer.addAttachment(Data(repeating: 0x61, count: AttachmentProcessing.maximumBytes + 1), mime: "text/plain", name: "large.txt")
    #expect(composer.attachments.isEmpty)
    #expect(composer.error == AttachmentError.tooLarge.localizedDescription)
    composer.error = nil
    composer.refuseDrop()
    #expect(composer.attachments.isEmpty)
    #expect(composer.error == AttachmentError.unsupported.localizedDescription)
    await composer.addAttachment(Data("fits".utf8), mime: "text/plain", name: "small.txt")
    #expect(composer.attachments.map(\.name) == ["small.txt"])
}

@Test @MainActor func composerDeletesDraftOnlyAfterDurableAdmissionAndKeepsItOnFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try PersistenceWriter(), drafts = DraftStore(writer: writer, filesRoot: root)
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), drafts: drafts)
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/project")
    await composer.load(); composer.setText(AttributedString("durable"))
    await composer.addAttachment(Data("file".utf8), mime: "text/plain", name: "file.txt")
    try await composer.flush()
    let originalID = composer.draftID
    store.sessions.removeValue(forKey: "s")
    composer.submit(preference: .steer)
    while composer.busy { await Task.yield() }
    #expect(try await drafts.load(serverID: "server", sessionID: "s") != nil)
    #expect(String(composer.text.characters) == "durable")
    store.seed(info: readInfo(), messages: [])
    composer.submit(preference: .steer)
    while composer.busy { await Task.yield() }
    let entries = try await OutboxStore(writer: writer).entries(serverID: "server")
    #expect(entries.count == 1)
    let input = try JSONDecoder().decode(PromptInput.self, from: #require(entries.first?.body))
    #expect(input.text == "durable" && input.files?.count == 1)
    #expect(composer.blank)
    #expect(try await drafts.load(serverID: "server", sessionID: "s") == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(originalID).path))
    await store.stop()
}

@Test @MainActor func shellModeAndStagedRevertConfirmationKeepDraft() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    var info = readInfo(); info["revert"] = .object(["messageID": .string("old")])
    store.seed(info: info, messages: [])
    let composer = store.composer(sessionID: "s", directory: "/p")
    await composer.load(); composer.setText(AttributedString("!"))
    #expect(composer.options.shell && composer.text.characters.isEmpty)
    composer.shellMode(false); composer.setText(AttributedString("next"))
    composer.submit(preference: .steer)
    #expect(composer.confirmRevert && !composer.busy && !composer.blank)
    #expect(store.outboxEntries.isEmpty)
    await store.stop()
}

@Test @MainActor func confirmedSelectionFollowsSubsequentServerChanges() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/project")
    await composer.load()
    let model = ModelRef(raw: .object(["id": .string("m"), "providerID": .string("p")]))
    composer.selectAgent("reviewer"); composer.selectModel(model)
    #expect(composer.pendingSelection)
    store.sessions["s"]?.info["agent"] = .string("reviewer")
    store.sessions["s"]?.info["model"] = model.raw
    composer.reconcileSelection()
    #expect(!composer.pendingSelection)
    store.sessions["s"]?.info["agent"] = .string("build")
    store.sessions["s"]?.info["model"] = .object(["id": .string("next"), "providerID": .string("p")])
    #expect(composer.effectiveAgent == "build" && composer.effectiveModel?.id == "next")
    await store.stop()
}

@Test @MainActor func deleteCompletesAfterItsPresentingTaskIsCancelled() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()), client: {
        readAPI { _ in try await Task.sleep(for: .milliseconds(20)); return .object([:]) }
    })
    store.seed(info: readInfo(), messages: [])
    var completed = false
    let presenter = Task {
        store.deleteSession("s") { result in
            if case .failure = result { Issue.record("The store-owned delete was cancelled with its presenter") }
            completed = true
        }
        try? await Task.sleep(for: .seconds(60))
    }
    while store.sessions["s"] != nil { await Task.yield() }
    presenter.cancel()
    while !completed { await Task.yield() }
    #expect(store.sessions["s"] == nil)
    await store.stop()
}

@Test @MainActor func undoPendingPersistsReplacementBeforeCancellation() async throws {
    let writer = try PersistenceWriter(), drafts = DraftStore(writer: writer)
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), drafts: drafts, client: {
        readAPI { request in
            if request.httpMethod == "DELETE" {
                let recovered = try await drafts.load(serverID: "server", sessionID: "s")
                #expect(try recovered?.attributedText == AttributedString("pending input"))
            }
            return .object([:])
        }
    })
    let payload: JSONValue = .object(["id": .string("p"), "type": .string("user"), "text": .string("pending input")])
    store.seed(info: readInfo(), messages: [.init(raw: payload)], pending: [.init(raw: .object(["id": .string("p"), "type": .string("user"), "delivery": .string("steer"), "payload": payload]))])
    try await store.undo("s")
    #expect(store.sessions["s"]?.pending.isEmpty == true)
    await store.stop()
}

@Test @MainActor func queueUndoCompletesAfterItsLastRowDisappears() async throws {
    let writer = try PersistenceWriter(), drafts = DraftStore(writer: writer)
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), drafts: drafts, client: {
        readAPI { _ in try await Task.sleep(for: .milliseconds(20)); return .object([:]) }
    })
    let item = InboxItem(raw: .object(["id": .string("pending"), "type": .string("user"), "delivery": .string("queue"),
                                     "payload": .object(["text": .string("Restore this prompt")])]))
    store.seed(info: readInfo(), messages: [], pending: [item])
    var completed = false
    let presenter = Task {
        store.performWrite({ try await store.cancelPending("s", itemID: "pending") }) { result in
            if case .failure = result { Issue.record("Queue Undo was cancelled with its disappearing panel") }
            completed = true
        }
        try? await Task.sleep(for: .seconds(60))
    }
    while store.sessions["s"]?.pending.isEmpty != true { await Task.yield() }
    presenter.cancel()
    while !completed { await Task.yield() }
    #expect(store.sessions["s"]?.pending.isEmpty == true)
    #expect(try await drafts.load(serverID: "server", sessionID: "s")?.attributedText == AttributedString("Restore this prompt"))
    await store.stop()
}

private actor RevertTrace {
    var requests: [(String, JSONValue)] = []
    func respond(_ request: URLRequest) throws -> JSONValue {
        let path = request.url?.path ?? ""
        let body = try request.httpBody.map { try JSONDecoder().decode(JSONValue.self, from: $0) } ?? .object([:])
        var recorded = body
        if let resume = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "resume" })?.value { recorded.set("resume", .bool(resume == "true")) }
        requests.append((path, recorded))
        if path.hasSuffix("/revert/stage") { return .object(["data": .object(["messageID": body["messageID"] ?? .null])]) }
        if path.hasSuffix("/fork") { return .object(["data": .object(["id": .string("fork"), "title": .string("Fork")])]) }
        return .object(["interrupted": .bool(true)])
    }
}
@Test @MainActor func repeatedUndoMovesBoundaryAndRedoKeepsComposer() async throws {
    let trace = RevertTrace(), store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()), client: { readAPI { try await trace.respond($0) } })
    let messages = ["first", "second"].enumerated().map { index, text in
        SessionMessage(raw: .object(["id": .string("m\(index)"), "type": .string("user"), "text": .string(text)]))
    }
    let queued = InboxItem(raw: .object(["id": .string("q"), "type": .string("user"), "delivery": .string("queue"), "payload": .object(["text": .string("pending")])]))
    store.seed(info: readInfo(), messages: messages, pending: [queued])
    let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
    composer.setText(AttributedString("unsaved typing"))
    let undo = Task { try await store.undo("s") }
    while store.replacingDraftSessionID == nil { await Task.yield() }
    #expect(await trace.requests.isEmpty)
    store.resolveDraftReplacement(true)
    try await undo.value
    #expect(store.sessions["s"]?.info.revert?.messageID == "m1")
    #expect(String(composer.text.characters) == "second")
    try await store.undo("s")
    #expect(store.sessions["s"]?.info.revert?.messageID == "m0")
    #expect(String(composer.text.characters) == "first")
    try await store.redo("s")
    #expect(store.sessions["s"]?.info.revert == nil && String(composer.text.characters) == "first")
    #expect(store.sessions["s"]?.pending.map(\.id) == ["q"])
    #expect(await trace.requests.prefix(3).map(\.0) == ["/api/session/s/interrupt", "/api/experimental/session/s/wait", "/api/session/s/revert/stage"])
    #expect(await trace.requests.first?.1["resume"]?.boolValue == false)
    let fork = try await store.forkFromMessage("s", messageID: "m1")
    #expect(try await store.drafts?.load(serverID: "server", sessionID: fork.id)?.attributedText == AttributedString("second"))
    await store.stop()
}

@Test @MainActor func failedCreateRestoresDirectoryDraftAcrossLaunch() async throws {
    let writer = try PersistenceWriter(), box = OutboxStore(writer: writer)
    let create = OutboxEntry(id: "new", serverID: "server", sessionID: "new", body: Data(#"{"id":"new","location":{"directory":"/project"}}"#.utf8), state: "failed", operation: "create")
    try await box.save(create)
    let input = ComposerInput.encode(AttributedString("First prompt"), directory: "/project",
        files: [.init(uri: "data:text/plain;base64,SGVsbG8=", name: "note.txt")], agent: "build", model: nil)
    let originalBytes = try input.body(id: "prompt")
    try await box.save(.init(id: "prompt", serverID: "server", sessionID: "new", body: originalBytes, state: "failed"))
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer))
    try await store.loadCache()
    let draft = try #require(try await store.drafts?.load(serverID: "server", directory: "/project"))
    #expect(try draft.attributedText == AttributedString("First prompt"))
    #expect(try draft.attachmentFiles.count == 1 && draft.options.recoveringCreateID == "new")
    #expect(store.failedCreationDirectories["new"] == "/project")
    #expect(try await box.entries(serverID: "server").first { $0.id == "prompt" }?.body == originalBytes)
    await store.stop()
}

@Test @MainActor func renameEmptyTitleAndDeleteFamilyUseExistingStorePath() async throws {
    let trace = RevertTrace(), store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()), client: { readAPI { try await trace.respond($0) } })
    store.seed(info: readInfo(), messages: [])
    var child = readInfo("child"); child["parentID"] = .string("s")
    store.seed(info: child, messages: [])
    try await store.renameSession("s", title: "")
    #expect(store.sessions["s"]?.info.title == "")
    #expect(await trace.requests.first?.1["title"]?.stringValue == "")
    try await store.deleteSession("s")
    #expect(store.sessions["s"] == nil && store.sessions["child"] == nil)
    #expect(await trace.requests.map(\.0) == ["/api/session/s", "/api/session/s"])
    await store.stop()
}
@Test @MainActor func typingDoesNotInvalidateTheTimelineObservationGraph() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
    let invalidated = Mutex(false)
    withObservationTracking {
        _ = store.sessions["s"]?.transcript?.snapshot
        _ = store.sessions["s"]?.pending
        _ = store.sessions["s"]?.info
    } onChange: { invalidated.withLock { $0 = true } }
    for i in 1...100 { composer.setText(AttributedString(String(repeating: "字", count: i))) }
    #expect(!invalidated.withLock { $0 })
    await store.stop()
}

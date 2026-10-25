import Foundation
import Testing
import Clocks
import OCFoundation
import OCModels
import OCPersistence
import OCNetworking
@testable import OCSync

private actor ReviewRequests {
    var paths: [String] = []
    func respond(_ request: URLRequest) -> JSONValue {
        paths.append(request.url?.path ?? "")
        return .object(["interrupted": .bool(true)])
    }
}

@Test @MainActor func replacementCancelPreservesDraftAndDoesNotCallServer() async throws {
    let trace = ReviewRequests()
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()), client: { readAPI { await trace.respond($0) } })
    store.seed(info: readInfo(), messages: [.init(raw: .object(["id": .string("sent"), "type": .string("user"), "text": .string("Previous prompt")]))])
    store.sessions["s"]?.status = .running(since: 1)
    let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
    composer.setText(AttributedString("My draft"))
    await composer.addAttachment(Data("Keep me".utf8), mime: "text/plain", name: "draft.txt")
    try await composer.flush()
    let draft = try await store.drafts?.load(serverID: "server", sessionID: "s")
    let undo = Task { try await store.undo("s") }
    while store.replacingDraftSessionID == nil { await Task.yield() }
    #expect(await trace.paths.isEmpty)
    store.resolveDraftReplacement(false)
    await #expect(throws: CancellationError.self) { try await undo.value }
    #expect(await trace.paths.isEmpty)
    #expect(store.sessions["s"]?.status.isRunning == true && store.sessions["s"]?.info.revert == nil)
    #expect(try await store.drafts?.load(serverID: "server", sessionID: "s") == draft)
    #expect(String(composer.text.characters) == "My draft" && composer.attachments.count == 1)
    await store.stop()
}

@Test @MainActor func replacingAnEditedRestoreAndFailedPromptRequiresConfirmation() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
    let prompt = MessageFields(raw: .object(["text": .string("Restored")]))
    try await store.restoreInput(prompt, sessionID: "s", append: false)
    // An unchanged restore can be replaced, including by repeated Undo.
    try await store.restoreInput(prompt, sessionID: "s", append: false)
    composer.setText(AttributedString("Changed")); composer.setText(AttributedString("Restored"))
    let id = try await store.sendPrompt("s", input: .init(text: "Failed input"))
    store.outboxEntries[id]?.state = "failed"
    let cancelled = Task { try await store.restoreFailedPrompt(id) }
    while store.replacingDraftSessionID == nil { await Task.yield() }
    store.resolveDraftReplacement(false)
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(String(composer.text.characters) == "Restored" && composer.options.editingOutboxID == nil)
    let accepted = Task { try await store.restoreFailedPrompt(id) }
    while store.replacingDraftSessionID == nil { await Task.yield() }
    store.resolveDraftReplacement(true); try await accepted.value
    #expect(String(composer.text.characters) == "Failed input" && composer.options.editingOutboxID == id)
    composer.setText(AttributedString("Typed after restore"))
    let stopped = Task { try await store.restoreFailedPrompt(id) }
    while store.replacingDraftSessionID == nil { await Task.yield() }
    await store.stop()
    await #expect(throws: CancellationError.self) { try await stopped.value }
}

@Test @MainActor func directoryDraftFollowsSelectionAndConflictNeverOverwritesWithoutChoice() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try PersistenceWriter(), drafts = DraftStore(writer: writer, filesRoot: root)
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), drafts: drafts)
    let source = store.composer(directory: "/first"); await source.load()
    var text = AttributedString("Review @file.swift")
    let range = try #require(text.range(of: "@file.swift"))
    text[range][MentionAttribute.self] = .init(kind: "file", value: "Sources/file.swift")
    source.setText(text)
    source.setOptions(.init(shell: true, agent: "reviewer", model: .init(raw: .object(["id": .string("vision"), "providerID": .string("mock"), "variant": .string("careful")]))))
    await source.addAttachment(Data("Attachment bytes".utf8), mime: "text/plain", name: "note.txt")
    let oldID = source.draftID, choices = source.options
    try await store.moveDirectoryDraft(from: "/first", to: "/second")
    #expect(source.blank)
    #expect(try await drafts.load(serverID: "server", directory: "/first") == nil)
    // Simulate a relaunch with a new store over the persisted database/files.
    let relaunched = DraftStore(writer: writer, filesRoot: root)
    let moved = try #require(try await relaunched.load(serverID: "server", directory: "/second"))
    #expect(moved.id == oldID && moved.options == choices)
    #expect(try moved.attributedText.runs.last?[MentionAttribute.self]?.value == "/first/Sources/file.swift")
    #expect(try await relaunched.promptFiles(moved).first?.uri == "data:text/plain;base64,QXR0YWNobWVudCBieXRlcw==")
    let destination = store.composer(directory: "/third"); await destination.load(); destination.setText(AttributedString("Saved draft"))
    await #expect(throws: ComposerError.directoryDraftConflict) { try await store.moveDirectoryDraft(from: "/second", to: "/third") }
    #expect(String(destination.text.characters) == "Saved draft")
    #expect(!store.composer(directory: "/second").blank)
    try await store.moveDirectoryDraft(from: "/second", to: "/third", keeping: .saved)
    #expect(String(destination.text.characters) == "Saved draft" && !store.composer(directory: "/second").blank)
    try await store.moveDirectoryDraft(from: "/second", to: "/third", keeping: .current)
    #expect(String(destination.text.characters) == "Review @file.swift" && destination.attachments.count == 1)
    #expect(destination.options == choices)
    #expect(try await drafts.load(serverID: "server", directory: "/second") == nil)
    await store.stop()
}

@Test @MainActor func delayedInterruptOnlyTargetsTheOriginalExecution() async throws {
    for outcome in ["same", "later", "gap"] {
        let sameRun = outcome == "same"
        let time = SyncTime(), trace = ReviewRequests()
        let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()), clock: time.clock,
                              client: { readAPI { await trace.respond($0) } })
        store.seed(info: readInfo(), messages: [])
        let session = try #require(store.sessions["s"])
        session.status = .running(since: 1)
        let original = session.executionID
        let id = try await store.sendPrompt("s", input: .init(text: "Interrupt and send"))
        store.interruptAfterAdmission(id, sessionID: "s", executionID: original)
        for _ in 0..<30 { await Task.yield() }
        // A retry is the same execution; an idle boundary then a run is not.
        if outcome == "later" { session.status = .idle; session.status = .running(since: 2) }
        if outcome == "gap" { store.setWritesConnected(false) }
        session.status = .retrying(attempt: 2, at: 3)
        #expect((session.executionID == original) == sameRun)
        store.outboxEntries.removeValue(forKey: id); store.admittedInputs.insert(id)
        for _ in 0..<20 {
            await time.test.advance(by: .seconds(1))
            for _ in 0..<20 { await Task.yield() }
        }
        #expect(await trace.paths.filter { $0.hasSuffix("/interrupt") }.count == (sameRun ? 1 : 0))
        await store.stop()
    }
}

@Test @MainActor func composerOutlivesItsServerAndClearsTransientSearchError() async throws {
    var store: ReadStore? = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    let composer = try #require(store?.composer(directory: "/p")); await composer.load()
    composer.error = "Could not search files."; composer.setText(AttributedString("Draft"))
    #expect(composer.error == nil)
    composer.error = "Could not search files."; composer.clearSearchError(); #expect(composer.error == nil)
    await store?.stop(); store = nil
    composer.submit(preference: .steer)
    #expect(composer.error == ComposerError.storeUnavailable.errorDescription)
    #expect(String(composer.text.characters) == "Draft")
}

@Test func writeErrorsHaveActionableMessagesAndPreserveServerMessages() {
    #expect(WriteErrorMessage.message(WriteStoreError.sessionUnavailable).contains("draft has been kept"))
    #expect(WriteErrorMessage.message(WriteStoreError.persistenceUnavailable).contains("saved on this device"))
    #expect(WriteErrorMessage.message(APIError.transport(URLError(.networkConnectionLost))).contains("Check your connection"))
    #expect(WriteErrorMessage.message(APIError.server(tag: "Conflict", status: 409, body: .object([:]))) == "This input conflicts with an existing request. Edit it and send again.")
    #expect(WriteErrorMessage.message(APIError.server(tag: "Failure", status: 400, body: .object(["message": .string("Model cannot accept images")]))) == "Model cannot accept images")
    #expect(WriteErrorMessage.message(APIError.server(tag: "Failure", status: 500, body: .object(["error": .object(["message": .string("Disk is full")])]))) == "Disk is full")
    #expect(WriteErrorMessage.message(DraftError.attachmentTooLarge).contains("20 MiB"))
    #expect(WriteErrorMessage.message(ComposerError.shellRestore) == "Leave shell mode before undoing a queued prompt")
    #expect(WriteErrorMessage.isCancellation(APIError.cancelled))
    #expect(!WriteErrorMessage.message(NSError(domain: "unknown", code: 1)).contains("error 1"))
}

@Test @MainActor func restoredFailedPromptCanBeDiscardedThenSent() async throws {
    let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer))
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
    let id = try await store.sendPrompt("s", input: .init(text: "Failed prompt"))
    store.outboxEntries[id]?.state = "failed"
    try await store.restoreFailedPrompt(id)
    #expect(composer.options.editingOutboxID == id)
    try await store.discardOutbox(id)
    #expect(composer.options.editingOutboxID == nil)
    #expect(String(composer.text.characters) == "Failed prompt")
    try await composer.flush()
    let restored = ComposerModel(store: store, sessionID: "s", directory: "/p"); await restored.load()
    #expect(restored.options.editingOutboxID == nil)
    restored.submit(preference: .steer)
    while restored.busy { await Task.yield() }
    #expect(restored.error == nil && restored.blank)
    let entries = try await OutboxStore(writer: writer).entries(serverID: "server")
    #expect(entries.count == 1 && entries.first?.id != id)
    #expect(try entries.first.map { try JSONDecoder().decode(PromptInput.self, from: $0.body).text } == "Failed prompt")
    await store.stop()
}

@Test @MainActor func staleEditingReferenceFallsBackToNewAdmission() async throws {
    for state in ["missing", "pending", "needsConfirmation"] {
        let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
        store.seed(info: readInfo(), messages: [])
        let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
        let id = try await store.sendPrompt("s", input: .init(text: "Old prompt"))
        if state == "missing" { store.outboxEntries.removeValue(forKey: id) }
        else { store.outboxEntries[id]?.state = state }
        composer.setOptions(.init(editingOutboxID: id))
        composer.setText(AttributedString("Edited prompt"))
        composer.submit(preference: .steer)
        while composer.busy { await Task.yield() }
        #expect(composer.error == nil && composer.blank)
        #expect(store.outboxEntries.values.contains { $0.id != id && String(decoding: $0.body, as: UTF8.self).contains("Edited prompt") })
        await store.stop()
    }
}

@Test @MainActor func acknowledgementsAndCancelClearOnlyTheEditingReference() async throws {
    for action in ["cancel", "event", "response", "reload"] {
        let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer))
        store.seed(info: readInfo(), messages: [])
        let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
        let id = try await store.sendPrompt("s", input: .init(text: "Original"))
        store.outboxEntries[id]?.state = "failed"
        try await store.restoreFailedPrompt(id)
        composer.setText(AttributedString("Keep these edits"))
        switch action {
        case "cancel": composer.cancelEditingOutbox()
        case "event": store.acknowledgeEvent(id)
        case "response": store.acknowledgeResponse(id, result: .prompt(.init(raw: .object(["id": .string(id), "sessionID": .string("s")]))))
        default: try await store.reloadOutbox()
        }
        #expect(composer.options.editingOutboxID == nil)
        #expect(String(composer.text.characters) == "Keep these edits")
        try await composer.flush()
        #expect(try await store.drafts?.load(serverID: "server", sessionID: "s")?.options.editingOutboxID == nil)
        if action == "cancel" { #expect(store.outboxEntries[id]?.state == "failed") }
        await store.stop()
    }
}

@Test @MainActor func relaunchClearsAStalePersistedEditingReference() async throws {
    let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer))
    let draft = try Draft(serverID: "server", sessionID: "s", attributedText: AttributedString("Recovered edits"),
                          options: .init(editingOutboxID: "discarded"))
    await store.drafts?.save(draft); try await store.drafts?.flush()
    try await store.loadCache()
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/p"); await composer.load()
    #expect(composer.options.editingOutboxID == nil && String(composer.text.characters) == "Recovered edits")
    try await composer.flush()
    #expect(try await store.drafts?.load(serverID: "server", sessionID: "s")?.options.editingOutboxID == nil)
    await store.stop()
}

@Test @MainActor func discardingAFailedCreationClearsEditingForItsPrompts() async throws {
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: try PersistenceWriter()))
    let session = try await store.createSession(location: .init(directory: "/p"))
    let prompt = try await store.sendPrompt(session, input: .init(text: "First prompt"))
    store.outboxEntries[session]?.state = "failed"; store.outboxEntries[prompt]?.state = "failed"
    let composer = store.composer(sessionID: session, directory: "/p"); await composer.load()
    composer.setOptions(.init(editingOutboxID: prompt))
    try await store.discardOutbox(session)
    #expect(composer.options.editingOutboxID == nil)
    await store.stop()
}

import Foundation
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCSecurity
import OCPersistence
import OCSync

private let writeEnvironment = ProcessInfo.processInfo.environment
private let writeLive = writeEnvironment["OPENCODE_LIVE_MOCK_URL"] != nil
private enum WriteLiveError: Error { case timeout, sandbox }
private struct LiveAuthentication: BiometricAuthenticating {
    // The live contract tests the write path. Device authentication is exercised
    // separately with an injectable gate; this never ships in the app.
    func authenticate(reason: String) async throws {}
}

@MainActor private final class WriteContract {
    let store: ServerStore
    let api: APIClient
    let mock: URL
    let directory: String
    init() async throws {
        let address = try #require(writeEnvironment["OPENCODE_LIVE_URL"])
        let mockAddress = try #require(writeEnvironment["OPENCODE_LIVE_MOCK_URL"])
        let url = try #require(URL(string: address))
        mock = try #require(URL(string: mockAddress))
        directory = try #require(writeEnvironment["OPENCODE_LIVE_DIRECTORY"])
        guard directory.contains("/.build/opencode-sandbox/"), EndpointPolicy.isLoopback(url) else { throw WriteLiveError.sandbox }
        let credential = Credential.password(try #require(writeEnvironment["OPENCODE_LIVE_PASSWORD"]))
        api = APIClient(baseURL: url, credential: credential)
        let endpoint = EndpointRecord(url: url, kind: .lan), record = ServerRecord(name: "Write contract", endpoints: [endpoint])
        let credentials = CredentialStore(secrets: InMemorySecretStore())
        try await credentials.save(credential, for: record.id)
        let connection = ServerConnection(endpoints: [endpoint], credential: credential, pathMonitor: nil)
        await connection.allowLocalNetwork()
        store = ServerStore(record: record, connection: connection, credentials: credentials, cache: CacheStore(writer: try PersistenceWriter()))
        store.readPath.biometricGate = LiveAuthentication()
        await store.start()
        try await until { self.store.resync?.records.last?.succeeded == true }
    }
    func until(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !predicate() {
            if ContinuousClock.now >= deadline { throw WriteLiveError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    func scenario(_ name: String) async throws {
        var request = URLRequest(url: mock.appending(path: "admin/scenario")); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["name": name])
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }
    func session(_ title: String) async throws -> String {
        let id = try await store.readPath.createSession(location: .init(directory: directory), title: title,
            model: .init(raw: .object(["providerID": .string("mock"), "id": .string("mock-1")])))
        try await until { self.store.readPath.outboxEntries[id] == nil }
        try await store.readPath.open(id)
        return id
    }
    @discardableResult func prompt(_ session: String, _ text: String = "Run the scenario.", delivery: Delivery = .steer, resume: Bool? = nil) async throws -> String {
        let id = try await store.readPath.sendPrompt(session, input: .init(text: text, delivery: delivery, resume: resume))
        try await until { self.store.readPath.outboxEntries[id] == nil }
        return id
    }
    func idle(_ id: String) async throws {
        try await api.send(Endpoint<Void>(method: .post, path: "/api/experimental/session/\(id)/wait") { _, _ in () })
        try await until { self.store.sessions[id]?.status == .idle }
    }
    func parity(_ id: String, _ label: String) async throws {
        let messages = try await api.send(ReadEndpoints.messages(id, limit: 200, order: .asc)).data
        let info = try await api.send(ReadEndpoints.session(id)).data
        let pending = try await api.send(ReadEndpoints.inbox(id)).data
        let permissions = try await api.send(ReadEndpoints.permissions(id)).data
        let forms = try await api.send(ReadEndpoints.forms(id)).data
        // Pending user and synthetic input is materialized in the transcript,
        // but the message endpoint contains only delivered rows.
        let pendingRows = pending.filter { item in ["user", "synthetic"].contains(item.type) && !messages.contains(where: { $0.id == item.id }) }
        let expected = messages.map { $0.raw.omittingNullFields } + pendingRows.map { item in
            var raw = item.fields.payload.raw
            raw.set("id", .string(item.id)); raw.set("type", .string(item.type)); raw.set("time", item.fields.time.raw)
            return raw.omittingNullFields
        }
        do {
            try await until { self.store.sessions[id]?.transcript?.snapshot.map { $0.raw.omittingNullFields } == expected }
            try await until { self.store.sessions[id]?.info.raw.omittingNullFields == info.raw.omittingNullFields }
        } catch {
            print("Parity failure: \(label); expected IDs \(expected.compactMap { $0["id"]?.stringValue }); actual IDs \(self.store.sessions[id]?.transcript?.order ?? [])")
            print("Expected info \(info.raw.omittingNullFields); actual \(String(describing: self.store.sessions[id]?.info.raw.omittingNullFields))")
            throw error
        }
        #expect(store.sessions[id]?.pending.map(\.raw) == pending.map(\.raw))
        #expect(store.permissions[id]?.map(\.raw) == permissions.map(\.raw))
        #expect(store.forms[.session(id)]?.map(\.raw) == forms.map(\.raw))
        print("PASS store projection equals snapshot: \(label)")
    }
}

extension LiveContracts {
@Test(.enabled(if: writeLive, "Requires Tools/contract sandbox"), .timeLimit(.minutes(5)))
@MainActor func sandboxWritePaths() async throws {
    let c = try await WriteContract()
    do {
        try await c.scenario("steer-queue")
        let steer = try await c.session("Steer and queue")
        try await c.prompt(steer)
        try await c.until { c.store.running.contains(steer) }
        try await c.prompt(steer, "Apply steering input.")
        try await c.prompt(steer, "Run this next turn.", delivery: .queue)
        try await c.idle(steer); try await c.parity(steer, "steer while running; queue next turn")
        #expect(c.store.sessions[steer]?.transcript?.snapshot.filter { $0.type == "user" }.count == 3)

        try await c.scenario("plain-text")
        let queued = try await c.session("Steer now and cancel")
        let cancelled = try await c.prompt(queued, "Restore this draft.", delivery: .queue, resume: false)
        try await c.store.readPath.cancelPending(queued, itemID: cancelled)
        try await c.parity(queued, "cancel queued item")
        let draft = try await c.store.readPath.drafts?.load(serverID: c.store.readPath.serverID, sessionID: queued)
        #expect(try draft?.attributedText == AttributedString("Restore this draft."))
        let promoted = try await c.prompt(queued, "Steer now.", delivery: .queue, resume: false)
        try await c.store.readPath.changeDelivery(queued, itemID: promoted, delivery: .steer)
        try await c.idle(queued); try await c.parity(queued, "steer now via inbox PATCH")

        for resume in [false, true] {
            try await c.scenario(resume ? "interrupt-resume" : "interrupt")
            let id = try await c.session("Interrupt")
            try await c.prompt(id)
            try await c.until { c.store.sessions[id]?.transcript?.snapshot.contains { $0.content.contains { $0.fields.text == "Starting." } } == true }
            if resume { try await c.prompt(id, "Resume with this steer.") }
            #expect(try await c.store.readPath.interrupt(id, resume: resume))
            try await c.idle(id); try await c.parity(id, resume ? "interrupt with resume" : "interrupt")
        }
        for decision in [PermissionDecision.once, .reject, .always] {
            try Data("original fixture line\nsecond line\n".utf8).write(to: URL(fileURLWithPath: c.directory).appending(path: "sample.txt"), options: .atomic)
            try await c.scenario(decision == .reject ? "permission-reject" : "permission-allow")
            let id = try await c.session("Permission \(decision.rawValue)")
            try await c.prompt(id)
            try await c.until { !(c.store.permissions[id] ?? []).isEmpty }
            let request = try #require(c.store.permissions[id]?.first)
            let start = ContinuousClock.now
            try await c.store.readPath.replyPermission(request, decision: decision, message: decision == .reject ? "Keep the original fixture text." : nil)
            try await c.until {
                c.store.sessions[id]?.transcript?.snapshot.flatMap(\.content).contains { $0.fields.name == "edit" && ["completed", "error"].contains($0.fields.toolState.type) } == true
            }
            if decision == .once { print("Direct Allow once to tool completion: \(start.duration(to: .now))") }
            try await c.idle(id); try await c.parity(id, "permission \(decision.rawValue)")
        }
        for dismiss in [false, true] {
            try await c.scenario("question-form")
            let id = try await c.session(dismiss ? "Dismiss question" : "Answer question")
            try await c.prompt(id)
            try await c.until { !(c.store.forms[.session(id)] ?? []).isEmpty }
            let form = try #require(c.store.forms[.session(id)]?.first)
            try await c.store.readPath.replyForm(form, answer: dismiss ? nil : ["q0": .string("Blue")], reason: dismiss ? "Choose the default." : nil)
            try await c.idle(id); try await c.parity(id, dismiss ? "question dismiss with reason" : "question answer")
        }
        try await c.scenario("revert")
        let revert = try await c.session("Revert"), boundary = try await c.prompt(revert)
        try await c.idle(revert)
        try await c.store.readPath.stageRevert(revert, message: boundary)
        try await c.parity(revert, "revert stage")
        try await c.store.readPath.redo(revert); try await c.parity(revert, "redo")
        try await c.store.readPath.stageRevert(revert, message: boundary)
        try await c.store.readPath.commitRevert(revert); try await c.parity(revert, "revert commit")

        try await c.scenario("fork")
        let source = try await c.session("Fork"), _ = try await c.prompt(source)
        try await c.idle(source)
        let fork = try await c.store.readPath.fork(source)
        try await c.store.readPath.open(fork.id)
        try await c.parity(fork.id, "fork")
        try await c.scenario("compaction")
        let compact = try await c.session("Compact"), _ = try await c.prompt(compact)
        try await c.idle(compact)
        let compactID = try await c.store.readPath.compact(compact)
        try await c.until { c.store.readPath.outboxEntries[compactID] == nil }
        try await c.idle(compact); try await c.parity(compact, "compact")
        try await c.scenario("plain-text")
        let mentionSession = try await c.session("Mention encoding")
        var mentionText = AttributedString("😀 e\u{301}漢字 Read @sample.txt")
        if let range = mentionText.range(of: "@sample.txt") { mentionText[range][MentionAttribute.self] = .init(kind: "file", value: "sample.txt") }
        let encoded = ComposerInput.encode(mentionText, directory: c.directory, agent: "build", model: nil)
        let mentionID = try await c.store.readPath.sendPrompt(mentionSession, input: encoded)
        try await c.until { c.store.readPath.outboxEntries[mentionID] == nil }
        try await c.idle(mentionSession); try await c.parity(mentionSession, "mention-encoded prompt")
        let sent = try #require(c.store.sessions[mentionSession]?.transcript?.messages[mentionID]?.fields)
        #expect(ComposerInput.restoreText(sent.raw).runs.contains { $0[MentionAttribute.self]?.kind == "file" })
        try await c.scenario("plain-text")
        let commandSession = try await c.session("Server command")
        try await c.store.readPath.command(commandSession, name: "review", input: .init(text: "Review sample.txt"))
        try await c.idle(commandSession); try await c.parity(commandSession, "server command")
        let shellID = try await c.store.readPath.shell(commandSession, command: "printf 'm3b-shell'")
        #expect(shellID.hasPrefix("msg_"))
        try await c.until { c.store.sessions[commandSession]?.transcript?.messages[shellID]?.fields.status == "exited" }
        try await c.parity(commandSession, "shell with minted ID")
        #expect(try await c.store.readPath.findFiles("sample", directory: c.directory).contains { $0.path == "sample.txt" })
        #expect(try await c.store.readPath.listDirectory(c.directory, directory: c.directory).contains { $0.path == "sample.txt" })
        #expect(try await c.store.readPath.resolveDirectory(c.directory).directory == c.directory)
        if let worktreeDirectory = writeEnvironment["OPENCODE_LIVE_WORKTREE_DIRECTORY"] {
            let location = try await c.store.readPath.resolveDirectory(worktreeDirectory)
            let project = try #require(location.project)
            _ = try await c.store.readPath.worktrees(projectID: project.id)
            let created = try await c.store.readPath.createWorktree(projectID: project.id, from: project.canonical, branch: nil)
            #expect(created.directory != worktreeDirectory)
            #expect(try await c.store.readPath.worktrees(projectID: project.id).contains { $0.directory == created.directory })
            #expect(!(try await c.store.readPath.branches("", directory: worktreeDirectory)).isEmpty)
        }
        try await c.scenario("plain-text")
        let duplicateSession = try await c.session("Duplicate admission")
        c.store.readPath.setWritesConnected(false)
        let duplicateID = try await c.store.readPath.sendPrompt(duplicateSession, input: .init(text: "Exactly once", delivery: .queue, resume: false))
        let body = try #require(c.store.readPath.outboxEntries[duplicateID]?.body)
        await c.store.readPath.flushWrites()
        c.store.readPath.setWritesConnected(true)
        let first = try await c.api.send(WriteEndpoints.prompt(duplicateSession, body: body)).data
        let second = try await c.api.send(WriteEndpoints.prompt(duplicateSession, body: body)).data
        #expect(first.raw == second.raw)
        #expect(try await c.api.send(ReadEndpoints.inbox(duplicateSession)).data.filter { $0.id == duplicateID }.count == 1)
        // V2 reconciles by ID/session/type, not payload bytes: the first body wins.
        let changedBody = try PromptInput(text: "Different bytes", delivery: .queue, resume: false).body(id: duplicateID)
        let changedReplay = try await c.api.send(WriteEndpoints.prompt(duplicateSession, body: changedBody)).data
        #expect(changedReplay.raw == first.raw)
        print("PASS changed bytes preserve the first admission (V2 does not return 409 for this case)")
        // A cross-session ID collision is the server's actual 409 condition.
        let collisionSession = try await c.session("Admission collision")
        do {
            _ = try await c.api.send(WriteEndpoints.prompt(collisionSession, body: changedBody))
            Issue.record("A cross-session admission ID must conflict")
        } catch APIError.server(_, let status, _) { #expect(status == 409) }
        let conflictWriter = try PersistenceWriter(), conflictBox = OutboxStore(writer: conflictWriter)
        try await conflictBox.save(.init(id: duplicateID, serverID: "conflict", sessionID: collisionSession, body: changedBody))
        try await OutboxProcessor(store: conflictBox, serverID: "conflict").drain(using: c.api)
        #expect(try await conflictBox.entries(serverID: "conflict").first?.state == "failed")
        try await c.parity(collisionSession, "409 leaves the other session unchanged")
        try await c.until { c.store.readPath.outboxEntries[duplicateID] == nil }
        try await c.store.readPath.changeDelivery(duplicateSession, itemID: duplicateID, delivery: .steer)
        try await c.idle(duplicateSession); try await c.parity(duplicateSession, "duplicate and 409")
        #expect(c.store.sessions[duplicateSession]?.transcript?.snapshot.filter { $0.type == "user" }.count == 1)
        print("PASS mention, command, shell, filesystem, worktree, duplicate admission and 409 contracts")
        try await c.reviewContracts()
        await c.store.dispose()
    } catch { await c.store.dispose(); throw error }
}
}

private extension WriteContract {
    func reviewContracts() async throws {
        guard let fixture = writeEnvironment["OPENCODE_LIVE_REVIEW"] else { return }
        let values = try JSONDecoder().decode([String: String].self, from: Data(fixture.utf8))
        let directory = try #require(values["directory"]), session = try #require(values["session"]), from = try #require(values["from"])
        let vcs = try await api.send(ReviewEndpoints.vcs(directory)).data
        #expect(vcs.provider == "git" && vcs.current == "feature")
        let working = try await api.send(ReviewEndpoints.diff(directory)).data.values
        let branch = try await api.send(ReviewEndpoints.diff(directory, mode: "branch")).data.values
        #expect(working.contains { $0.file == "Large.swift" && $0.additions == 5000 && $0.deletions == 5000 })
        #expect(branch.contains { $0.file == "README.md" })
        #expect(try await api.send(ComposerEndpoints.branches("", directory: directory)).data.values.contains("main"))
        for context in [nil, 3] as [Int?] {
            let changes = try await api.send(ReadEndpoints.diff(session, from: from, to: from, context: context)).data
            #expect(changes.contains { $0.file == "Sources/Example.swift" })
        }
        let entries = try await api.send(ComposerEndpoints.list("", directory: directory)).data.values
        #expect(entries.contains { $0.path == ".hidden" })
        #expect(try await api.send(ComposerEndpoints.find("Example", directory: directory, type: "file", limit: 200)).data.values.contains { $0.path == "Sources/Example.swift" })
        let file = try await api.readFile("Sources/Example.swift", directory: directory)
        #expect(file.status == 200 && !file.data.isEmpty)
        #expect(try await api.readFile("Sources/Example.swift", directory: directory, etag: file.etag).status == 304)
        let range = try await api.readFile("Sources/Example.swift", directory: directory, range: 0..<4)
        #expect(range.status == 206 && range.data == file.data.prefix(4) && range.totalSize == file.data.count)
        #expect(try await api.readFile("Sources/Example.swift", directory: directory, range: 1_000_000..<1_000_010).status == 416)
        let noGit = try #require(values["noGit"])
        try await api.send(ReviewEndpoints.initialize(noGit))
        // Init rebuilds the location before its VCS plugin finishes activating.
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while try await api.send(ReviewEndpoints.vcs(noGit)).data.provider != "git" {
            if ContinuousClock.now >= deadline { throw WriteLiveError.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await store.readPath.open(session)
        try await scenario("plain-text")
        let composer = store.readPath.composer(sessionID: session, directory: directory)
        await composer.load(); composer.setText(AttributedString("Please address this"))
        composer.addComment(.init(file: "Sources/Example.swift", selection: .init(start: 2, end: 3), comment: "Simplify these lines", preview: "    let value = 2\n    let title = \"Original\""))
        composer.submit(preference: .steer)
        try await until { !composer.busy && composer.comments.isEmpty }
        try await until { self.store.readPath.outboxEntries.isEmpty }
        try await idle(session)
        let messages = try await api.send(ReadEndpoints.messages(session, limit: 200, order: .asc)).data
        let user = try #require(messages.last { $0.type == "user" })
        #expect(user.fields.text == "Please address this\nThe user made the following comment regarding lines 2 through 3 of Sources/Example.swift: Simplify these lines")
        #expect(user.fields.metadata?["comments"]?[0]?["selection"]?["startLine"] == .integer(2))
        #expect(LineComment.restore(user.raw).first?.comment == "Simplify these lines")
        try await parity(session, "review comment")
        print("PASS session.diff from/to/context, VCS working/branch/init, fs list/find/read 200/206/304/416, comment prompt and projection parity")
    }
}

import Foundation
import Testing
import Synchronization
import Clocks
import OCModels
import OCFoundation
import OCNetworking
import OCPersistence
@testable import OCSync

/// Answers by method and path; records every request with its body.
final class AdminTransport: HTTPTransport, Sendable {
    struct Reply: Sendable { var status = 200; var body: JSONValue = .object([:]) }
    let routes: Mutex<[String: [Reply]]>
    let log = Mutex<[(String, Data?)]>([])
    init(_ routes: [String: [Reply]] = [:]) { self.routes = Mutex(routes) }
    func add(_ route: String, _ replies: Reply...) { routes.withLock { $0[route, default: []].append(contentsOf: replies) } }
    var requests: [String] { log.withLock { $0.map(\.0) } }
    func body(of route: String) -> JSONValue? {
        log.withLock { $0.last { $0.0 == route }?.1 }.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = try #require(request.url), route = (request.httpMethod ?? "GET") + " " + url.path
        log.withLock { $0.append((route, request.httpBody)) }
        // The last reply repeats, so a poll can stay pending.
        let reply = routes.withLock { routes -> Reply in
            guard var replies = routes[route], !replies.isEmpty else { return Reply(status: 404, body: .object(["_tag": .string("NotFound")])) }
            let next = replies.removeFirst()
            routes[route] = replies.isEmpty ? [next] : replies
            return next
        }
        let data = reply.status == 204 ? Data() : try JSONEncoder().encode(reply.body)
        return .init(data: data, response: try #require(HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil,
                                                                         headerFields: ["Content-Type": "application/json"])))
    }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

private func located(_ data: JSONValue) -> JSONValue { .object(["location": .object(["directory": .string("/p")]), "data": data]) }
private let noContent = AdminTransport.Reply(status: 204)

@MainActor private func adminModel(_ transport: AdminTransport, cache: CacheStore? = nil, clock: any Clock<Duration> = ImmediateClock(),
                                   now: @escaping @Sendable () -> Date = Date.init,
                                   log: @escaping @Sendable (RedactedLogMessage) -> Void = { _ in }) -> (ReadStore, ServerAdminModel) {
    let client = APIClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: transport)
    let store = ReadStore(serverID: UUID().uuidString, cache: cache, client: { client })
    store.projects = [Project(raw: .object(["id": .string("prj"), "canonical": .string("/p"), "time": .object(["created": .integer(0), "updated": .integer(0), "active": .integer(2)])])),
                      Project(raw: .object(["id": .string("old"), "canonical": .string("/old"), "time": .object(["created": .integer(0), "updated": .integer(0), "active": .integer(1)])]))]
    let model = ServerAdminModel(store: store, clock: clock, now: now, log: log)
    store.adminModel = model; store.register(model)
    model.appear()
    return (store, model)
}
private func integration(accounts: [String] = []) -> JSONValue {
    .object(["id": .string("mock"), "name": .string("Fixture Mock"),
             "methods": .array([.object(["type": .string("key"), "label": .string("API key")]),
                                .object(["type": .string("oauth"), "id": .string("browser"), "label": .string("Browser")]),
                                .object(["type": .string("command"), "id": .string("cli"), "label": .string("CLI login"), "command": .array([.string("login")])])]),
             "connections": .array(accounts.map { .object(["type": .string("credential"), "id": .string("cred_" + $0), "label": .string($0), "method": .string("key")]) })])
}

@Test @MainActor func picksTheMostRecentProjectAndLoadsIntegrations() async throws {
    let transport = AdminTransport(["GET /api/integration": [.init(body: located(.array([integration(accounts: ["Second", "First"]), .string("junk")])))]])
    let (store, admin) = adminModel(transport)
    #expect(admin.directory == "/p")
    await admin.loadIntegrations()
    let mock = try #require(admin.integrations.value?.first)
    #expect(admin.integrations.value?.count == 1, "Undecodable rows are dropped")
    #expect(mock.accounts.map(\.label) == ["Second", "First"])
    #expect(mock.methods.map(\.type) == ["key", "oauth", "command"])
    withExtendedLifetime(store) {}
}

@Test @MainActor func emptyStatesAndServerErrors() async throws {
    let transport = AdminTransport(["GET /api/integration": [.init(body: located(.array([])))],
                                    "GET /api/permission/saved": [.init(status: 500, body: .object(["_tag": .string("Boom"), "message": .string("Database locked")]))]])
    let (store, admin) = adminModel(transport)
    await admin.loadIntegrations()
    #expect(admin.integrations.value == [])
    await admin.loadSavedPermissions(projectID: "prj")
    #expect(admin.savedPermissions(for: "prj").value == nil)
    #expect(admin.error == "Database locked")
    withExtendedLifetime(store) {}
}

@Test @MainActor func apiKeysAreSentOnceAndNeverStoredOrLogged() async throws {
    let secret = "fake-test-key-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = directory.appendingPathComponent("cache.sqlite")
    let cache = CacheStore(writer: try PersistenceWriter(url: database))
    let messages = Mutex<[String]>([])
    let transport = AdminTransport(["POST /api/integration/mock/connect/key": [noContent],
                                    "GET /api/integration": [.init(body: located(.array([integration(accounts: ["Work"])])))]])
    let (store, admin) = adminModel(transport, cache: cache, log: { message in messages.withLock { $0.append(message.text) } })
    let mock = IntegrationInfo(raw: integration())
    #expect(await admin.connectKey(mock, key: "  " + secret + " ", answers: .object(["region": .string("eu")]), label: "Work"))
    #expect(transport.requests.filter { $0.contains("connect/key") }.count == 1)
    let body = try #require(transport.body(of: "POST /api/integration/mock/connect/key"))
    #expect(body["key"]?.stringValue == secret, "Trimmed, sent as is")
    #expect(body["label"]?.stringValue == "Work" && body["answer"]?["region"]?.stringValue == "eu")
    #expect(admin.notice == "Fixture Mock connected")
    #expect(admin.integrations.value?.first?.accounts.first?.label == "Work")
    // Nothing kept: not the model, the log, the cache database or the defaults.
    #expect(!String(describing: admin.integrations.value as Any).contains(secret))
    #expect(messages.withLock { $0 }.allSatisfy { !$0.contains(secret) } && !messages.withLock { $0 }.isEmpty)
    await store.stop()
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        #expect(try Data(contentsOf: file).range(of: Data(secret.utf8)) == nil, "\(file.lastPathComponent) holds the key")
    }
    let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { String(describing: $0) }
    #expect(!defaults.contains { $0.contains(secret) })
    // Empty keys never reach the server.
    #expect(!(await admin.connectKey(mock, key: "   ", answers: nil, label: nil)))
    #expect(transport.requests.filter { $0.contains("connect/key") }.count == 1)
}

@Test @MainActor func oauthCodeFlowCompletesWithThePastedCode() async throws {
    let attempt = located(.object(["attemptID": .string("con_1"), "url": .string("https://example.invalid/auth"), "instructions": .string("Paste the code"),
                                   "mode": .string("code"), "time": .object(["created": .integer(0), "expires": .integer(9_999_999_999_999)])]))
    let transport = AdminTransport(["POST /api/integration/mock/connect/oauth": [.init(body: attempt)],
                                    "POST /api/integration/mock/connect/oauth/con_1/complete": [noContent],
                                    "GET /api/integration/mock/connect/oauth/con_1": [.init(body: located(.object(["status": .string("complete")])))],
                                    "GET /api/integration": [.init(body: located(.array([integration(accounts: ["Browser"])])))]])
    let (store, admin) = adminModel(transport)
    let mock = IntegrationInfo(raw: integration())
    admin.beginConnect(mock, method: try #require(mock.methods.first { $0.type == "oauth" }))
    let flow = try #require(admin.connect)
    await settle { if case .code = flow.phase { true } else { false } }
    #expect(transport.body(of: "POST /api/integration/mock/connect/oauth")?["methodID"]?.stringValue == "browser")
    #expect(!transport.requests.contains("GET /api/integration/mock/connect/oauth/con_1"), "A code attempt waits for the code")
    flow.submit(code: "  abc123 ")
    await settle { flow.phase == .complete }
    #expect(transport.body(of: "POST /api/integration/mock/connect/oauth/con_1/complete")?["code"]?.stringValue == "abc123")
    await settle { admin.integrations.value?.first?.accounts.first?.label == "Browser" }
    #expect(admin.notice == "Fixture Mock connected")
    withExtendedLifetime(store) {}
}

@Test @MainActor func oauthAutoFlowPollsUntilCompleteFailedOrExpired() async throws {
    func attempt(_ id: String, expires: Int64 = 9_999_999_999_999) -> AdminTransport.Reply {
        .init(body: located(.object(["attemptID": .string(id), "url": .string("http://localhost:1455/auth"), "instructions": .string(""),
                                     "mode": .string("auto"), "time": .object(["created": .integer(0), "expires": .integer(expires)])])))
    }
    let pending = AdminTransport.Reply(body: located(.object(["status": .string("pending")])))
    for (outcome, last, expected) in [("complete", AdminTransport.Reply(body: located(.object(["status": .string("complete")]))), ConnectFlow.Phase.complete),
                                      ("failed", .init(body: located(.object(["status": .string("failed"), "message": .string("Denied")]))), .failed("Denied")),
                                      ("expired", .init(body: located(.object(["status": .string("expired")]))), .expired)] {
        let clock = TestClock()
        let transport = AdminTransport(["POST /api/integration/mock/connect/oauth": [attempt("con_" + outcome)],
                                        "GET /api/integration/mock/connect/oauth/con_" + outcome: [pending, pending, last],
                                        "GET /api/integration": [.init(body: located(.array([integration()])))]])
        let (store, admin) = adminModel(transport, clock: clock)
        let mock = IntegrationInfo(raw: integration())
        admin.beginConnect(mock, method: try #require(mock.methods.first { $0.type == "oauth" }))
        let flow = try #require(admin.connect)
        await settle { if case .waiting = flow.phase { true } else { false } }
        await settle { transport.requests.filter { $0.hasSuffix("con_" + outcome) }.count == 1 }
        await clock.advance(by: .seconds(2))
        await settle { transport.requests.filter { $0.hasSuffix("con_" + outcome) }.count == 2 }
        #expect(!flow.phase.isFinished)
        await clock.advance(by: .seconds(2))
        await settle { flow.phase == expected }
        withExtendedLifetime(store) {}
    }
    // The attempt's own deadline ends the wait even while the server still says pending.
    let clock = TestClock(), deadline = Date(timeIntervalSince1970: 1_000)
    let now = Mutex(Date(timeIntervalSince1970: 900))
    let transport = AdminTransport(["POST /api/integration/mock/connect/oauth": [attempt("con_late", expires: 1_000_000)],
                                    "GET /api/integration/mock/connect/oauth/con_late": [pending]])
    let (store, admin) = adminModel(transport, clock: clock, now: { now.withLock { $0 } })
    let mock = IntegrationInfo(raw: integration())
    admin.beginConnect(mock, method: try #require(mock.methods.first { $0.type == "oauth" }))
    let flow = try #require(admin.connect)
    await settle { transport.requests.contains("GET /api/integration/mock/connect/oauth/con_late") }
    now.withLock { $0 = deadline }
    await clock.advance(by: .seconds(2))
    await settle { flow.phase == .expired }
    withExtendedLifetime(store) {}
}

@Test @MainActor func cancellingASignInCancelsItOnTheServer() async throws {
    let clock = TestClock()
    let transport = AdminTransport(["POST /api/integration/mock/connect/oauth": [.init(body: located(.object(["attemptID": .string("con_2"), "url": .string("https://example.invalid"), "instructions": .string(""), "mode": .string("auto"), "time": .object([:])])))],
                                    "GET /api/integration/mock/connect/oauth/con_2": [.init(body: located(.object(["status": .string("pending")])))],
                                    "DELETE /api/integration/mock/connect/oauth/con_2": [noContent]])
    let (store, admin) = adminModel(transport, clock: clock)
    let mock = IntegrationInfo(raw: integration())
    admin.beginConnect(mock, method: try #require(mock.methods.first { $0.type == "oauth" }))
    let flow = try #require(admin.connect)
    await settle { if case .waiting = flow.phase { true } else { false } }
    admin.endConnect()
    #expect(flow.phase == .cancelled && admin.connect == nil)
    await settle { transport.requests.contains("DELETE /api/integration/mock/connect/oauth/con_2") }
    await clock.advance(by: .seconds(10))
    #expect(transport.requests.filter { $0 == "GET /api/integration/mock/connect/oauth/con_2" }.count <= 2, "Polling stops")
    withExtendedLifetime(store) {}
}

@Test @MainActor func commandSignInShowsTheServersMessages() async throws {
    let clock = TestClock()
    let transport = AdminTransport(["POST /api/integration/mock/connect/command": [.init(body: located(.object(["attemptID": .string("con_3"), "time": .object([:])])))],
                                    "GET /api/integration/mock/connect/command/con_3": [
                                        .init(body: located(.object(["status": .string("pending"), "message": .string("Open https://example.invalid/device and enter ABCD-1234")]))),
                                        .init(body: located(.object(["status": .string("complete")])))],
                                    "GET /api/integration": [.init(body: located(.array([integration()])))]])
    let (store, admin) = adminModel(transport, clock: clock)
    let mock = IntegrationInfo(raw: integration())
    admin.beginConnect(mock, method: try #require(mock.methods.first { $0.type == "command" }))
    let flow = try #require(admin.connect)
    await settle { flow.phase == .command(message: "Open https://example.invalid/device and enter ABCD-1234") }
    #expect(transport.body(of: "POST /api/integration/mock/connect/command")?["methodID"]?.stringValue == "cli")
    await clock.advance(by: .seconds(2))
    await settle { flow.phase == .complete }
    withExtendedLifetime(store) {}
}

@Test @MainActor func accountsAreRenamedActivatedAndRemoved() async throws {
    let transport = AdminTransport(["PATCH /api/credential/cred_Work": [noContent], "POST /api/credential/cred_Work/activate": [noContent],
                                    "DELETE /api/credential/cred_Work": [noContent],
                                    "GET /api/integration": [.init(body: located(.array([integration(accounts: ["Home", "Work"])])))]])
    let (store, admin) = adminModel(transport)
    let account = IntegrationConnection(raw: .object(["type": .string("credential"), "id": .string("cred_Work"), "label": .string("Work"), "method": .string("key")]))
    #expect(await admin.rename(account, label: " Office "))
    #expect(transport.body(of: "PATCH /api/credential/cred_Work")?["label"]?.stringValue == "Office")
    #expect(!(await admin.rename(account, label: "  ")))
    #expect(await admin.activate(account))
    #expect(await admin.remove(account))
    #expect(transport.requests.contains("DELETE /api/credential/cred_Work"))
    #expect(!transport.requests.contains("GET /api/credential"), "The secret-returning list is never read")
    withExtendedLifetime(store) {}
}

@Test @MainActor func savedPermissionsAreDeletedEvenWhenAlreadyGone() async throws {
    let rules: JSONValue = .object(["data": .array([
        .object(["id": .string("psv_1"), "projectID": .string("prj"), "action": .string("edit"), "resource": .string("src/*"), "time": .object(["created": .integer(1), "updated": .integer(1)])]),
        .object(["id": .string("psv_2"), "projectID": .string("prj"), "action": .string("shell"), "resource": .string("git *"), "time": .object(["created": .integer(2), "updated": .integer(2)])])])])
    let transport = AdminTransport(["GET /api/permission/saved": [.init(body: rules)], "DELETE /api/permission/saved/psv_1": [noContent],
                                    "DELETE /api/permission/saved/psv_2": [.init(status: 404, body: .object(["_tag": .string("PermissionSavedNotFoundError")]))]])
    let (store, admin) = adminModel(transport)
    await admin.loadSavedPermissions(projectID: "prj")
    let loaded = try #require(admin.savedPermissions(for: "prj").value)
    #expect(loaded.map(\.id) == ["psv_2", "psv_1"], "Newest first")
    #expect(await admin.deleteSavedPermission(loaded[1]))
    #expect(await admin.deleteSavedPermission(loaded[0]))
    #expect(admin.error == nil)
    #expect(transport.requests.contains("DELETE /api/permission/saved/psv_1") && transport.requests.contains("DELETE /api/permission/saved/psv_2"))
    withExtendedLifetime(store) {}
}

@Test @MainActor func worktreeRemovalChecksForChangesAndForcesOnlyWhenAsked() async throws {
    let dirty: JSONValue = .object(["_tag": .string("WorktreeError"), "name": .string("WorktreeError"),
                                    "data": .object(["message": .string("contains modified or untracked files"), "forceRequired": .bool(true)])])
    let transport = AdminTransport(["GET /api/vcs/status": [.init(body: .object(["location": .object(["directory": .string("/wt")]), "data": .array([
                                        .object(["file": .string("README.md"), "additions": .integer(1), "deletions": .integer(0), "status": .string("modified")])])]))],
                                    "DELETE /api/worktree": [.init(status: 400, body: dirty), noContent],
                                    "GET /api/worktree": [.init(body: .array([.object(["directory": .string("/p")])]))]])
    let (store, admin) = adminModel(transport)
    let worktree = WorktreeInfo(raw: .object(["directory": .string("/wt"), "strategy": .string("git")]))
    #expect(await admin.uncommittedChanges(in: worktree)?.map(\.file) == ["README.md"])
    #expect(await admin.removeWorktree(worktree, projectID: "prj", force: false) == .forceRequired("contains modified or untracked files"))
    #expect(transport.body(of: "DELETE /api/worktree")?["force"] == .bool(false))
    #expect(admin.error == nil, "A refusal that needs force is not an error")
    #expect(await admin.removeWorktree(worktree, projectID: "prj", force: true) == .removed)
    #expect(transport.body(of: "DELETE /api/worktree") == .object(["projectID": .string("prj"), "directory": .string("/wt"), "force": .bool(true)]))
    #expect(admin.worktrees(for: "prj").value?.map(\.directory) == ["/p"])
    withExtendedLifetime(store) {}
}

@Test @MainActor func updateNoticesAndInvalidationsFollowEvents() async throws {
    let (store, admin) = adminModel(AdminTransport())
    admin.integrations.seed([]); admin.plugins.seed([])
    store.handle(try readEvent("installation.update-available", session: "", data: ["version": .string("2.3.0")]))
    #expect(admin.availableUpdate == "2.3.0")
    store.handle(try readEvent("credential.switched", session: ""))
    store.handle(try readEvent("plugin.updated", session: ""))
    #expect(admin.integrations.isStale && admin.plugins.isStale)
    store.handle(try readEvent("installation.updated", session: "", data: ["version": .string("2.3.0")]))
    #expect(admin.availableUpdate == nil)
}

@Test @MainActor func shellChangesPatchTheGlobalConfigurationAndLocationsReload() async throws {
    let transport = AdminTransport(["PATCH /api/experimental/config": [noContent], "POST /api/location/reload": [noContent],
                                    "DELETE /api/debug/location": [noContent],
                                    "GET /api/debug/location": [.init(body: .array([.object(["directory": .string("/p")])]))],
                                    "GET /api/config": [.init(body: .array([.object(["type": .string("document"), "path": .string("/g/opencode.json"), "info": .object(["shell": .string("/bin/zsh")])]),
                                                                            .object(["type": .string("document"), "info": .object(["shell": .string("/bin/bash")])])]))],
                                    "GET /api/config/shell": [.init(body: .array([.object(["path": .string("/bin/zsh"), "name": .string("zsh"), "acceptable": .bool(true)])]))]])
    let (store, admin) = adminModel(transport)
    #expect(await admin.setShell("/bin/zsh"))
    #expect(transport.body(of: "PATCH /api/experimental/config") == .object(["shell": .string("/bin/zsh")]))
    #expect(await admin.setShell(nil))
    #expect(transport.body(of: "PATCH /api/experimental/config") == .object(["shell": .null]))
    #expect(admin.configuredShell == "/bin/bash", "The highest-precedence document wins")
    await admin.loadLocations()
    await admin.evict(try #require(admin.locations.value?.first))
    #expect(transport.requests.contains("DELETE /api/debug/location"))
    await admin.reloadLocations()
    #expect(admin.notice == "Configuration reloaded")
    withExtendedLifetime(store) {}
}

@Test @MainActor func signInsSurviveTheBackgroundAndRetryDroppedPolls() async throws {
    let clock = TestClock()
    let pending = AdminTransport.Reply(body: located(.object(["status": .string("pending")])))
    let transport = AdminTransport(["POST /api/integration/mock/connect/oauth": [.init(body: located(.object(["attemptID": .string("con_4"), "url": .string("https://example.invalid"), "instructions": .string(""), "mode": .string("auto"), "time": .object([:])])))],
                                    "GET /api/integration/mock/connect/oauth/con_4": [pending, .init(status: 503, body: .object(["_tag": .string("ServiceUnavailableError")])), pending,
                                                                                      .init(body: located(.object(["status": .string("complete")])))],
                                    "GET /api/integration": [.init(body: located(.array([integration()])))]])
    let (store, admin) = adminModel(transport, clock: clock)
    let mock = IntegrationInfo(raw: integration())
    admin.beginConnect(mock, method: try #require(mock.methods.first { $0.type == "oauth" }))
    let flow = try #require(admin.connect)
    await settle { transport.requests.filter { $0.hasSuffix("con_4") }.count == 1 }
    // Opening the link backgrounds the app: polling pauses, the attempt stays open.
    await store.stop()
    #expect(admin.connect === flow && !flow.phase.isFinished)
    #expect(!transport.requests.contains("DELETE /api/integration/mock/connect/oauth/con_4"))
    store.resume()
    await settle { transport.requests.filter { $0.hasSuffix("con_4") }.count == 2 }
    for _ in 0..<3 where !flow.phase.isFinished {
        await clock.advance(by: .seconds(2))
        for _ in 0..<50 { await Task.yield() }
    }
    await settle { flow.phase == .complete }
}

@Test @MainActor func eachWindowHasItsOwnSettingsModel() async throws {
    let (store, shared) = adminModel(AdminTransport())
    let first = ServerAdminScope(), second = ServerAdminScope()
    let a = first.model(for: store), b = second.model(for: store)
    #expect(a !== b && first.model(for: store) === a, "A window keeps its model; another window gets its own")
    a.appear(); b.appear()
    a.directory = "/old"; a.error = "Only in the first window"; a.notice = "Mock connected"
    #expect(b.directory == "/p" && b.error == nil && b.notice == nil)
    // Server events reach every open model.
    store.handle(try readEvent("installation.update-available", session: "", data: ["version": .string("2.3.0")]))
    #expect(a.availableUpdate == "2.3.0" && b.availableUpdate == "2.3.0" && shared.availableUpdate == "2.3.0")
}

@Test @MainActor func aWindowDropsTheModelOfARemovedServer() {
    let scope = ServerAdminScope()
    let first = ReadStore(serverID: "same"), second = ReadStore(serverID: "same")
    let old = scope.model(for: first)
    #expect(scope.model(for: second) !== old, "A server added again with the same id gets a model of its new store")
    withExtendedLifetime(first) {}
}

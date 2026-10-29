import Foundation
import Synchronization
import Testing
import Clocks
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence
@testable import OCSync

/// A scripted socket: the test yields its events and reads what the session sent.
final class FakeSocket: WebSocketConnection {
    let events: AsyncStream<PTYEvent>
    let continuation: AsyncStream<PTYEvent>.Continuation
    let request: URLRequest
    private let state = Mutex((sent: [String](), closed: false))
    init(request: URLRequest) { self.request = request; (events, continuation) = AsyncStream.makeStream() }
    var sent: [String] { state.withLock { $0.sent } }
    var closed: Bool { state.withLock { $0.closed } }
    var cursor: String? { URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value }
    func send(_ text: String) async throws { state.withLock { $0.sent.append(text) } }
    func close() { state.withLock { $0.closed = true }; continuation.finish() }
}
final class FakeSockets: WebSocketConnecting {
    private let state = Mutex([FakeSocket]())
    var opened: [FakeSocket] { state.withLock { $0 } }
    func open(_ request: URLRequest) -> any WebSocketConnection {
        let socket = FakeSocket(request: request)
        state.withLock { $0.append(socket) }
        return socket
    }
}
@MainActor final class FakeEngine: TerminalEngine {
    var fed: [String] = []
    var resets = 0
    var restored: [String] = []
    var size: (cols: Int, rows: Int) = (80, 24)
    var applicationCursor = false
    func feed(_ text: String) { fed.append(text) }
    func replay(_ text: String) { fed.append(text); replayed.append(text) }
    var replayed: [String] = []
    func reset() { resets += 1; fed = [] }
    func snapshot(scrollback: Int) -> String? { (restored + fed).joined() }
    func restore(_ screen: String, cols: Int, rows: Int) { restored.append(screen) }
}
actor TerminalRequests {
    var requests: [(method: String, path: String, body: JSONValue?)] = []
    func record(_ request: URLRequest) {
        requests.append((request.httpMethod ?? "GET", request.url?.path ?? "", request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }))
    }
    func count(_ method: String, _ path: String) -> Int { requests.filter { $0.method == method && $0.path == path }.count }
    func last(_ method: String, _ path: String) -> JSONValue? { requests.last { $0.method == method && $0.path == path }?.body }
}
struct TerminalTransport: HTTPTransport {
    let log: TerminalRequests
    let respond: @Sendable (URLRequest) async -> (Int, JSONValue)
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        await log.record(request)
        let (status, body) = await respond(request), url = try #require(request.url)
        return .init(data: status == 204 ? Data() : try JSONEncoder().encode(body),
                     response: try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
    }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}
/// A value the test changes while the transport reads it.
final class Shared<Value: Sendable>: Sendable {
    fileprivate let storage: Mutex<Value>
    init(_ value: Value) { storage = Mutex(value) }
    var value: Value { storage.withLock { $0 } }
    func set(_ value: Value) { storage.withLock { $0 = value } }
}
extension Shared {
    /// The first element, removed, or `fallback` once none is left.
    func take<Element>(_ fallback: Element) -> Element where Value == [Element] { storage.withLock { $0.isEmpty ? fallback : $0.removeFirst() } }
}
private func pty(_ id: String = "pty_1", title: String = "Terminal 1", status: String = "running", exitCode: Int? = nil) -> JSONValue {
    var raw: JSONValue = .object(["id": .string(id), "title": .string(title), "command": .string("/bin/bash"), "args": .array([.string("-l")]),
                                  "cwd": .string("/w"), "status": .string(status), "pid": .integer(7)])
    if let exitCode { raw.set("exitCode", .integer(Int64(exitCode))) }
    return raw
}
private func located(_ data: JSONValue) -> JSONValue { .object(["location": .object(["directory": .string("/w")]), "data": data]) }
struct ShellPage: Sendable { var body: JSONValue; var status = 200 }
@MainActor private func terminalStore(_ log: TerminalRequests, time: SyncTime = SyncTime(), cache: CacheStore? = nil,
                                      respond: @escaping @Sendable (URLRequest) async -> (Int, JSONValue)) -> ReadStore {
    ReadStore(serverID: "s", cache: cache, clock: time.clock, client: {
        APIClient(baseURL: URL(string: "http://127.0.0.1:4096")!, credential: .password("secret"), transport: TerminalTransport(log: log, respond: respond))
    })
}
/// The fake clock's date, which saved points carry.
private let syncDate = Date(timeIntervalSince1970: 1_790_000_000)
private func yields() async { for _ in 0..<50 { await Task.yield() } }

@Test @MainActor func resizeIsSentAtOnceThenCoalescedEvery100Milliseconds() async {
    let time = SyncTime(), log = TerminalRequests()
    let store = terminalStore(log, time: time) { _ in (200, located(pty())) }
    let session = store.terminals(directory: "/w").session("pty_1")
    session.resized(cols: 80, rows: 24)
    await settle { await log.count("PUT", "/api/pty/pty_1") == 1 }
    session.resized(cols: 100, rows: 30); session.resized(cols: 120, rows: 40)
    await yields(); await time.test.advance(by: .milliseconds(99)); await yields()
    #expect(await log.count("PUT", "/api/pty/pty_1") == 1)
    await time.test.advance(by: .milliseconds(1))
    await settle { await log.count("PUT", "/api/pty/pty_1") == 2 }
    #expect(await log.last("PUT", "/api/pty/pty_1") == .object(["size": .object(["cols": .integer(120), "rows": .integer(40)])]), "Only the latest size")
    session.resized(cols: 120, rows: 40)
    await yields(); await time.test.advance(by: .milliseconds(500)); await yields()
    #expect(await log.count("PUT", "/api/pty/pty_1") == 2, "An unchanged size is not sent")
    session.resized(cols: 120, rows: 40, force: true)
    await settle { await log.count("PUT", "/api/pty/pty_1") == 3 }
}

@Test @MainActor func sessionRestoresTheScreenThenResumesFromItsCursor() async throws {
    let writer = try PersistenceWriter(), log = TerminalRequests(), sockets = FakeSockets()
    try await writer.saveTerminal(TerminalResume(serverID: "s", ptyID: "pty_1", directory: "/w", cursor: 10, cols: 80, rows: 24, screen: "SCREEN", updated: syncDate))
    let store = terminalStore(log, cache: CacheStore(writer: writer)) { _ in (200, located(pty())) }
    store.webSockets = sockets
    let session = store.terminals(directory: "/w").session("pty_1"), engine = FakeEngine()
    await session.attach(engine)
    #expect(engine.restored == ["SCREEN"])
    await settle { sockets.opened.count == 1 }
    let socket = try #require(sockets.opened.first)
    #expect(socket.cursor == "10" && socket.request.url?.scheme == "ws")
    #expect(socket.request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    socket.continuation.yield(.opened)
    socket.continuation.yield(.frame(.output("abc")))
    socket.continuation.yield(.frame(.control(cursor: 13)))
    await settle { engine.fed == ["abc"] && session.link.cursor == 13 }
    await settle { (try? await writer.terminal(serverID: "s", ptyID: "pty_1", now: syncDate))?.cursor == 13 }
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: syncDate)?.screen == "SCREENabc", "The saved screen matches the saved cursor")
    socket.continuation.yield(.frame(.output("😀")))
    await settle { session.link.cursor == 15 }
    // Input: a latched Ctrl, and an arrow in application cursor mode.
    session.toggle(.control); session.type("c")
    engine.applicationCursor = true; session.press(.up)
    session.send(Array("ls\r".utf8))
    await settle { socket.sent == ["\u{3}", "\u{1B}OA", "ls\r"] }
    #expect(session.latch.latched.isEmpty)
}

@Test @MainActor func outputTheBufferNoLongerHoldsIsReported() async throws {
    let writer = try PersistenceWriter(), log = TerminalRequests(), sockets = FakeSockets()
    try await writer.saveTerminal(TerminalResume(serverID: "s", ptyID: "pty_1", directory: "/w", cursor: 100, cols: 80, rows: 24, screen: "OLD", updated: syncDate))
    let store = terminalStore(log, cache: CacheStore(writer: writer)) { _ in (200, located(pty())) }
    store.webSockets = sockets
    let session = store.terminals(directory: "/w").session("pty_1"), engine = FakeEngine()
    await session.attach(engine)
    await settle { sockets.opened.count == 1 }
    let socket = try #require(sockets.opened.first)
    socket.continuation.yield(.opened); socket.continuation.yield(.frame(.output("zz"))); socket.continuation.yield(.frame(.control(cursor: 5_000)))
    await settle { session.gap == .lost(units: 4_898) }
    #expect(engine.resets == 1 && engine.fed == ["zz"], "The screen restarts from what the server kept")
}

@Test @MainActor func aClosedSocketShowsTheExitCode() async throws {
    let log = TerminalRequests(), sockets = FakeSockets()
    let exited = Shared(false)
    let store = terminalStore(log) { request in
        request.url?.path == "/api/pty/pty_1" && request.httpMethod == "GET" && exited.value ? (200, located(pty(status: "exited", exitCode: 3))) : (200, located(pty()))
    }
    store.webSockets = sockets
    let session = store.terminals(directory: "/w").session("pty_1"), engine = FakeEngine()
    await session.attach(engine)
    await settle { sockets.opened.count == 1 }
    let socket = try #require(sockets.opened.first)
    socket.continuation.yield(.opened); socket.continuation.yield(.frame(.control(cursor: 0))); socket.continuation.yield(.frame(.output("bye\r\n")))
    exited.set(true)
    socket.continuation.yield(.closed(code: 1000, reason: nil, httpStatus: nil))
    await settle { session.link.phase == .exited(code: 3) }
    #expect(session.gap == nil, "Every byte arrived before the normal close")
    #expect(sockets.opened.count == 1, "An exited terminal is not reconnected")
}

@Test @MainActor func aLostSocketBacksOffAndAGoneTerminalLeavesTheList() async throws {
    let time = SyncTime(), log = TerminalRequests(), sockets = FakeSockets(), gone = Shared(false)
    let writer = try PersistenceWriter()
    try await writer.saveTerminal(TerminalResume(serverID: "s", ptyID: "pty_1", directory: "/w", cursor: 3, cols: 80, rows: 24, screen: "S", updated: syncDate))
    let store = terminalStore(log, time: time, cache: CacheStore(writer: writer)) { request in
        if request.url?.path == "/api/pty" { return (200, located(.array([pty()]))) }
        if request.url?.path == "/api/config/shell" { return (200, .array([])) }
        return gone.value ? (404, .object(["_tag": .string("PtyNotFoundError")])) : (200, located(pty()))
    }
    store.webSockets = sockets
    let list = store.terminals(directory: "/w")
    list.refresh()
    await settle { list.terminals.count == 1 }
    let session = list.session("pty_1")
    await session.attach(FakeEngine())
    await settle { sockets.opened.count == 1 }
    sockets.opened[0].continuation.yield(.closed(code: nil, reason: nil, httpStatus: nil))
    await settle { session.link.phase == .waiting }
    await yields(); await time.test.advance(by: .milliseconds(250))
    await settle { sockets.opened.count == 2 }
    #expect(sockets.opened[1].cursor == "3", "Reconnects from the saved cursor after checking the terminal")
    gone.set(true)
    sockets.opened[1].continuation.yield(.closed(code: nil, reason: nil, httpStatus: nil))
    await yields(); await time.test.advance(by: .milliseconds(500))
    await settle { list.terminals.isEmpty && session.removedFromServer }
    await settle { (try? await writer.terminal(serverID: "s", ptyID: "pty_1", now: syncDate)) == nil }
}

@Test @MainActor func anExitedTerminalShowsItsLastScreenWithoutConnecting() async throws {
    let writer = try PersistenceWriter(), log = TerminalRequests(), sockets = FakeSockets()
    try await writer.saveTerminal(TerminalResume(serverID: "s", ptyID: "pty_1", directory: "/w", cursor: 4, cols: 80, rows: 24, screen: "LAST", updated: syncDate))
    let store = terminalStore(log, cache: CacheStore(writer: writer)) { request in
        request.url?.path == "/api/pty" ? (200, located(.array([pty(status: "exited", exitCode: 1)]))) : (200, .array([]))
    }
    store.webSockets = sockets
    let list = store.terminals(directory: "/w")
    list.refresh()
    await settle { list.terminals.first?.status == .exited }
    let session = list.session("pty_1"), engine = FakeEngine()
    await session.attach(engine)
    #expect(engine.restored == ["LAST"] && session.link.phase == .exited(code: 1) && session.gap == .exitedWhileAway)
    await yields()
    #expect(sockets.opened.isEmpty)
}

@Test @MainActor func ptyEventsAndActionsKeepTheListCurrent() async throws {
    let log = TerminalRequests()
    let store = terminalStore(log) { request in
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/api/pty"): (200, located(pty("pty_2", title: "Terminal 2")))
        case ("DELETE", _): (204, .null)
        case ("PUT", _): (200, located(pty(title: "Build")))
        default: (200, .array([]))
        }
    }
    let list = store.terminals(directory: "/w")
    list.handle(type: "pty.created", payload: .object(["info": pty()]))
    #expect(list.terminals.map(\.id) == ["pty_1"])
    list.create(shell: ShellOption(raw: .object(["path": .string("/bin/zsh"), "name": .string("zsh")])))
    await settle { list.terminals.count == 2 && list.selected == "pty_2" }
    #expect(await log.last("POST", "/api/pty") == .object(["command": .string("/bin/zsh"), "title": .string("Terminal 2")]))
    list.rename("pty_1", title: " Build ")
    await settle { list.info("pty_1")?.title == "Build" }
    #expect(await log.last("PUT", "/api/pty/pty_1") == .object(["title": .string("Build")]))
    list.handle(type: "pty.exited", payload: .object(["id": .string("pty_1"), "exitCode": .integer(2)]))
    #expect(list.info("pty_1")?.status == .exited && list.info("pty_1")?.exitCode == 2 && list.hasExited)
    list.clearExited()
    await settle { list.terminals.map(\.id) == ["pty_2"] }
    #expect(await log.count("DELETE", "/api/pty/pty_1") == 1)
    #expect(await log.count("DELETE", "/api/pty/pty_2") == 0)
    list.handle(type: "pty.deleted", payload: .object(["id": .string("pty_2")]))
    #expect(list.terminals.isEmpty && list.selected == nil)
}

@Test @MainActor func runACommandPagesItsOutputUntilItEnds() async throws {
    let time = SyncTime(), log = TerminalRequests()
    let pages = Shared<[ShellPage]>([.init(body: .object(["output": .string("one\n"), "cursor": .integer(4), "size": .integer(4), "truncated": .bool(false)])),
                                     .init(body: .object(["output": .string("two\n"), "cursor": .integer(8), "size": .integer(8), "truncated": .bool(false)])),
                                     .init(body: .object(["output": .string(""), "cursor": .integer(8), "size": .integer(8), "truncated": .bool(false)]))])
    let shell: JSONValue = .object(["id": .string("sh_1"), "status": .string("running"), "command": .string("count"), "cwd": .string("/w"),
                                    "shell": .string("/bin/bash"), "file": .string("/f"), "metadata": .object([:]), "time": .object(["started": .integer(1)])])
    let store = terminalStore(log, time: time) { request in
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/api/shell"), ("GET", "/api/shell/sh_1"): return (200, located(shell))
        case ("GET", "/api/shell/sh_1/output"):
            let page = pages.take(ShellPage(body: .object(["_tag": .string("ShellNotFoundError")]), status: 404))
            return (page.status, page.status == 200 ? located(page.body) : page.body)
        default: return (200, located(.array([])))
        }
    }
    let model = store.shellRuns(directory: "/w"), engine = FakeEngine()
    model.attach(engine)
    model.run("count")
    await settle { engine.fed == ["one\r\n"] }
    #expect(model.isRunning)
    await yields(); await time.test.advance(by: .seconds(1))
    await settle { engine.fed == ["one\r\n", "two\r\n"] }
    model.handle(type: "shell.exited", payload: .object(["id": .string("sh_1"), "status": .string("exited"), "exit": .integer(0)]))
    #expect(!model.isRunning && model.shell?.status == "exited")
    await yields(); await time.test.advance(by: .seconds(1))
    await settle { await log.count("GET", "/api/shell/sh_1/output") == 3 }
    await yields(); await time.test.advance(by: .seconds(5)); await yields()
    #expect(await log.count("GET", "/api/shell/sh_1/output") == 3, "Paging stops once the ended command is caught up")
    #expect(model.running.isEmpty)
    // A new view replays what was paged.
    let again = FakeEngine()
    model.attach(again)
    #expect(again.fed == ["one\r\n", "two\r\n"])
}

@Test @MainActor func stoppingACommandKeepsItsOutput() async throws {
    let log = TerminalRequests()
    let shell: JSONValue = .object(["id": .string("sh_2"), "status": .string("running"), "command": .string("sleep 60"), "cwd": .string("/w"),
                                    "shell": .string("/bin/bash"), "file": .string("/f"), "metadata": .object([:]), "time": .object(["started": .integer(1)])])
    let store = terminalStore(log) { request in
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/api/shell"): (200, located(shell))
        case ("DELETE", "/api/shell/sh_2"): (204, .null)
        case ("GET", "/api/shell/sh_2/output"): (200, located(.object(["output": .string("tick\n"), "cursor": .integer(5), "size": .integer(5), "truncated": .bool(false)])))
        default: (200, located(.array([])))
        }
    }
    let model = store.shellRuns(directory: "/w"), engine = FakeEngine()
    model.attach(engine)
    model.run("sleep 60")
    await settle { engine.fed == ["tick\r\n"] }
    model.stop()
    await settle { model.shell?.status == "killed" }
    #expect(await log.count("DELETE", "/api/shell/sh_2") == 1)
    #expect(engine.fed == ["tick\r\n"] && !model.isRunning)
}

@Test @MainActor func anUpgradeRefusedBeforeOpeningRetriesOnceWithATicket() async throws {
    let log = TerminalRequests(), sockets = FakeSockets()
    let store = terminalStore(log) { request in
        request.url?.path.hasSuffix("/connect-token") == true ? (200, located(.object(["ticket": .string("t1"), "expires_in": .integer(60)]))) : (200, located(pty()))
    }
    store.webSockets = sockets
    let session = store.terminals(directory: "/w").session("pty_1")
    await session.attach(FakeEngine())
    await settle { sockets.opened.count == 1 }
    // Dropped without a status, as the server does when the Authorization header never arrived.
    sockets.opened[0].continuation.yield(.closed(code: nil, reason: nil, httpStatus: nil))
    await settle { sockets.opened.count == 2 }
    let retry = sockets.opened[1].request
    #expect(retry.value(forHTTPHeaderField: "Authorization") == nil, "A ticketed upgrade carries no credentials")
    #expect(URLComponents(url: try #require(retry.url), resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "ticket" && $0.value == "t1" } == true)
    #expect(await log.count("POST", "/api/pty/pty_1/connect-token") == 1)
    #expect(session.ticketReason != nil)
    sockets.opened[1].continuation.yield(.closed(code: nil, reason: nil, httpStatus: nil))
    await yields()
    #expect(sockets.opened.count == 2, "Only one ticketed retry; the next attempt waits for the backoff")
}

@Test @MainActor func pagingResumesAfterTheBackgroundAndReadsTheLastPage() async throws {
    let time = SyncTime(), log = TerminalRequests()
    let pages = Shared<[ShellPage]>([.init(body: .object(["output": .string("one\n"), "cursor": .integer(4), "size": .integer(4), "truncated": .bool(false)])),
                                     .init(body: .object(["output": .string("two\n"), "cursor": .integer(8), "size": .integer(8), "truncated": .bool(false)]))])
    let shell: JSONValue = .object(["id": .string("sh_3"), "status": .string("running"), "command": .string("count"), "cwd": .string("/w"),
                                    "shell": .string("/bin/bash"), "file": .string("/f"), "metadata": .object([:]), "time": .object(["started": .integer(1)])])
    let store = terminalStore(log, time: time) { request in
        switch (request.httpMethod, request.url?.path) {
        case ("POST", "/api/shell"), ("GET", "/api/shell/sh_3"): return (200, located(shell))
        case ("GET", "/api/shell/sh_3/output"):
            return (200, located(pages.take(ShellPage(body: .object(["output": .string(""), "cursor": .integer(8), "size": .integer(8), "truncated": .bool(false)]))).body))
        default: return (200, located(.array([])))
        }
    }
    let model = store.shellRuns(directory: "/w"), engine = FakeEngine()
    model.attach(engine)
    model.run("count")
    await settle { engine.fed == ["one\r\n"] }
    // The app goes to the background: paging stops. The command ends meanwhile.
    model.cancel()
    model.handle(type: "shell.exited", payload: .object(["id": .string("sh_3"), "status": .string("exited"), "exit": .integer(0)]))
    await settle { engine.fed == ["one\r\n", "two\r\n"] }
    #expect(!model.isRunning)
    // Paging finished, so showing the sheet again fetches nothing more.
    let fetched = await log.count("GET", "/api/shell/sh_3/output")
    model.appear()
    await yields(); await time.test.advance(by: .seconds(3)); await yields()
    #expect(await log.count("GET", "/api/shell/sh_3/output") == fetched)
}

@Test @MainActor func sizesReachTheServerInOrderWithTheNewestLast() async throws {
    let log = TerminalRequests(), first = Shared(true)
    let store = terminalStore(log) { request in
        // The first size request is slow; a later one sent beside it would overtake it.
        if request.httpMethod == "PUT", first.value { first.set(false); try? await Task.sleep(for: .milliseconds(200)) }
        return (200, located(pty()))
    }
    let session = store.terminals(directory: "/w").session("pty_1")
    session.resized(cols: 80, rows: 24)
    await settle { await log.count("PUT", "/api/pty/pty_1") == 1 }
    session.resized(cols: 100, rows: 30, force: true)
    session.resized(cols: 120, rows: 40, force: true)
    for _ in 0..<100 where await log.count("PUT", "/api/pty/pty_1") < 2 { try await Task.sleep(for: .milliseconds(20)) }
    try await Task.sleep(for: .milliseconds(300))
    #expect(await log.count("PUT", "/api/pty/pty_1") == 2, "The size in between was never sent")
    #expect(await log.last("PUT", "/api/pty/pty_1") == .object(["size": .object(["cols": .integer(120), "rows": .integer(40)])]))
}

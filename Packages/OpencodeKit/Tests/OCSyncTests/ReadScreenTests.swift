import Foundation
import Clocks
import Testing
import OCModels
import OCFoundation
import OCShared
import OCNetworking
import OCPersistence
@testable import OCSync

@Test @MainActor func unreadChildFailuresRollUpAndClearWithViewEvent() async throws {
    let store = ReadStore(serverID: "server")
    store.seed(info: readInfo())
    var child = readInfo("child")
    child.raw.set("parentID", .string("s")); child.raw.set("outcome", .string("failed"))
    child.raw.set(["time", "idle"], .integer(100)); child.raw.set(["time", "viewed"], .integer(0))
    store.seed(info: child)
    #expect(store.sessions["s"]?.attention == 1)
    #expect(store.sessions["child"]?.attention == 1)
    store.apply(try readEvent("session.viewed", session: "child", seq: 1, data: ["idle": .integer(100)]))
    #expect(store.sessions["s"]?.attention == 0)
    await store.stop()
}
@Test @MainActor func localPinHideSurviveReloadAndAreIsolatedByServer() async throws {
    let writer = try PersistenceWriter(), cache = CacheStore(writer: writer)
    let store = ReadStore(serverID: "server", cache: cache)
    try await store.setLocalMeta(.init(pinned: true, hidden: true), sessionID: "s")
    let reopened = ReadStore(serverID: "server", cache: cache)
    try await reopened.loadCache()
    #expect(reopened.localMeta["s"] == .init(pinned: true, hidden: true))
    #expect(try await writer.sessionLocalMeta(serverID: "other").isEmpty)
    await store.stop(); await reopened.stop()
}
@Test @MainActor func markReadUsesCapturedIdleAndPreservesNewUnreadTurn() async throws {
    let store = ReadStore(serverID: "server")
    var info = readInfo(); info.raw.set(["time", "idle"], .integer(100)); store.seed(info: info)
    store.client = { readAPI { request in
        #expect(request.url?.path == "/api/session/s/view")
        #expect(request.httpMethod == "POST")
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
        #expect(body["idle"]?.wireNumber == 100)
        await MainActor.run { store.sessions["s"]?.info.raw.set(["time", "idle"], .integer(200)) }
        return .object([:])
    } }
    try await store.markViewed("s")
    #expect(store.sessions["s"]?.info.time.viewed == 100)
    #expect(store.sessions["s"]?.unread == true)
    await store.stop()
}
@Test func deepLinksRejectCredentialsAndInvalidRoutes() throws {
    let id = UUID().uuidString
    let url = try #require(URL(string: "opencodeios://server/\(id)/session/ses_123/request/req_123"))
    let link = try #require(DeepLink(url: url))
    #expect(link.sessionID == "ses_123"); #expect(link.requestID == "req_123")
    for path in ["opencodeios://user:secret@server/\(id)", "opencodeios://server/\(id)?password=secret", "opencodeios://server/\(id)/session/a%2Fb", "opencodeios://server/\(id)/session/..", "opencodeios://server/invalid", "https://server/\(id)"] {
        #expect(DeepLink(url: try #require(URL(string: path))) == nil)
    }
}

private actor ShellReadLog {
    var calls = 0
    func record() { calls += 1 }
}
@Test @MainActor func shellPollingStopsWhenRowDisappearsAndCompletedRowsFetchOnce() async throws {
    let time = SyncTime(), log = ShellReadLog(), store = ReadStore(serverID: "server", clock: time.clock)
    store.client = { readAPI { request in
        #expect(request.url?.path == "/api/shell/sh/output")
        await log.record()
        return .object(["location": .object(["directory": .string("/work")]), "data": .object(["output": .string("line\n"), "cursor": .integer(5), "size": .integer(5)])])
    } }
    let shell = ShellOutputModel()
    shell.start(store: store, shellID: "sh", directory: "/work", running: true)
    await settle { !shell.output.isEmpty }
    #expect(await log.calls == 1)
    await time.test.advance(by: .milliseconds(999))
    #expect(await log.calls == 1)
    await time.test.advance(by: .milliseconds(1))
    await settle { shell.output.count > 5 }
    #expect(await log.calls == 2)
    shell.stop()
    await time.test.advance(by: .seconds(5))
    #expect(await log.calls == 2)
    shell.start(store: store, shellID: "sh", directory: "/work", running: false)
    await settle { shell.output.count > 10 }
    await time.test.advance(by: .seconds(5))
    #expect(await log.calls == 3)
    shell.stop(); await store.stop()
}

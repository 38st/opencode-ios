import Foundation
import Testing
import OCFoundation
import OCModels
import OCPersistence
import OCShared
@testable import OCSync

private let server = ServerID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!)
private func link(_ session: String? = nil, request: String? = nil) throws -> DeepLink {
    let url = try #require(DeepLink.url(serverID: server.rawValue, sessionID: session, requestID: request))
    return try #require(DeepLink(url: url))
}
private func path(_ ids: String...) -> [SessionRef] { ids.map { SessionRef(serverID: server, sessionID: $0) } }

@MainActor private final class PhaseLog {
    var phases: [AppScenePhase] = []
}

@Test @MainActor func linksGoToTheWindowShowingTheSession() throws {
    let windows = WindowCoordinator(), a = UUID(), b = UUID()
    var activated: [UUID] = []
    windows.register(a) { activated.append(a) }; windows.register(b) { activated.append(b) }
    windows.update(a, path: path("ses_a")); windows.update(b, path: path("ses_b", "ses_child"))
    windows.focused(a)
    #expect(windows.route(try link("ses_child"), from: a) == b, "A child shown deeper in a window's path")
    #expect(windows.take(b)?.sessionID == "ses_child" && windows.take(b) == nil, "A route is taken once")
    #expect(activated == [b], "The window comes forward")
    // A child that no window shows goes to the window showing its root.
    #expect(windows.route(try link("ses_other_child"), root: SessionRef(serverID: server, sessionID: "ses_b")) == b)
    // Otherwise the key window takes it, without being activated again.
    activated = []
    #expect(windows.route(try link("ses_new", request: "per_1"), from: b) == a)
    #expect(windows.take(a)?.requestID == "per_1" && activated.isEmpty)
    #expect(windows.route(try link()) == a, "A server-only link goes to the key window")
}

@Test @MainActor func theWindowMostRecentlyInUseTakesLinks() throws {
    let windows = WindowCoordinator(), a = UUID(), b = UUID()
    windows.register(a) {}; windows.register(b) {}
    #expect(windows.current == b, "The newest window, until one is used")
    windows.update(a, phase: .active); windows.update(b, phase: .active)
    #expect(windows.current == b)
    // Every window stays key in its own scene, so coming forward shows in the phase, and use in touches.
    windows.update(a, phase: .background); windows.update(a, phase: .active)
    #expect(windows.current == a && windows.isKey(a) && !windows.isKey(b))
    windows.update(a, phase: .active)
    #expect(windows.current == a, "An unchanged phase is not a window coming forward")
    windows.focused(b)
    #expect(windows.isKey(b), "A touch in a window beside another")
    windows.unregister(b)
    #expect(windows.current == a, "Closing a window leaves the others")
    #expect(windows.route(try link("ses_x")) == a)
    windows.unregister(a)
    #expect(windows.route(try link("ses_x")) == nil)
}

@Test @MainActor func oneBackgroundWindowDoesNotPauseTheOthers() async {
    let windows = WindowCoordinator(), log = PhaseLog(), a = UUID(), b = UUID()
    windows.applyPhase = { log.phases.append($0) }
    windows.register(a) {}; windows.register(b) {}
    windows.update(a, phase: .active)
    windows.update(b, phase: .active)
    windows.update(b, phase: .background)
    #expect(windows.phase == .active)
    windows.update(a, phase: .inactive)
    windows.update(a, phase: .background)
    #expect(windows.phase == .background)
    windows.update(b, phase: .active)
    await settle { log.phases.count == 4 }
    #expect(log.phases == [.active, .inactive, .background, .active], "Only changes of the app-wide phase reach the registry")
    windows.unregister(b)
    await settle { log.phases.count == 5 }
    #expect(log.phases.last == .background)
}

@Test @MainActor func aWindowAlreadyShowingASessionIsFound() {
    let windows = WindowCoordinator(), a = UUID()
    #expect(windows.register(a) {})
    #expect(!windows.register(UUID()) {}, "Only the first window of the process")
    windows.update(a, path: path("ses_root", "ses_child"))
    #expect(windows.window(showing: SessionRef(serverID: server, sessionID: "ses_root", requestID: "per_2")) == a)
    #expect(windows.window(showing: SessionRef(serverID: server, sessionID: "ses_child")) == a)
    #expect(windows.window(showing: SessionRef(serverID: ServerID(), sessionID: "ses_root")) == nil)
    #expect(windows.diagnostics.contains("path=ses_root,ses_child"))
}

@MainActor private final class Counter { var made = 0 }

@Test @MainActor func scenesStartingTogetherShareOneValue() async throws {
    let counter = Counter()
    let once = SharedOnce<UUID> { counter.made += 1; try await Task.sleep(for: .milliseconds(20)); return UUID() }
    async let first = once.value(), second = once.value(), third = once.value()
    let values = try await [first, second, third]
    #expect(Set(values).count == 1 && counter.made == 1)
    struct Failure: Error {}
    let attempts = Counter()
    let failing = SharedOnce<Int> { attempts.made += 1; if attempts.made == 1 { throw Failure() }; return attempts.made }
    await #expect(throws: Failure.self) { try await failing.value() }
    #expect(try await failing.value() == 2, "A failure is not kept")
}

@Test @MainActor func aSessionOpenInTwoWindowsStaysOpenUntilBothClose() async throws {
    let store = ReadStore(serverID: "server")
    store.seed(info: readInfo(), messages: [])
    try await store.open("s"); try await store.open("s")
    store.close("s")
    #expect(store.openSessions.contains("s"))
    store.close("s")
    #expect(!store.openSessions.contains("s"))
    store.close("s")
    #expect(!store.openSessions.contains("s") && store.openCounts["s"] == nil)
}

@Test @MainActor func droppedTextAndMentionsGoInAtTheCursor() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try PersistenceWriter(), store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), drafts: DraftStore(writer: writer, filesRoot: root))
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/project")
    await composer.load()
    composer.setText(AttributedString("😀 hello"))
    // The emoji is two UTF-16 units: offset 1 is inside it and moves to its end.
    #expect(composer.insertText("+", atUTF16: 1) == 3)
    #expect(String(composer.text.characters) == "😀+ hello")
    #expect(composer.insertText("!", atUTF16: 99) == 10)
    #expect(String(composer.text.characters) == "😀+ hello!")
    let after = composer.mentionFile("src/app.swift", atUTF16: 3, focus: false)
    #expect(String(composer.text.characters) == "😀+ @app.swift  hello!")
    #expect(after == 15)
    let mention = composer.text.runs.first { $0[MentionAttribute.self] != nil }
    #expect(mention?[MentionAttribute.self]?.value == "/project/src/app.swift")
    // A drop inside a mention lands after it, never splitting the token.
    #expect(composer.insertText("x", atUTF16: 6) == 15)
    #expect(String(composer.text.characters) == "😀+ @app.swiftx  hello!")
    #expect(composer.text.runs.filter { $0[MentionAttribute.self] != nil }.map { String(composer.text[$0.range].characters) } == ["@app.swift"])
    composer.mentionFile("/abs/readme.md", focus: false)
    #expect(String(composer.text.characters).hasSuffix("hello! @readme.md "), "Without an offset the mention goes at the end")
    await store.stop()
}

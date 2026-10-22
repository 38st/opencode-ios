import Foundation
import Observation
import Synchronization
import Testing
import OCModels
import OCFoundation
import OCPersistence
import OCNetworking
@testable import OCSync

@Test @MainActor func commentsSurviveDraftRelaunchDurableAdmissionAndRestore() async throws {
    let writer = try PersistenceWriter(), cache = CacheStore(writer: writer)
    let store = ReadStore(serverID: "server", cache: cache)
    store.seed(info: readInfo(), messages: [])
    let composer = store.composer(sessionID: "s", directory: "/project")
    await composer.load()
    composer.addComment(.init(file: "a.swift", selection: .init(start: 12, end: 14), comment: "Please simplify", preview: "let a = 1"))
    #expect(!composer.blank)
    try await composer.flush()
    let relaunched = ReadStore(serverID: "server", cache: cache)
    relaunched.seed(info: readInfo(), messages: [])
    let restored = relaunched.composer(sessionID: "s", directory: "/project")
    await restored.load()
    #expect(restored.comments == composer.comments)
    restored.submit(preference: .steer)
    while restored.busy { await Task.yield() }
    #expect(restored.comments.isEmpty)
    let entry = try #require(await OutboxStore(writer: writer).entries(serverID: "server").first)
    let bytes = entry.body
    let raw = try JSONDecoder().decode(JSONValue.self, from: bytes)
    #expect(raw["text"]?.stringValue == "The user made the following comment regarding lines 12 through 14 of a.swift: Please simplify")
    _ = try await relaunched.restoreInput(.init(raw: raw), sessionID: "s")
    #expect(restored.comments.count == 1 && restored.comments[0].comment == "Please simplify")
    #expect(try await OutboxStore(writer: writer).entries(serverID: "server").first?.body == bytes)
    // The server replaces uri with source.uri and resolved bytes; those bytes must not become inline attachments.
    var stored = raw
    stored.set("files", .array([.object(["data": .string("dGV4dA=="), "mime": .string("text/plain"), "source": .object(["type": .string("uri"), "uri": .string("file:///project/a.swift?start=12&end=14")])])]))
    _ = try await relaunched.restoreInput(.init(raw: stored), sessionID: "s", append: true)
    #expect(restored.comments.count == 2 && restored.attachments.isEmpty)
    await store.stop(); await relaunched.stop()
}
@Test func reviewPersistenceDoesNotChangeOtherLocalMetadataOrOutbox() async throws {
    let writer = try PersistenceWriter()
    var state = ReviewState(); state.source = .turn("msg_turn"); state.selectedFile = "a"; state.openFiles = ["a", "b"]
    try await writer.saveReviewState(serverID: "server", sessionID: "s", state: state, reviewed: ["digest"])
    let loaded = try await writer.reviewState(serverID: "server", sessionID: "s")
    #expect(loaded.0 == state && loaded.1 == ["digest"])
}
@Test @MainActor func reviewFallbackRetainsChoiceAndRetriesTruncatedPatch() async throws {
    let writer = try PersistenceWriter()
    var state = ReviewState(); state.source = .branch
    try await writer.saveReviewState(serverID: "server", sessionID: "s", state: state, reviewed: [])
    let store = ReadStore(serverID: "server", cache: CacheStore(writer: writer), client: {
        readAPI { request in
            switch request.url?.path {
            case "/api/location": return .object(["directory": .string("/project/sub"), "project": .object(["directory": .string("/project")])])
            case "/api/vcs": return .object(["location": .object(["directory": .string("/project/sub")]), "data": .object(["provider": .string("git"), "branch": .object(["current": .string("main"), "default": .string("main")])])])
            default:
                let retry = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "context", value: "3")) == true
                return .object(["location": .object(["directory": .string("/project/sub")]), "data": .array([.object(["file": .string("sub/a.swift"), "patch": .string(retry ? "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n" : "--- a\n+++ b\n"), "additions": .integer(1), "deletions": .integer(1)])])])
            }
        }
    })
    let review = store.review(sessionID: "s", directory: "/project/sub")
    review.appear()
    for _ in 0..<10000 { if review.loaded { break }; await Task.yield() }
    #expect(review.source == .working && review.state.source == .branch)
    let file = try #require(review.files.first)
    #expect(file.patch.contains("@@") && file["bounded"]?.boolValue == true)
    #expect(review.path(file.file)?.path == "a.swift")
    review.mark(file, reviewed: true); #expect(review.isReviewed(file))
    var changed = file; changed.raw.set("patch", .string("different")); #expect(!review.isReviewed(changed))
    review.disappear(); await store.stop()
}

@Test @MainActor func commandsPreserveCommentsAndFailedPromptKeepsThem() async throws {
    for shell in [false, true] {
        let trace = CommentCommandTrace(), writer = try PersistenceWriter()
        let client = readAPI { request in await trace.receive(request) }
        let store = ReadStore(serverID: "comments", cache: CacheStore(writer: writer), client: { client })
        var info = readInfo(); info["agent"] = .string("build")
        store.seed(info: info, messages: [])
        let composer = store.composer(sessionID: "s", directory: "/project")
        await composer.load()
        composer.catalog.commands.seed(.array([.object(["name": .string("review")])]))
        let comment = LineComment(file: "a.swift", selection: .init(start: 2), comment: "Keep this for the prompt")
        composer.addComment(comment); composer.shellMode(shell)
        composer.setText(AttributedString(shell ? "echo fixture" : "/review explain"))
        composer.submit(preference: .steer)
        while composer.busy { await Task.yield() }
        #expect(composer.error == nil)
        #expect(composer.comments == [comment])
        #expect(try await store.drafts?.load(serverID: "comments", sessionID: "s")?.comments == [comment])
        let requests = await trace.requests
        #expect(requests.contains { $0.0.hasSuffix(shell ? "/shell" : "/command") })
        #expect(requests.allSatisfy { !$0.1.contains("Keep this for the prompt") && !$0.1.contains("a.swift") })
        store.sessions.removeValue(forKey: "s")
        composer.setText(AttributedString("Next prompt")); composer.submit(preference: .steer)
        while composer.busy { await Task.yield() }
        #expect(composer.comments == [comment] && composer.error != nil)
        await store.stop()
    }
}
private actor CommentCommandTrace {
    var requests: [(String, String)] = []
    func receive(_ request: URLRequest) -> JSONValue {
        requests.append((request.url?.path ?? "", String(decoding: request.httpBody ?? Data(), as: UTF8.self)))
        return .object(["data": .object([:])])
    }
}

@Test @MainActor func reviewRefreshIsDebouncedVisibleOnlyAndRetainsOfflineContent() async throws {
    let trace = ReviewRefreshTrace()
    let client = readAPI { try await trace.respond($0) }
    let store = ReadStore(serverID: "refresh", client: { client })
    let review = store.review(sessionID: "s", directory: "/p")
    review.appear()
    try await reviewEventually { review.loaded }
    let first = review.files
    #expect(await trace.diffCount == 1)
    for type in ["session.step.ended", "session.idle", "vcs.branch.updated", "session.revert.staged", "worktree.updated"] {
        let header = EventHeader(id: UUID().uuidString, type: type)
        let payload: JSONValue = .object(["sessionID": .string("s")])
        let event: ServerEvent = switch type {
        case "session.step.ended": .sessionStepEnded(header, .init(raw: payload))
        case "session.idle": .sessionIdle(header, .init(raw: payload))
        case "vcs.branch.updated": .vcsBranchUpdated(header, .init(raw: payload))
        case "session.revert.staged": .sessionRevertStaged(header, .init(raw: payload))
        default: .worktreeUpdated(header, .init(raw: payload))
        }
        store.refreshReviewViews(event)
    }
    try await Task.sleep(for: .milliseconds(250))
    try await reviewEventually { !review.loading }
    #expect(await trace.diffCount == 2)
    review.disappear(); review.invalidate()
    try await Task.sleep(for: .milliseconds(200))
    #expect(await trace.diffCount == 2)
    await trace.offline()
    review.appear()
    try await reviewEventually { review.error != nil }
    #expect(review.files == first)
    review.disappear(); await store.stop()
}

@Test @MainActor func finishedTurnCacheRetriesFailuresAndRemembersAnInflightRefresh() async throws {
    let trace = ReviewRefreshTrace()
    let client = readAPI { try await trace.respond($0) }
    let store = ReadStore(serverID: "turn-cache", client: { client })
    let model = store.turnDiff(sessionID: "s", from: "msg_opening")
    await trace.offline(); model.load()
    try await reviewEventually { model.error != nil }
    await trace.online(); model.load(); model.load(force: true)
    try await reviewEventually { model.loaded && model.error == nil }
    try await Task.sleep(for: .milliseconds(50))
    #expect(await trace.diffCount == 2)
    model.load()
    try await Task.sleep(for: .milliseconds(50))
    #expect(await trace.diffCount == 2)
    #expect(await trace.from == "msg_opening")
    await store.stop()
}

@Test @MainActor func openingAndRefreshingReviewDoesNotInvalidateTheTimeline() async throws {
    let trace = ReviewRefreshTrace(), client = readAPI { try await trace.respond($0) }
    let store = ReadStore(serverID: "review-observation", client: { client })
    store.seed(info: readInfo(), messages: [])
    let invalidated = Mutex(false)
    withObservationTracking {
        _ = store.sessions["s"]?.transcript?.snapshot
        _ = store.sessions["s"]?.pending
        _ = store.sessions["s"]?.info
    } onChange: { invalidated.withLock { $0 = true } }
    let review = store.review(sessionID: "s", directory: "/p")
    review.appear()
    try await reviewEventually { review.loaded }
    review.expandAll(true)
    if let file = review.files.first { review.mark(file, reviewed: true) }
    review.refresh()
    for _ in 0..<300 { if await trace.diffCount == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
    try await reviewEventually { !review.loading }
    #expect(await trace.diffCount == 2)
    #expect(!invalidated.withLock { $0 })
    review.disappear(); await store.stop()
}

@MainActor private func reviewEventually(_ condition: () -> Bool) async throws {
    for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
    Issue.record("Review model did not settle")
}
private actor ReviewRefreshTrace {
    var diffCount = 0
    var from: String?
    private var failing = false
    func offline() { failing = true }
    func online() { failing = false }
    func respond(_ request: URLRequest) throws -> JSONValue {
        if failing { throw URLError(.notConnectedToInternet) }
        let location: JSONValue = .object(["directory": .string("/p")])
        switch request.url?.path {
        case "/api/location": return .object(["directory": .string("/p"), "project": .object(["directory": .string("/p")])])
        case "/api/vcs": return .object(["location": location, "data": .object(["provider": .string("git"), "branch": .object(["current": .string("main"), "default": .string("main")])])])
        default:
            diffCount += 1
            from = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "from" }?.value }
            return .object(["location": location, "data": .array([.object(["file": .string("a.swift"), "additions": .integer(1), "deletions": .integer(1), "patch": .string("@@ -1 +1 @@\n-old\n+new\n")])])])
        }
    }
}

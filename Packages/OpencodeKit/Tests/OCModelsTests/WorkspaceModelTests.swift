import Foundation
import Testing
import OCFoundation
import OCModels

private let first = ServerID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
private let second = ServerID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
private func session(_ id: String, _ title: String, project: String = "opencode", updated: Double, server: ServerID = first) -> SwitcherIndex.Session {
    .init(ref: SessionRef(serverID: server, sessionID: id), title: title, project: project, updated: updated)
}

@Test func switcherOpensWithTheDesktopDefaults() {
    let sessions = (1...7).map { session("ses_\($0)", "Session \($0)", updated: Double($0)) }
    let groups = SwitcherIndex.groups(query: "  ", commands: WorkspaceCommand.all, sessions: sessions, projects: [])
    #expect(groups.map(\.title) == ["Commands", "Recent sessions"])
    #expect(groups[0].entries.map(\.title) == ["New session", "Previous session", "Next session", "Toggle review"])
    #expect(groups[0].entries[0].shortcut == "⌘N")
    #expect(groups[1].entries.map(\.title) == ["Session 7", "Session 6", "Session 5", "Session 4", "Session 3"])
    // Disabled commands are left out; with none of the preferred ones, the first commands are shown.
    let fallback = SwitcherIndex.groups(query: "", commands: [.find, .stop], sessions: [], projects: [])
    #expect(fallback.map(\.title) == ["Commands"] && fallback[0].entries.map(\.title) == ["Find", "Stop"])
}

@Test func switcherRanksSessionsLikeHomeSearch() {
    let sessions = [session("ses_a", "Fix login flow", updated: 1), session("ses_b", "Polish the review panel", project: "ios", updated: 3),
                    session("ses_c", "Login copy", updated: 2, server: second), session("ses_d", "Lint", updated: 4)]
    let groups = SwitcherIndex.groups(query: "LOGIN", commands: [], sessions: sessions, projects: [])
    #expect(groups.map(\.title) == ["Sessions"])
    // Substring matches of the title and project first, newest first, from every server; then subsequence matches.
    #expect(groups[0].entries.map(\.title) == ["Login copy", "Fix login flow"])
    let fuzzy = SwitcherIndex.groups(query: "prp", commands: [], sessions: sessions, projects: [])
    #expect(fuzzy.first?.entries.map(\.title) == ["Polish the review panel"])
    let byProject = SwitcherIndex.groups(query: "ios", commands: [], sessions: sessions, projects: [])
    #expect(byProject.first?.entries.map(\.title) == ["Polish the review panel"])
    #expect(SwitcherIndex.groups(query: "zzz", commands: [], sessions: sessions, projects: []).isEmpty)
}

@Test func switcherPutsAnExactSessionIDFirst() {
    let id = "ses_0123456789abcdefghijkl"
    let sessions = [session("ses_other", "Mentions \(id)", updated: 9), session(id, "Untitled session", updated: 1)]
    let entries = SwitcherIndex.groups(query: id, commands: [], sessions: sessions, projects: []).first?.entries ?? []
    #expect(entries.map(\.id) == ["session:" + sessions[1].ref.id, "session:" + sessions[0].ref.id])
    #expect(SwitcherIndex.looksLikeSessionID(id) && !SwitcherIndex.looksLikeSessionID("ses_short") && !SwitcherIndex.looksLikeSessionID("msg_0123456789abcdefghijkl"))
}

@Test func switcherFindsCommandsAndProjects() {
    let projects = [SwitcherIndex.Project(filter: first.rawValue.uuidString + ":prj_1", name: "opencode-ios", path: "/Users/Shared/opencode-ios", server: "Studio")]
    let groups = SwitcherIndex.groups(query: "review", commands: [.toggleReview, .reviewNextApproval, .newSession], sessions: [], projects: projects)
    #expect(groups.first?.entries.map(\.title) == ["Toggle review", "Review next approval"])
    let project = SwitcherIndex.groups(query: "shared/open", commands: [], sessions: [], projects: projects)
    #expect(project.map(\.title) == ["Projects"] && project[0].entries.first?.kind == .project(projects[0].filter))
    #expect(SwitcherIndex.groups(query: "session", commands: [.newSession], sessions: [], projects: [])[0].entries[0].detail == "File")
    #expect(SwitcherIndex.fuzzyScore("tr", in: "toggle review") == 6)
    #expect(SwitcherIndex.fuzzyScore("rt", in: "toggle review") == nil)
}

@Test func windowStateRoundTripsAndRejectsStaleState() throws {
    var state = WindowState(owner: "ui-1")
    state.path = [SessionRef(serverID: first, sessionID: "ses_root", requestID: "per_1"), SessionRef(serverID: first, sessionID: "ses_child")]
    state.server = first; state.project = first.rawValue.uuidString + ":prj"; state.homeOpen = false; state.reviewOpen = true
    state.reviewTab = "Context"; state.chatWidth = 700; state.homeWidth = 300; state.reviewTreeWidth = 260
    let restored = try #require(WindowState.restore(state.encoded(), owner: "ui-1", servers: [first]))
    #expect(restored.path.map(\.sessionID) == ["ses_root", "ses_child"])
    #expect(restored.path.allSatisfy { $0.requestID == nil }, "A restored window does not reopen an old request")
    #expect(restored.server == first && restored.project == state.project && !restored.homeOpen && restored.reviewOpen)
    #expect(restored.reviewTab == "Context" && restored.chatWidth == 700 && restored.homeWidth == 300 && restored.reviewTreeWidth == 260)
    #expect(WindowState.restore(state.encoded(), owner: "ui-2", servers: [first]) == nil, "Another namespace's window")
    #expect(WindowState.restore(Data("{".utf8), owner: "ui-1", servers: [first]) == nil)
    #expect(WindowState.restore(nil, owner: "ui-1", servers: [first]) == nil)
    var old = state; old.version = 0
    #expect(WindowState.restore(old.encoded(), owner: "ui-1", servers: [first]) == nil)
    let removed = try #require(WindowState.restore(state.encoded(), owner: "ui-1", servers: [second]))
    #expect(removed.path.isEmpty && removed.server == nil && removed.project == nil, "Servers that are no longer saved")
    var wild = state; wild.chatWidth = 10; wild.homeWidth = 9_000; wild.reviewTreeWidth = -1; wild.reviewTab = "Logs"
    let clamped = try #require(WindowState.restore(wild.encoded(), owner: "ui-1", servers: [first]))
    #expect(clamped.chatWidth == 450 && clamped.homeWidth == 520 && clamped.reviewTreeWidth == 200 && clamped.reviewTab == nil)
    #expect(WorkspaceWidths.clamp(.nan, 200...480) == 200 && WorkspaceWidths.clamp(.infinity, 200...480) == 200)
}

@Test(arguments: [
    // The desktop's session-panel-width table.
    (800.0, 1700.0 as Double?, false, 800.0), (1600, 1700, false, 1220), (1600, 1700, true, 900), (3440, 3440, false, 2960),
    (1600, 700, true, 450), (1600, 0, false, 450), (1600, nil, false, 1600),
])
func chatWidthClampsLikeTheDesktop(width: Double, available: Double?, split: Bool, expected: Double) {
    #expect(WorkspaceWidths.clampChat(width, available: available, split: split) == expected)
}

private func message(_ id: String, _ type: String, tokens: [String: Double]? = nil, status: String? = nil, model: String? = nil, created: Double = 0) -> MessageFields {
    var raw: [String: JSONValue] = ["id": .string(id), "type": .string(type), "time": .object(["created": .double(created)])]
    if let tokens {
        raw["tokens"] = .object(["input": .double(tokens["input"] ?? 0), "output": .double(tokens["output"] ?? 0), "reasoning": .double(tokens["reasoning"] ?? 0),
                                 "cache": .object(["read": .double(tokens["read"] ?? 0), "write": .double(tokens["write"] ?? 0)])])
    }
    if let status { raw["status"] = .string(status) }
    if let model { raw["model"] = .object(["id": .string(model), "providerID": .string("mock")]) }
    return MessageFields(raw: .object(raw))
}
private let models = [ModelInfo(raw: .object(["id": .string("mock-1"), "providerID": .string("mock"), "name": .string("Mock"), "limit": .object(["context": .double(200_000), "output": .double(8_000)])])),
                      ModelInfo(raw: .object(["id": .string("open"), "providerID": .string("mock"), "name": .string("Open"), "limit": .object(["context": .double(0), "output": .double(0)])]))]

@Test func contextUsageForAKnownLimit() throws {
    let messages = [message("msg_1", "user"), message("msg_2", "assistant", tokens: ["input": 50_000, "output": 30_000, "reasoning": 4_000, "read": 1_000, "write": 500], model: "mock-1", created: 42)]
    let usage = try #require(ContextUsage.compute(messages, boundary: nil, models: models, session: nil))
    #expect(usage.total == 85_500 && usage.limit == 200_000 && usage.percent == 43 && usage.created == 42)
    #expect(ContextUsage.label(usage) == "Context 43%")
}

@Test func contextUsageForAnUnknownLimitAndNoAssistantYet() throws {
    let open = [message("msg_1", "assistant", tokens: ["input": 10], model: "open")]
    let usage = try #require(ContextUsage.compute(open, boundary: nil, models: models, session: nil))
    #expect(usage.total == 10 && usage.limit == nil && usage.percent == nil && ContextUsage.label(usage) == "Context —")
    let uncatalogued = [message("msg_1", "assistant", tokens: ["input": 10], model: "missing")]
    #expect(ContextUsage.compute(uncatalogued, boundary: nil, models: models, session: nil)?.percent == nil)
    #expect(ContextUsage.compute([message("msg_1", "user")], boundary: nil, models: models, session: nil) == nil)
    #expect(ContextUsage.compute([message("msg_1", "assistant")], boundary: nil, models: models, session: nil) == nil, "A step without tokens")
    #expect(ContextUsage.label(nil) == "Context —")
    // A message without a model falls back to the session's.
    let session = ModelRef(raw: .object(["id": .string("mock-1"), "providerID": .string("mock")]))
    #expect(ContextUsage.compute([message("msg_1", "assistant", tokens: ["input": 2_000])], boundary: nil, models: models, session: session)?.percent == 1)
}

@Test func contextUsageStopsAtCompactionAndRevert() {
    let messages = [message("msg_1", "assistant", tokens: ["input": 100], model: "mock-1"), message("msg_2", "compaction", status: "completed"),
                    message("msg_3", "user"), message("msg_4", "assistant", tokens: ["input": 200], model: "mock-1"),
                    message("msg_5", "user"), message("msg_6", "assistant", tokens: ["input": 300], model: "mock-1")]
    #expect(ContextUsage.lastAssistantWithUsage(messages, boundary: nil)?.id == "msg_6")
    #expect(ContextUsage.lastAssistantWithUsage(messages, boundary: "msg_5")?.id == "msg_4", "Before the revert boundary")
    #expect(ContextUsage.lastAssistantWithUsage(messages, boundary: "msg_3") == nil, "Nothing after the compaction yet")
    #expect(ContextUsage.lastAssistantWithUsage(messages, boundary: "msg_missing") == nil)
    let running = [message("msg_1", "assistant", tokens: ["input": 100]), message("msg_2", "compaction", status: "running")]
    #expect(ContextUsage.lastAssistantWithUsage(running, boundary: nil)?.id == "msg_1", "Only a completed compaction resets usage")
}

@Test func todosComeFromTheLatestCompletedWrite() {
    func call(_ status: String, _ todos: [(String, String)]) -> JSONValue {
        .object(["type": .string("tool"), "id": .string(UUID().uuidString), "name": .string("todowrite"), "state": .object([
            "status": .string(status), "input": .object(["todos": .array(todos.map { .object(["content": .string($0.0), "status": .string($0.1)]) })])])])
    }
    func assistant(_ id: String, _ content: [JSONValue]) -> MessageFields {
        MessageFields(raw: .object(["id": .string(id), "type": .string("assistant"), "content": .array(content)]))
    }
    let messages = [assistant("msg_1", [call("completed", [("Plan", "completed"), ("Build", "in_progress")])]),
                    assistant("msg_2", [call("completed", [("Plan", "completed"), ("Build", "completed"), ("Ship", "odd"), ("", "pending")])]),
                    assistant("msg_3", [call("running", [("Never", "pending")])])]
    #expect(SessionTodo.current(messages, boundary: nil) == [.init(content: "Plan", status: .completed), .init(content: "Build", status: .completed), .init(content: "Ship", status: .pending)])
    #expect(SessionTodo.current(messages, boundary: "msg_2").map(\.status) == [.completed, .inProgress])
    #expect(SessionTodo.current([], boundary: nil).isEmpty)
}

@Test func dropsBecomeMentionsAttachmentsOrText() {
    #expect(ComposerDrop.classify([ComposerDrop.mentionType, "public.utf8-plain-text"]) == .mention)
    #expect(ComposerDrop.classify(["public.png"]) == .attachment("public.png"))
    #expect(ComposerDrop.classify(["public.jpeg", "public.file-url"]) == .attachment("public.file-url"))
    #expect(ComposerDrop.classify(["com.adobe.pdf"]) == .attachment("com.adobe.pdf"))
    #expect(ComposerDrop.classify(["public.html", "public.utf8-plain-text"]) == .text("public.utf8-plain-text"))
    #expect(ComposerDrop.classify(["public.plain-text"], named: "notes.txt") == .attachment("public.plain-text"), "A text file is attached")
    #expect(ComposerDrop.classify(["public.plain-text"], named: "Text") == .text("public.plain-text"))
    #expect(ComposerDrop.classify(["public.mpeg-4"]) == .refused)
    #expect(ComposerDrop.classify(["public.mp3"]) == .refused)
    #expect(ComposerDrop.classify(["com.example.unknown"]) == .refused)
}

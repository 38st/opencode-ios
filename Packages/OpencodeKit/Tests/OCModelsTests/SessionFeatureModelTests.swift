import Foundation
import Testing
import OCFoundation
@testable import OCModels

private func entry(_ text: String, _ session: String, _ created: Double) -> PromptHistory.Entry { .init(text: text, sessionID: session, created: created) }

@Test func promptHistoryPutsTheSessionFirstAndKeepsEachTextOnce() {
    let entries = PromptHistory.entries(
        session: [entry("fix the build", "a", 10), entry("add tests", "a", 30), entry("  ", "a", 40), entry("fix the build ", "a", 20)],
        project: [entry("deploy", "b", 50), entry("add tests", "b", 60), entry("lint", "c", 5)])
    #expect(entries.map(\.text) == ["add tests", "fix the build ", "deploy", "lint"])
    #expect(entries.first?.sessionID == "a", "A repeated text keeps its place in this session")
    #expect(PromptHistory.entries(session: (0..<150).map { entry("p\($0)", "a", Double($0)) }, project: []).count == 100)
}

@Test func promptHistoryCursorStepsAndRestoresTheDraft() {
    let entries = [entry("newest", "a", 3), entry("older", "a", 2)]
    var cursor = PromptHistory.Cursor()
    #expect(cursor.newer(entries) == nil, "Nothing to step back to")
    #expect(cursor.older(entries, current: "") == "newest")
    #expect(cursor.older(entries, current: "newest") == "older")
    #expect(cursor.older(entries, current: "older") == nil, "The oldest stays")
    #expect(cursor.index == 1)
    #expect(cursor.newer(entries) == "newest")
    #expect(cursor.newer(entries) == "", "Stepping past the newest restores the empty draft")
    #expect(cursor.index == nil)
    var empty = PromptHistory.Cursor()
    #expect(empty.older([], current: "") == nil && empty.index == nil)
}

private func inbox(_ type: String, directory: String, delivery: String = "steer") -> InboxItem {
    InboxItem(raw: .object(["id": .string("msg_m"), "sessionID": .string("ses"), "type": .string(type), "delivery": .string(delivery),
        "time": .object(["created": .integer(1)]), "payload": .object(["location": .object(["directory": .string(directory)])])]))
}

@Test func moveStateFollowsTheInboxAndTheLocation() {
    #expect(SessionMove.state(requested: nil, pending: [], location: "/p") == nil)
    #expect(SessionMove.state(requested: nil, pending: [inbox("move", directory: "/wt", delivery: "queue")], location: "/p") == .pending(directory: "/wt", delivery: .queue),
            "A move from another device shows from its inbox item")
    #expect(SessionMove.state(requested: .pending(directory: "/wt", delivery: .steer), pending: [], location: "/p") == .pending(directory: "/wt", delivery: .steer),
            "Before the echo, the request stays pending")
    #expect(SessionMove.state(requested: .pending(directory: "/wt", delivery: .steer), pending: [], location: "/wt") == .applied(directory: "/wt"))
    #expect(SessionMove.state(requested: .failed(directory: "/wt", message: "x"), pending: [], location: "/p") == .failed(directory: "/wt", message: "x"))
    #expect(SessionMove.state(requested: nil, pending: [inbox("user", directory: "/wt")], location: "/p") == nil)
}

@Test func statsRangeUsesWholeDaysInTheDeviceTimeZone() throws {
    let istanbul = try #require(TimeZone(identifier: "Europe/Istanbul"))
    // 2026-10-29 21:30 UTC is 2026-10-30 00:30 in Istanbul (UTC+3).
    let now = Date(timeIntervalSince1970: 1_793_309_400)
    let today = StatsRange(.today, now: now, timeZone: istanbul)
    #expect(today.from == Date(timeIntervalSince1970: 1_793_307_600), "Midnight of Istanbul's day, not UTC's")
    #expect(today.to == now)
    let week = StatsRange(.week, now: now, timeZone: istanbul)
    #expect(week.from == Date(timeIntervalSince1970: 1_793_307_600 - 6 * 86_400))
    #expect(Dictionary(uniqueKeysWithValues: week.query)["timezone"] == "Europe/Istanbul")
    #expect(Dictionary(uniqueKeysWithValues: week.query)["from"] == "1792789200000")
}

@Test func statsDecodeTolerantlyAndEmpty() throws {
    let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
    {"range":{"from":1,"to":2},"sessions":3,"subagents":1,"prompts":4,"steps":9,"tokens":{"input":100,"output":20,"reasoning":3,"cache":{"read":5,"write":6}},
     "cost":0.125,"tools":{"mode":"detail","totals":{"calls":7,"succeeded":5,"failed":1,"unfinished":1},
     "usage":[{"name":"read","calls":2,"succeeded":2,"failed":0,"unfinished":0},{"name":"shell","calls":5,"failed":1,"durationP50":120}, 3]},
     "activeDays":2,"streak":2,"activity":[{"date":"2026-10-29","steps":4},{"date":"2026-10-30","steps":5}],
     "models":[{"model":{"id":"m","providerID":"p"},"steps":9,"tokens":{"input":100},"cost":0.125}], "future":true}
    """#.utf8))
    let stats = SessionStats(raw: raw)
    #expect(stats.sessions == 3 && stats.subagents == 1 && stats.prompts == 4 && stats.steps == 9 && !stats.isEmpty)
    #expect(stats.tokens.input == 100 && stats.tokens.cacheWrite == 6 && stats.cost == 0.125)
    #expect(stats.tools.calls == 7 && stats.tools.failed == 1 && stats.tools.unfinished == 1)
    #expect(stats.tools.byTool.map(\.name) == ["shell", "read"] && stats.tools.byTool.first?.medianDuration == 120)
    #expect(stats.activity.map(\.date) == ["2026-10-29", "2026-10-30"] && stats.models.first?.model.id == "m")
    let empty = SessionStats(raw: .object(["tools": .object(["mode": .string("none")])]))
    #expect(empty.isEmpty && empty.tools.calls == 0 && empty.activity.isEmpty && empty.models.isEmpty)
}

@Test func transcriptMarkdownRendersEveryRowType() throws {
    let transfer = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
    {"info":{"id":"ses_1","title":"Fix\nit","cost":0.5,"location":{"directory":"/Users/Shared/app"},"time":{"created":0}},
     "messages":[
      {"id":"m1","type":"user","text":"Hello","files":[{"name":"shot.png","mime":"image/png","data":""}],"time":{"created":1}},
      {"id":"m2","type":"synthetic","text":"editor context","time":{"created":2}},
      {"id":"m3","type":"system","text":"Be brief","time":{"created":3}},
      {"id":"m4","type":"skill","skill":"s","name":"Review","text":"Skill body","time":{"created":4}},
      {"id":"m5","type":"shell","command":"ls","status":"exited","output":{"output":"a\nb"},"time":{"created":5}},
      {"id":"m6","type":"assistant","agent":"build","content":[{"type":"reasoning","text":"thinking"},{"type":"text","text":"Answer with ```fence```"},
        {"type":"tool","id":"t","name":"read","state":{"status":"completed","input":{"filePath":"a.txt"},"content":[{"type":"text","text":"body"},{"type":"file","uri":"data:image/png;base64,AA==","mime":"image/png","name":"img"}]}},
        {"type":"tool","id":"u","name":"shell","state":{"status":"error","input":{},"error":{"message":"boom"}}}],"time":{"created":6}},
      {"id":"m7","type":"compaction","status":"completed","summary":"Summary","time":{"created":7}},
      {"id":"m8","type":"agent-switched","agent":"plan","time":{"created":8}},
      {"id":"m9","type":"model-switched","model":{"id":"gpt","providerID":"p"},"time":{"created":9}},
      {"id":"m10","type":"location-switched","location":{"directory":"/wt"},"time":{"created":10}},
      {"id":"m11","type":"idle","outcome":"failed","error":{"message":"rate limited"},"time":{"created":11}},
      {"id":"m12","type":"idle","outcome":"succeeded","time":{"created":12}},
      {"id":"m13","type":"future-row","time":{"created":13}}]}
    """#.utf8))
    let markdown = TranscriptMarkdown.render(transfer, timeZone: try #require(TimeZone(identifier: "UTC")))
    #expect(markdown.hasPrefix("# Fix it\n\n- Session: `ses_1`\n- Directory: `/Users/Shared/app`\n- Cost: $0.5000\n"))
    for expected in ["## User\n\nHello\n\n- Attachment: shot.png", "## Context\n\n> editor context", "## Instructions\n\n> Be brief",
                     "## Skill: Review\n\nSkill body", "## Shell\n\n```sh\n$ ls\na\nb\n```", "## Assistant (build)",
                     "<details><summary>Thinking</summary>\n\nthinking\n\n</details>", "Answer with ```fence```",
                     "**Tool: read** (completed)", "\"filePath\" : \"a.txt\"", "````\nbody\n[img]\n````".replacingOccurrences(of: "````", with: "```"),
                     "**Tool: shell** (error)\n\nError: boom", "## Compaction\n\n> Summary", "_Agent: plan_", "_Model: gpt_", "_Moved to `/wt`_",
                     "_Turn failed: rate limited_"] {
        #expect(markdown.contains(expected), "Missing: \(expected)")
    }
    #expect(!markdown.contains("succeeded") && !markdown.contains("future-row"), "Successful turns and unknown rows add nothing")
    #expect(TranscriptMarkdown.fence("a ``` b ```` c", language: "") == "`````\na ``` b ```` c\n`````", "A fence outlasts the text's backticks")
}

@Test func exportFileNamesFollowTheDesktop() throws {
    #expect(SessionExportFile.name(title: "Fix: the Parser!", sessionID: "ses_1", extension: "json") == "fix-the-parser.json")
    #expect(SessionExportFile.name(title: nil, sessionID: "ses_1", extension: "md") == "ses_1.md")
    #expect(SessionExportFile.name(title: "— ✓ —", sessionID: "ses_1", extension: "md") == "ses_1.md")
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try SessionExportFile.write(Data("a".utf8), title: "One", sessionID: "s", extension: "md", root: root)
    let second = try SessionExportFile.write(Data("b".utf8), title: "Two", sessionID: "s", extension: "md", root: root)
    let content = try String(contentsOf: second, encoding: .utf8)
    #expect(FileManager.default.fileExists(atPath: first.path) && content == "b", "A recent export stays while its share sheet may show it")
    #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
    #expect(first.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Exports")
}

@Test func sideQuestionsAreReadFromBtw() {
    #expect(ComposerSuggestions.sideQuestion("/btw what is X?") == "what is X?")
    #expect(ComposerSuggestions.sideQuestion("  /btw  ") == "")
    #expect(ComposerSuggestions.sideQuestion("/btwx") == nil && ComposerSuggestions.sideQuestion("ask /btw") == nil)
    #expect(ComposerCommand.available(session: true, showAgent: false).contains(.btw))
    #expect(!ComposerCommand.available(session: false, showAgent: false).contains(.btw))
}

@Test func elapsedTimeMatchesTheDesktop() {
    #expect(ElapsedTime.format(-3) == "0s" && ElapsedTime.format(42) == "42s")
    #expect(ElapsedTime.format(65) == "1m 05s" && ElapsedTime.format(3_599) == "59m 59s")
    #expect(ElapsedTime.format(7_380) == "2h 03m")
}

@Test func voiceVocabularyFavoursAgentsFilesAndSymbols() {
    let strings = VoiceVocabulary.strings(files: ["Sources/OCSync/ReadStore.swift", "/p/README.md"],
                                          texts: ["Call `send(_:)` on `ReadStore` and `x`", "see `user_id` and `two words`"], agents: ["build", "plan"])
    #expect(strings == ["build", "plan", "ReadStore.swift", "ReadStore", "README.md", "README", "user_id", "send"])
    #expect(VoiceVocabulary.strings(files: (0..<300).map { "f\($0).swift" }, texts: [], agents: []).count == 100)
}

@Test func gitActionsAreAgentPrompts() {
    for action in GitQuickAction.allCases {
        #expect(!action.prompt.isEmpty && action.message.hasSuffix(":"))
    }
    #expect(GitQuickAction.openPullRequest.prompt.contains("Do not merge"))
}

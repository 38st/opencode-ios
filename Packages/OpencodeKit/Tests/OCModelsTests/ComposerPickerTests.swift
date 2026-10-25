import Foundation
import Testing
import OCFoundation
import OCModels

private func pickerModel(_ id: String, provider: String, name: String? = nil, released: String? = nil) -> ModelInfo {
    var raw: JSONValue = .object(["id": .string(id), "name": .string(name ?? id), "providerID": .string(provider), "enabled": .bool(true), "family": .string("family")])
    if let released { raw.set("time", .object(["released": .string(released)])) }
    return .init(raw: raw)
}
@Test func modelGroupsSortSearchHideStaleAndRetainFiveRecentModels() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z"))
    let models = [pickerModel("old", provider: "openai", released: "2025-01-01"), pickerModel("new", provider: "openai", released: "2026-10-01"),
                  pickerModel("z", provider: "anthropic"), pickerModel("a", provider: "anthropic"), pickerModel("extra", provider: "acme")]
    let providers = [ProviderInfo(raw: .object(["id": .string("acme"), "name": .string("Custom provider")]))]
    let groups = ComposerPickers.groups(models, providers: providers, query: "", showAll: false, now: now)
    #expect(groups.map(\.id) == ["anthropic", "openai", "acme"])
    #expect(groups[0].models.map(\.id) == ["a", "z"])
    #expect(groups[1].models.map(\.id) == ["new"])
    #expect(ComposerPickers.groups(models, providers: providers, query: "CUSTOM", showAll: false, now: now).first?.models.first?.id == "extra")
    #expect(ComposerPickers.groups(models, providers: providers, query: "old", showAll: true, now: now).first?.models.first?.id == "old")
    let many = (0..<8).map { pickerModel("m\($0)", provider: "mock") }
    let recent = ComposerPickers.groups(many, providers: [], query: "", showAll: false, recent: many.reversed().map(ComposerPickers.key), now: now)
    #expect(recent.first?.name == "Recent")
    #expect(recent.first?.models.map(\.id) == ["m7", "m6", "m5", "m4", "m3"])
}
@Test func pickerBadgesAndAgentVisibility() {
    var model = pickerModel("free", provider: "opencode", name: "Free model (latest)")
    model["capabilities"] = .object(["input": .array([.string("image"), .string("pdf")])])
    model["variants"] = .array([.object(["id": .string("fast")])])
    #expect(ComposerPickers.badges(model, defaultModel: model) == ["Free", "Latest", "Default", "Image", "PDF", "Variants"])
    let agents = [("build", "primary", false), ("plan", "primary", false), ("reviewer", "primary", false), ("secret", "primary", true), ("explore", "subagent", false)].map { name, mode, hidden in
        AgentInfo(raw: .object(["id": .string(name), "name": .string(name), "mode": .string(mode), "hidden": .bool(hidden)]))
    }
    #expect(ComposerPickers.agents(agents).map(\.name) == ["build", "plan", "reviewer"])
    #expect(!ComposerPickers.showAgent(Array(agents.prefix(2)), setting: false))
    #expect(ComposerPickers.showAgent(agents, setting: false))
    #expect(ComposerPickers.showAgent([], setting: true))
}
@Test func selectionMetadataUsesDesktopModelIDAndRestoresVariant() {
    let model = ModelRef(raw: .object(["id": .string("m"), "providerID": .string("p"), "variant": .string("careful")]))
    let input = ComposerInput.encode(AttributedString("hello"), directory: "/p", agent: "reviewer", model: model, delivery: .queue)
    #expect(input.metadata?["model"]?["modelID"]?.stringValue == "m")
    #expect(input.metadata?["model"]?["id"] == nil)
    #expect(ComposerInput.restoreModel(input.metadata) == model)
    let same = ComposerPickers.sameSelection(.init(raw: .object(["id": .string("m"), "providerID": .string("p")])),
                                            .init(raw: .object(["id": .string("m"), "providerID": .string("p"), "variant": .string("default")])))
    #expect(same)
}
@Test func worktreeFailureRetainsForceRequiredAndUnknownShapes() {
    let failure = WorktreeFailure(raw: .object(["_tag": .string("WorktreeError"), "data": .object(["message": .string("Dirty worktree"), "forceRequired": .bool(true)])]))
    #expect(failure.message == "Dirty worktree" && failure.forceRequired)
    #expect(!WorktreeFailure(raw: .object([:])).forceRequired)
    #expect(FileEntry(raw: .object(["type": .string("future")])).type == .unknown("future"))
}

@Test func submittedClientCommandsMatchAvailablePickerActionsExactly() {
    func command(_ text: String, session: Bool = true, showAgent: Bool = true,
                 hasPrompts: Bool = true, reverted: Bool = true, server: JSONValue? = nil) -> ComposerCommand? {
        ComposerSuggestions.submittedCommand(text, server: server, session: session, showAgent: showAgent,
                                             hasPrompts: hasPrompts, reverted: reverted)?.command
    }
    for action in ComposerCommand.allCases {
        #expect(command(" /" + action.rawValue + "\n") == action)
    }
    #expect(command("/comp") == nil)
    #expect(command("/undo the edits") == nil)
    #expect(command("/unknown") == nil)
    #expect(command("/compact", session: false) == nil)
    #expect(command("/undo", hasPrompts: false) == nil)
    #expect(command("/redo", reverted: false) == nil)
    #expect(command("/agent", showAgent: false) == nil)
    #expect(command("/new", session: false) == .new)
    #expect(command("/compact", server: .array([.object(["name": .string("compact")])])) == nil)
}

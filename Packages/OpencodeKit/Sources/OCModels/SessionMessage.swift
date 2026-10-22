import Foundation
import OCFoundation

public enum SessionMessage: Codable, Sendable, Equatable {
    case user(MessageFields)
    case assistant(MessageFields)
    case synthetic(MessageFields)
    case system(MessageFields)
    case skill(MessageFields)
    case shell(MessageFields)
    case compaction(MessageFields)
    case idle(MessageFields)
    case agentSwitched(MessageFields)
    case modelSwitched(MessageFields)
    case locationSwitched(MessageFields)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["user", "assistant", "synthetic", "system", "skill", "shell", "compaction", "idle", "agent-switched", "model-switched", "location-switched"].contains(raw["type"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["id", "type", "text", "agent", "shellID", "command", "status", "summary", "recent"], numbers: ["cost", "exit"], objects: ["time", "model", "tokens", "retry", "error"], arrays: ["content", "files", "agents", "skills"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["type"]?.stringValue ?? "" {
        case "user": self = .user(.init(raw: raw))
        case "assistant": self = .assistant(.init(raw: raw))
        case "synthetic": self = .synthetic(.init(raw: raw))
        case "system": self = .system(.init(raw: raw))
        case "skill": self = .skill(.init(raw: raw))
        case "shell": self = .shell(.init(raw: raw))
        case "compaction": self = .compaction(.init(raw: raw))
        case "idle": self = .idle(.init(raw: raw))
        case "agent-switched": self = .agentSwitched(.init(raw: raw))
        case "model-switched": self = .modelSwitched(.init(raw: raw))
        case "location-switched": self = .locationSwitched(.init(raw: raw))
        default: self = .unknown(type: raw["type"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .user(let value), .assistant(let value), .synthetic(let value), .system(let value), .skill(let value), .shell(let value), .compaction(let value), .idle(let value), .agentSwitched(let value), .modelSwitched(let value), .locationSwitched(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: MessageFields { .init(raw: raw) }
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

public extension SessionMessage {
    var id: String { fields.id }
    var content: [AssistantContent] { fields.content }
    var time: WireTime { fields.time }
}
public struct MessageFields: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var type: String { string("type") }
    public var text: String { string("text") }
    public var description: String? { self["description"]?.stringValue }
    public var metadata: JSONValue? { self["metadata"] }
    public var time: WireTime { object("time") }
    public var agent: String? { self["agent"]?.stringValue }
    public var model: ModelRef? { optional("model") }
    public var previous: JSONValue? { self["previous"] }
    public var location: Location? { optional("location") }
    public var projectID: String? { self["projectID"]?.stringValue }
    public var subpath: String? { self["subpath"]?.stringValue }
    public var skill: String? { self["skill"]?.stringValue }
    public var name: String? { self["name"]?.stringValue }
    public var files: [PromptFile] { self["files"]?.lossy(PromptFile.self).values ?? [] }
    public var agents: [PromptAgent] { self["agents"]?.lossy(PromptAgent.self).values ?? [] }
    public var skills: [PromptSkill] { self["skills"]?.lossy(PromptSkill.self).values ?? [] }
    public var content: [AssistantContent] { self["content"]?.lossy(AssistantContent.self).values ?? [] }
    public var snapshot: StepSnapshot? { optional("snapshot") }
    public var finish: String? { self["finish"]?.stringValue }
    public var rawFinish: String? { self["rawFinish"]?.stringValue }
    public var providerState: JSONValue? { self["providerState"] }
    public var providerContext: JSONValue? { self["providerContext"] }
    public var cost: Double? { self["cost"]?.wireNumber }
    public var tokens: TokenUsage? { optional("tokens") }
    public var error: StructuredError? { optional("error") }
    public var retry: AssistantRetry? { optional("retry") }
    public var shellID: String? { self["shellID"]?.stringValue }
    public var command: String? { self["command"]?.stringValue }
    public var status: String? { self["status"]?.stringValue }
    public var exit: Double? { self["exit"]?.wireNumber }
    public var output: ShellOutput? { optional("output") }
    public var reason: String? { self["reason"]?.stringValue }
    public var summary: String? { self["summary"]?.stringValue }
    public var recent: String? { self["recent"]?.stringValue }
    public var outcome: String? { self["outcome"]?.stringValue }
}
public struct AssistantRetry: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var attempt: Double { number("attempt") }
    public var at: Double { number("at") }
    public var error: StructuredError { object("error") }
}
public struct PromptFile: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var data: String { string("data") }
    public var mime: String { string("mime") }
    public var name: String? { self["name"]?.stringValue }
    public var description: String? { self["description"]?.stringValue }
    public var source: JSONValue? { self["source"] }
    public var mention: PromptMention? { optional("mention") }
}

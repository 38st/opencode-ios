import OCFoundation

/// Model output is deliberately not validated against the tool's input schema.
public protocol ToolInput: Sendable {
    var raw: JSONValue { get }
    init(raw: JSONValue)
}
public extension ToolInput {
    func text(_ keys: String...) -> String? { keys.lazy.compactMap { raw[$0]?.stringValue }.first }
    func number(_ key: String) -> Double? { raw[key]?.wireNumber ?? raw[key]?.stringValue.flatMap(Double.init) }
    func flag(_ key: String) -> Bool? {
        if let flag = raw[key]?.boolValue { return flag }
        return raw[key]?.stringValue.flatMap { ["true": true, "false": false][$0] }
    }
}
public struct ShellInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var command: String? { text("command") }
    public var description: String? { text("description") }
    public var timeout: Double? { number("timeout") }
    public var workdir: String? { text("workdir", "cwd") }
    public var background: Bool? { flag("background") }
}
public struct EditInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var filePath: String? { text("filePath", "file_path", "path") }
    public var oldString: String? { text("oldString", "old_string") }
    public var newString: String? { text("newString", "new_string") }
    public var replaceAll: Bool? { flag("replaceAll") ?? flag("replace_all") }
}
public struct WriteInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var filePath: String? { text("filePath", "file_path", "path") }
    public var content: String? { text("content") }
}
public struct ReadInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var filePath: String? { text("filePath", "file_path", "path") }
    public var offset: Double? { number("offset") }
    public var limit: Double? { number("limit") }
}
public struct GrepInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var pattern: String? { text("pattern") }
    public var path: String? { text("path") }
    public var include: String? { text("include") }
    public var literal: Bool? { flag("literal") }
    public var caseSensitive: Bool? { flag("caseSensitive") }
    public var limit: Double? { number("limit") }
}
public struct GlobInput: ToolInput {
    public var hidden: Bool? { flag("hidden") }
    public var limit: Double? { number("limit") }
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var pattern: String? { text("pattern") }
    public var path: String? { text("path") }
}
public struct SubagentInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var prompt: String? { text("prompt") }
    public var agent: String? { text("agent", "subagent_type") }
    public var description: String? { text("description") }
    public var sessionID: String? { text("sessionID", "task_id") }
    public var model: String? { text("model") }
    public var background: Bool? { flag("background") }
}
public struct QuestionInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var questions: [WireObject] { raw["questions"]?.lossy(WireObject.self).values ?? [] }
}
public struct WebfetchInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var url: String? { text("url") }
    public var format: String? { text("format") }
    public var timeout: Double? { number("timeout") }
}
public struct WebsearchInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var query: String? { text("query") }
    public var numResults: Double? { number("numResults") }
}
public struct SkillInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var name: String? { text("name", "id") }
}
public enum ToolInputView: Sendable {
    case shell(ShellInput), edit(EditInput), write(WriteInput), read(ReadInput), grep(GrepInput), glob(GlobInput)
    case subagent(SubagentInput), question(QuestionInput), webfetch(WebfetchInput), websearch(WebsearchInput), skill(SkillInput)
    case patch(PatchInput), todo(TodoInput), unknown(name: String, raw: JSONValue)
    public init(name: String, raw: JSONValue) {
        switch name {
        case "shell", "bash": self = .shell(.init(raw: raw))
        case "edit": self = .edit(.init(raw: raw))
        case "write": self = .write(.init(raw: raw))
        case "read": self = .read(.init(raw: raw))
        case "grep": self = .grep(.init(raw: raw))
        case "glob": self = .glob(.init(raw: raw))
        case "subagent", "task": self = .subagent(.init(raw: raw))
        case "question": self = .question(.init(raw: raw))
        case "webfetch": self = .webfetch(.init(raw: raw))
        case "websearch": self = .websearch(.init(raw: raw))
        case "skill": self = .skill(.init(raw: raw))
        case "patch", "apply_patch": self = .patch(.init(raw: raw))
        case "todowrite", "todoread": self = .todo(.init(raw: raw))
        default: self = .unknown(name: name, raw: raw)
        }
    }
}

public struct PatchInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var patchText: String? { text("patchText", "patch") ?? raw.stringValue }
}
public struct TodoInput: ToolInput {
    public let raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var todos: [WireObject] { raw["todos"]?.lossy(WireObject.self).values ?? [] }
}

import Foundation
import OCFoundation
import OCModels

public struct ToolPresentation: Equatable, Sendable {
    public enum Style: Sendable { case generic, explore, diff, addedFile, shell, subagent, question, compact, links, execute }
    public var title: String
    public var subtitle: String = ""
    /// The file the tool acted on, which the row can open. Only Read (of a file), Edit and Write set it; never a search summary.
    public var path: String?
    public var icon: String = "code"
    public var status: String
    public var style: Style = .generic
    public var input: String = ""
    public var output: String = ""
    public var badge: String?
    public var failed = false
    public var errorMessage: String?
    public var files: [FileDiff] = []
    public var links: [URL] = []
    public var nested: [ToolPresentation] = []
    public var childID: String?
    public var shellID: String?
    public init(title: String, status: String) { self.title = title; self.status = status }
    public static func shellFailed(_ metadata: JSONValue?) -> Bool {
        (metadata?["exit"]?.wireNumber ?? 0) != 0 || metadata?["timeout"]?.boolValue == true || metadata?["status"]?.stringValue == "timeout"
    }
}

public protocol ToolPresenter: Sendable {
    func matches(_ name: String) -> Bool
    func summary(_ tool: ContentFields) -> ToolPresentation
    func detail(_ tool: ContentFields) -> ToolPresentation
}
public extension ToolPresenter {
    func summary(_ tool: ContentFields) -> ToolPresentation { detail(tool) }
}

public struct ToolPresenterRegistry: Sendable {
    private let presenters: [any ToolPresenter]
    public init(presenters: [any ToolPresenter] = [ReadPresenter(), GlobPresenter(), GrepPresenter(), EditPresenter(), PatchPresenter(), WritePresenter(), ShellPresenter(), SubagentPresenter(), QuestionPresenter(), SkillPresenter(), WebfetchPresenter(), WebsearchPresenter(), ExecutePresenter(), TodoPresenter()]) {
        self.presenters = presenters
    }
    public func presentation(_ tool: ContentFields) -> ToolPresentation {
        (presenters.first { $0.matches(tool.name) } ?? GenericToolPresenter()).detail(tool)
    }
}

public struct GenericToolPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { true }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        let state = tool.toolState.fields
        var value = ToolPresentation(title: tool.name, status: state.status)
        value.input = (try? state.input.prettyPrinted()) ?? ""
        value.output = state.content.filter { $0.type == "text" }.map { $0.fields.text }.joined(separator: "\n")
        value.failed = state.status == "error"
        if let error = state.error {
            value.errorMessage = error.message
            value.output = error.message + (value.output.isEmpty ? "" : "\n" + value.output)
        }
        if tool.name.contains("_") { value.badge = "MCP"; value.icon = "mcp" }
        return value
    }
}

private func base(_ tool: ContentFields, title: String, style: ToolPresentation.Style, icon: String = "code", subtitle: String? = nil) -> ToolPresentation {
    var value = GenericToolPresenter().detail(tool)
    value.title = title; value.style = style; value.icon = icon; value.subtitle = subtitle ?? ""; value.badge = nil
    return value
}
public struct ReadPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "read" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        var value = base(tool, title: "Read", style: .explore, icon: "glasses", subtitle: ReadInput(raw: tool.toolState.fields.input).filePath)
        // A read of a directory lists its entries; there is no file to open.
        if !value.output.hasPrefix("Read directory") { value.path = ReadInput(raw: tool.toolState.fields.input).filePath }
        return value
    }
}
public struct GlobPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "glob" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        explore(tool, title: "Glob", countKey: "count")
    }
}
public struct GrepPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "grep" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        explore(tool, title: "Grep", countKey: "matches")
    }
}
public struct EditPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "edit" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        let path = EditInput(raw: tool.toolState.fields.input).filePath
        var value = base(tool, title: "Edit", style: .diff, icon: "edit", subtitle: path)
        value.path = path
        value.files = tool.toolState.fields.metadata?["files"]?.lossy(FileDiff.self).values ?? []
        return value
    }
}
public struct PatchPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { ["patch", "apply_patch"].contains(name) }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        var value = EditPresenter().detail(tool); value.title = "Patch"; return value
    }
}
public struct WritePresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "write" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        let input = WriteInput(raw: tool.toolState.fields.input)
        var value = base(tool, title: "Write", style: .addedFile, icon: "edit", subtitle: input.filePath)
        value.output = input.content ?? ""; value.badge = "Added file"; value.path = input.filePath; return value
    }
}
public struct ShellPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { ["shell", "bash"].contains(name) }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        let state = tool.toolState.fields, input = ShellInput(raw: state.input), meta = state.metadata
        var value = base(tool, title: "Shell", style: .shell, icon: "terminal", subtitle: input.description ?? input.command)
        value.input = input.command ?? ""; value.shellID = meta?["shellID"]?.stringValue
        value.failed = value.failed || ToolPresentation.shellFailed(meta)
        if meta?["timeout"]?.boolValue == true || meta?["status"]?.stringValue == "timeout" { value.badge = "Timed out" }
        else if let exit = meta?["exit"]?.wireNumber { value.badge = "Exit \(Int(clamping: exit))" }
        return value
    }
}
public struct SubagentPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { ["subagent", "task"].contains(name) }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        let input = SubagentInput(raw: tool.toolState.fields.input)
        var value = base(tool, title: input.agent?.capitalized ?? "Agent", style: .subagent, icon: "subagent", subtitle: input.description)
        value.childID = tool.toolState.fields.metadata?["sessionID"]?.stringValue ?? input.sessionID
        value.input = input.prompt ?? ""; return value
    }
}
public struct QuestionPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "question" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        let state = tool.toolState.fields, questions = QuestionInput(raw: state.input).questions
        var value = base(tool, title: "Questions", style: .question, icon: "bubble-5")
        value.input = questions.map { $0.string("question") }.joined(separator: "\n\n")
        if let answers = state.metadata?["answers"]?.arrayValue {
            value.output = answers.map { $0.arrayValue?.compactMap(\.stringValue).joined(separator: ", ") ?? $0.stringValue ?? "" }.joined(separator: "\n")
        }
        return value
    }
}
public struct SkillPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "skill" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        base(tool, title: "Loaded skill", style: .compact, icon: "post-skill", subtitle: SkillInput(raw: tool.toolState.fields.input).name)
    }
}
public struct WebfetchPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "webfetch" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        base(tool, title: "Webfetch", style: .compact, icon: "globe", subtitle: WebfetchInput(raw: tool.toolState.fields.input).url)
    }
}
public struct WebsearchPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "websearch" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        var value = base(tool, title: "Websearch", style: .links, icon: "globe", subtitle: WebsearchInput(raw: tool.toolState.fields.input).query)
        let pattern = #"https?://[^\s<>\"'`)\]]+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = value.output as NSString
            var seen: Set<URL> = []
            value.links = regex.matches(in: value.output, range: NSRange(location: 0, length: ns.length)).compactMap {
                guard let url = URL(string: ns.substring(with: $0.range).trimmingCharacters(in: CharacterSet(charactersIn: "),.;:!?"))), seen.insert(url).inserted else { return nil }
                return url
            }
        }
        return value
    }
}
public struct ExecutePresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { name == "execute" }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        var value = base(tool, title: "CodeMode", style: .execute, icon: "code")
        value.input = tool.toolState.fields.input["code"]?.stringValue ?? value.input
        // Bound nesting: tool metadata is untrusted and can contain cycles represented as deep JSON.
        value.nested = (tool.toolState.fields.metadata?["toolCalls"]?.arrayValue ?? []).prefix(200).map { raw in
            let fallbackState: JSONValue = .object([
                "status": raw["status"] ?? .string("completed"),
                "input": raw["input"] ?? .object([:]),
                "content": .array([.object(["type": .string("text"), "text": raw["output"] ?? .string("")])])
            ])
            let nested = ContentFields(raw: .object([
                "type": .string("tool"), "name": raw["tool"] ?? raw["name"] ?? .string("tool"),
                "state": raw["state"] ?? fallbackState
            ]))
            return GenericToolPresenter().detail(nested)
        }
        value.failed = value.failed || tool.toolState.fields.metadata?["error"]?.boolValue == true || value.nested.contains(where: \.failed)
        return value
    }
}
public struct TodoPresenter: ToolPresenter {
    public init() {}
    public func matches(_ name: String) -> Bool { ["todowrite", "todoread"].contains(name) }
    public func detail(_ tool: ContentFields) -> ToolPresentation {
        var value = base(tool, title: "Tasks", style: .compact, icon: "task")
        value.output = TodoInput(raw: tool.toolState.fields.input).todos.map { "\($0.string("status")): \($0.string("content"))" }.joined(separator: "\n")
        return value
    }
}

private func explore(_ tool: ContentFields, title: String, countKey: String) -> ToolPresentation {
    let state = tool.toolState.fields
    let input = state.input
    var detail = input["path"]?.stringValue ?? "/"
    if let pattern = input["pattern"]?.stringValue { detail += " pattern=" + pattern }
    if let include = input["include"]?.stringValue { detail += " include=" + include }
    if let count = state.metadata?[countKey]?.wireNumber, count > 0, count < Double(Int.max) {
        detail += " · (\(Int(count)) \(count == 1 ? "match" : "matches"))"
    }
    return base(tool, title: title, style: .explore, icon: "magnifying-glass", subtitle: detail)
}

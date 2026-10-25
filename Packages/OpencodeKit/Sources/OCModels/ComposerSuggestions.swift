import Foundation
import OCFoundation

public struct ComposerTrigger: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case context, command }
    public let kind: Kind
    public let query: String
    public let range: NSRange
    public static func detect(_ text: AttributedString, caret: Int? = nil) -> Self? {
        guard let trigger = detect(String(text.characters), caret: caret) else { return nil }
        for run in text.runs where run[MentionAttribute.self] != nil {
            let range = NSRange(location: String(text[..<run.range.lowerBound].characters).utf16.count,
                                length: String(text[run.range].characters).utf16.count)
            if NSIntersectionRange(trigger.range, range).length > 0 { return nil }
        }
        return trigger
    }
    public static func detect(_ text: String, caret: Int? = nil) -> Self? {
        let prefix = String(decoding: Array(text.utf16.prefix(caret ?? text.utf16.count)), as: UTF16.self)
        if let match = prefix.range(of: #"(?:^|\s)@([^\s@]*)$"#, options: .regularExpression),
           let at = prefix[match].firstIndex(of: "@") {
            let range = NSRange(at..<prefix.endIndex, in: prefix)
            return .init(kind: .context, query: String(prefix[at...].dropFirst()), range: range)
        }
        if text.range(of: #"^/(\S*)$"#, options: .regularExpression) != nil {
            return .init(kind: .command, query: String(text.dropFirst()), range: NSRange(location: 0, length: text.utf16.count))
        }
        return nil
    }
}

public enum ComposerCommand: String, CaseIterable, Sendable {
    case new, undo, redo, compact, fork, model, agent
    public var title: String {
        switch self {
        case .new: "New session"
        case .undo: "Undo"
        case .redo: "Redo"
        case .compact: "Compact session"
        case .fork: "Fork from message"
        case .model: "Choose model"
        case .agent: "Cycle agent"
        }
    }
    public var description: String {
        switch self {
        case .new: ""
        case .undo: "Undo the last message"
        case .redo: "Redo the last undone message"
        case .compact: "Summarize the session to reduce context size"
        case .fork: "Create a new session from a previous message"
        case .model: "Select a different model"
        case .agent: "Switch to the next agent"
        }
    }
    public static func available(session: Bool, showAgent: Bool, hasPrompts: Bool = true, reverted: Bool = true) -> [Self] {
        allCases.filter {
            (session || [.new, .model, .agent].contains($0)) && ($0 != .agent || showAgent) &&
                (![.undo, .compact, .fork].contains($0) || hasPrompts) && ($0 != .redo || reverted)
        }
    }
}

public struct ComposerSuggestion: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let description: String
    public let mention: DraftMention?
    public let command: ComposerCommand?
    public let serverCommand: String?
    public init(id: String, label: String, description: String = "", mention: DraftMention? = nil,
                command: ComposerCommand? = nil, serverCommand: String? = nil) {
        self.id = id; self.label = label; self.description = description; self.mention = mention
        self.command = command; self.serverCommand = serverCommand
    }
}

public enum ComposerSuggestions {
    public static func submittedCommand(_ text: String, server: JSONValue?, session: Bool, showAgent: Bool,
                                        hasPrompts: Bool, reverted: Bool) -> ComposerSuggestion? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Resolve exact names using the same server-first ordering as the picker.
        let match = commands(query: "", server: server, session: session, showAgent: showAgent,
                             hasPrompts: hasPrompts, reverted: reverted).first { $0.label == text }
        return match?.command == nil ? nil : match
    }
    public static func matches(_ text: String, query: String) -> Bool {
        var remaining = query.lowercased().makeIterator(), next = remaining.next()
        for c in text.lowercased() where c == next { next = remaining.next() }
        return next == nil
    }
    public static func context(query: String, references: JSONValue?, skills: JSONValue?, agents: [AgentInfo], files: [FileEntry]) -> [ComposerSuggestion] {
        let references = (references?.arrayValue ?? []).filter { $0["hidden"]?.boolValue != true }.compactMap { raw -> ComposerSuggestion? in
            guard let name = raw["name"]?.stringValue, let path = raw["path"]?.stringValue else { return nil }
            return .init(id: "reference:" + name, label: "@" + name, description: raw["description"]?.stringValue ?? path, mention: .init(kind: "reference", value: path))
        }
        let skills = (skills?.arrayValue ?? []).compactMap { raw -> ComposerSuggestion? in
            guard let id = raw["id"]?.stringValue else { return nil }
            return .init(id: "skill:" + id, label: "@" + id, description: raw["description"]?.stringValue ?? "", mention: .init(kind: "skill", value: id))
        }
        let agents = agents.filter { !$0.hidden && $0.mode != "primary" }.map {
            ComposerSuggestion(id: "agent:" + ComposerPickers.agentID($0), label: "@" + ComposerPickers.agentID($0), description: $0.description ?? "", mention: .init(kind: "agent", value: ComposerPickers.agentID($0)))
        }
        return (references + skills + agents).filter { matches($0.label, query: query) } + files.map {
            .init(id: "file:" + $0.path, label: $0.path, description: $0.type == .directory ? "Directory" : "File", mention: .init(kind: "file", value: $0.path))
        }
    }
    public static func commands(query: String, server: JSONValue?, session: Bool, showAgent: Bool, hasPrompts: Bool = true, reverted: Bool = true) -> [ComposerSuggestion] {
        let remote = (server?.arrayValue ?? []).compactMap { raw -> ComposerSuggestion? in
            guard let name = raw["name"]?.stringValue else { return nil }
            return .init(id: "server:" + name, label: "/" + name, description: raw["description"]?.stringValue ?? "", serverCommand: name)
        }
        return (remote + ComposerCommand.available(session: session, showAgent: showAgent, hasPrompts: hasPrompts, reverted: reverted).map {
            .init(id: "client:" + $0.rawValue, label: "/" + $0.rawValue, description: $0.description, command: $0)
        }).filter { matches($0.label, query: query) || $0.command.map { matches($0.title, query: query) } == true }
    }
}

public enum ComposerDelivery {
    public enum Action: Equatable, Sendable { case stop, send(Delivery, interrupt: Bool), empty, unqueueable }
    public static func action(running: Bool, blank: Bool, shell: Bool, preference: Delivery, alternate: Bool = false, interrupt: Bool = false) -> Action {
        if blank { return running ? .stop : .empty }
        let delivery: Delivery = !running || interrupt ? .steer : alternate ? (preference == .queue ? .steer : .queue) : preference
        if shell && delivery == .queue { return .unqueueable }
        return .send(delivery, interrupt: interrupt)
    }
}

import Foundation
import OCModels

public enum TimelineDetail: String, CaseIterable, Sendable {
    case everything, detailed, compact, quiet, messagesOnly
    public var title: String {
        switch self {
        case .everything: "Everything"
        case .detailed: "Detailed"
        case .compact: "Compact"
        case .quiet: "Quiet"
        case .messagesOnly: "Messages only"
        }
    }
    public var expanded: Bool { self == .everything || self == .detailed }
}

public struct TimelineReference: Hashable, Sendable {
    public let messageID: String
    public let index: Int
    public init(messageID: String, index: Int) { self.messageID = messageID; self.index = index }
}

public struct TimelineRow: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case userPrompt, assistantText, reasoning, tool, toolGroup, subagent, shell
        case notice, compaction, retry, error, pendingInput, turnEnd
    }
    public let id: String
    public let kind: Kind
    public var text: String
    public var reference: TimelineReference?
    public var children: [TimelineRow]
    public var files: [String]
    public var badge: String?
    public var turnFrom: String?
    public var childID: String?
    public init(id: String, kind: Kind, text: String = "", reference: TimelineReference? = nil,
                children: [TimelineRow] = [], files: [String] = [], badge: String? = nil, childID: String? = nil, turnFrom: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.reference = reference
        self.children = children; self.files = files; self.badge = badge; self.childID = childID; self.turnFrom = turnFrom
    }
}

/// Matches session-ui/timeline/detail.ts. Errors remain visible at every detail level.
extension TimelineDetail {
    enum Placement { case separate, grouped, hidden }
    func placement(_ row: TimelineRow, tool: String? = nil) -> Placement {
        let category: String
        switch row.kind {
        case .reasoning: category = "thinking"
        case .shell: category = "shell"
        case .subagent: category = "subagents"
        case .notice, .compaction: category = "notices"
        case .tool:
            category = ["edit", "write", "patch", "apply_patch"].contains(tool ?? "") ? "edit" : tool == "execute" ? "shell" : "tools"
        default: return .separate
        }
        switch self {
        case .everything: return .separate
        case .detailed: return ["shell", "edit", "subagents"].contains(category) ? .separate : .grouped
        case .compact: return .grouped
        case .quiet: return ["edit", "subagents"].contains(category) ? .grouped : .hidden
        case .messagesOnly: return .hidden
        }
    }
}

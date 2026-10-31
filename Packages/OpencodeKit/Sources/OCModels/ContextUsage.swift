// Sources: packages/client/src/solid/usage.ts (lastAssistantWithUsage), gui-extensions/src/context/tab.tsx and
// tui/src/util/todo.ts. The session header, the Context tab and the iPhone sheet all read this one calculation.
import Foundation
import OCFoundation

public struct ContextUsage: Equatable, Sendable {
    public var messageID: String
    public var model: ModelRef?
    public var input: Double
    public var output: Double
    public var reasoning: Double
    public var cacheRead: Double
    public var cacheWrite: Double
    /// The model's context window; nil while the catalog has no limit for it.
    public var limit: Double?
    /// When the step was written: the desktop's "Last Activity".
    public var created: Double
    public var total: Double { input + output + reasoning + cacheRead + cacheWrite }
    /// `round(total / limit × 100)`, as the desktop rounds it; nil for an unknown limit.
    public var percent: Int? {
        guard let limit, limit > 0, limit.isFinite else { return nil }
        let value = (total / limit * 100).rounded()
        // Clamped first: a huge count or a tiny limit must not overflow the conversion.
        return value.isFinite && value >= 0 ? Int(min(value, 999_999)) : nil
    }
    /// The header's badge.
    public static func label(_ usage: ContextUsage?) -> String { usage?.percent.map { localized("Context \($0.formatted(.percent))", comment: "Header badge; %@ is how full the context window is, like 43%") } ?? localized("Context —", comment: "Header badge when context usage is unknown") }

    /// The assistant step whose tokens fill the context window now: the latest one after the last completed
    /// compaction and before the revert boundary.
    public static func lastAssistantWithUsage(_ messages: [MessageFields], boundary: String?) -> MessageFields? {
        let boundaryIndex = boundary.flatMap { id in messages.firstIndex { $0.id == id } }
        if boundary != nil && boundaryIndex == nil { return nil }
        let end = boundaryIndex ?? messages.count
        let compaction = messages[..<end].lastIndex { $0.type == "compaction" && $0.status == "completed" } ?? -1
        return messages[..<end].enumerated().last { index, message in
            message.type == "assistant" && message.tokens != nil && index > compaction
        }?.element
    }
    /// The usage of that step against its model's limit. The message's model is looked up first, then the session's.
    public static func compute(_ messages: [MessageFields], boundary: String?, models: [ModelInfo], session: ModelRef?) -> ContextUsage? {
        guard let message = lastAssistantWithUsage(messages, boundary: boundary), let tokens = message.tokens else { return nil }
        let model = message.model ?? session
        let limit = model.flatMap { ComposerPickers.model($0, in: models) }.map(\.limit.context).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        return ContextUsage(messageID: message.id, model: model, input: tokens.input, output: tokens.output, reasoning: tokens.reasoning,
                            cacheRead: tokens.cacheRead, cacheWrite: tokens.cacheWrite, limit: limit, created: message.time.created)
    }
}

public struct SessionTodo: Equatable, Sendable {
    public enum Status: String, Sendable { case pending, inProgress = "in_progress", completed, cancelled }
    public var content: String
    public var status: Status
    public init(content: String, status: Status) { self.content = content; self.status = status }
    /// The input of the latest completed `todowrite` call before the revert boundary.
    public static func current(_ messages: [MessageFields], boundary: String?) -> [SessionTodo] {
        let end = boundary.flatMap { id in messages.firstIndex { $0.id == id } } ?? messages.count
        let call = messages[..<end].filter { $0.type == "assistant" }.flatMap(\.content).last { item in
            item.type == "tool" && item.fields.name == "todowrite" && item.fields.state?["status"]?.stringValue == "completed"
        }
        return call?.fields.state?["input"]?["todos"]?.arrayValue?.compactMap { item in
            guard let content = item["content"]?.stringValue, !content.isEmpty else { return nil }
            return SessionTodo(content: content, status: item["status"]?.stringValue.flatMap(Status.init(rawValue:)) ?? .pending)
        } ?? []
    }
}

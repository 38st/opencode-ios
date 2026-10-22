import Foundation
import Observation
import OCFoundation
import OCModels

public enum ContentKey: Hashable, Sendable {
    case text(Int), reasoning(Int), tool(String), fallback(Int)
}
@MainActor @Observable public final class ContentItemModel: Identifiable {
    public let id: ContentKey
    public private(set) var text: String
    public var joinedMidStream: Bool
    public var fields: ContentFields
    public init(id: ContentKey, value: AssistantContent, joinedMidStream: Bool = false) {
        self.id = id; self.fields = value.fields; self.text = value.fields.text
        self.joinedMidStream = joinedMidStream
        if value.type != "tool" { fields["text"] = nil }
    }
    public var value: AssistantContent {
        var raw = fields.raw
        if fields.type == "text" || fields.type == "reasoning" { raw.set("text", .string(text)) }
        return .init(raw: raw)
    }
    public func append(_ delta: String) { text.append(delta) }
    public func end(_ text: String) { self.text = text; joinedMidStream = false }
    public func replace(_ value: AssistantContent) {
        fields = value.fields; text = value.fields.text
        if value.type != "tool" { fields["text"] = nil }
        joinedMidStream = false
    }
}
@MainActor @Observable public final class MessageModel: Identifiable {
    public let id: String
    public var fields: MessageFields
    public private(set) var items: [ContentItemModel] = []
    public var acknowledged: Bool
    @ObservationIgnored private var index: [ContentKey: ContentItemModel] = [:]
    public init(_ value: SessionMessage, acknowledged: Bool = true) {
        id = value.id; fields = value.fields; self.acknowledged = acknowledged
        replace(value)
    }
    public var value: SessionMessage {
        var raw = fields.raw
        if fields.type == "assistant" { raw.set("content", .array(items.map { $0.value.raw })) }
        return .init(raw: raw)
    }
    public func item(_ key: ContentKey) -> ContentItemModel? { index[key] }
    @discardableResult public func upsert(_ key: ContentKey, value: AssistantContent, joinedMidStream: Bool = false) -> ContentItemModel {
        if let item = index[key] { item.replace(value); return item }
        let item = ContentItemModel(id: key, value: value, joinedMidStream: joinedMidStream)
        index[key] = item; items.append(item); return item
    }
    public func replace(_ value: SessionMessage) {
        fields = value.fields; fields["content"] = nil
        var counts: [String: Int] = [:], next: [ContentItemModel] = [], keys = Set<ContentKey>()
        for content in value.content {
            let ordinal = counts[content.type, default: 0]; counts[content.type] = ordinal + 1
            let key: ContentKey = switch content.type {
            case "text": .text(ordinal)
            case "reasoning": .reasoning(ordinal)
            case "tool": .tool(content.fields.id)
            default: .fallback(next.count)
            }
            let item = index[key] ?? ContentItemModel(id: key, value: content)
            item.replace(content)
            if value.type == "assistant", value.time.streamed == nil, value.time.completed == nil {
                item.joinedMidStream = content.type == "tool" ? content.fields.toolState.type == "streaming" : content.fields.time.completed == nil
            }
            index[key] = item; keys.insert(key); next.append(item)
        }
        index = index.filter { keys.contains($0.key) }; items = next
    }
}
@MainActor @Observable public final class TranscriptModel {
    public private(set) var order: [String] = []
    public private(set) var messages: [String: MessageModel] = [:]
    public var olderCursor: String?
    public var loadingOlder = false
    public var isAtStart = false
    @ObservationIgnored var durableChanged: Set<String> = []
    public init(messages: [SessionMessage] = [], olderCursor: String? = nil) {
        self.olderCursor = olderCursor
        for message in messages { upsert(message) }
    }
    public var snapshot: [SessionMessage] { order.compactMap { messages[$0]?.value } }
    public func upsert(_ row: SessionMessage, acknowledged: Bool = true) {
        guard !row.id.isEmpty else { return }
        if let existing = messages[row.id] { existing.replace(row); existing.acknowledged = acknowledged }
        else { messages[row.id] = MessageModel(row, acknowledged: acknowledged); order.append(row.id) }
    }
    public func remove(_ id: String) { messages.removeValue(forKey: id); order.removeAll { $0 == id } }
    public func moveToEnd(_ id: String) { guard messages[id] != nil else { return }; order.removeAll { $0 == id }; order.append(id) }
    public func replace(_ rows: [SessionMessage], keeping protected: Set<String> = []) {
        let optimistic = order.filter { messages[$0]?.acknowledged == false }
        let serverIDs = Set(rows.map(\.id))
        let extra = order.filter { protected.contains($0) && !serverIDs.contains($0) }
        var next: [String] = []
        for row in rows where !next.contains(row.id) {
            if !protected.contains(row.id) || messages[row.id] == nil { upsert(row) }
            next.append(row.id)
        }
        for id in extra + optimistic where !next.contains(id) { next.append(id) }
        messages = messages.filter { next.contains($0.key) }; order = next
    }
    public func prepend(_ rows: [SessionMessage]) {
        let old = order
        for row in rows where messages[row.id] == nil { upsert(row) }
        order = rows.map(\.id).filter { !old.contains($0) } + old
    }
    public func visibleOrder(revert: String?, pending: [InboxItem]) -> [String] {
        let hidden = Set(pending.filter { $0.delivery == .queue }.map(\.id))
        let boundary = revert.flatMap { order.firstIndex(of: $0) }
        return order.enumerated().compactMap { index, id in
            if hidden.contains(id) { return nil }
            if let boundary, index >= boundary { return nil }
            if boundary == nil, let revert, id >= revert { return nil }
            return id
        }
    }
    @discardableResult public func truncate(at boundary: String) -> Set<String> {
        let start = order.firstIndex(of: boundary) ?? order.firstIndex(where: { $0 >= boundary }) ?? order.count
        let removed = Set(order.dropFirst(start))
        for id in removed { messages.removeValue(forKey: id) }
        order.removeSubrange(start...); return removed
    }
}

import Foundation
import OCFoundation

public enum AssistantContent: Codable, Sendable, Equatable {
    case text(ContentFields)
    case reasoning(ContentFields)
    case tool(ContentFields)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["text", "reasoning", "tool"].contains(raw["type"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["type", "id", "name", "text"], objects: ["state", "time"], bools: ["executed"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["type"]?.stringValue ?? "" {
        case "text": self = .text(.init(raw: raw))
        case "reasoning": self = .reasoning(.init(raw: raw))
        case "tool": self = .tool(.init(raw: raw))
        default: self = .unknown(type: raw["type"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .text(let value), .reasoning(let value), .tool(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: ContentFields { .init(raw: raw) }
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

public struct ContentFields: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var type: String { string("type") }
    public var id: String { string("id") }
    public var name: String { string("name") }
    public var text: String { string("text") }
    public var executed: Bool? { self["executed"]?.boolValue }
    public var providerState: JSONValue? { self["providerState"] }
    public var providerResultState: JSONValue? { self["providerResultState"] }
    public var state: JSONValue? { self["state"] }
    public var toolState: ToolState { .init(raw: self["state"] ?? .object([:])) }
    public var time: WireTime { object("time") }
}

public enum ToolState: Codable, Sendable, Equatable {
    case streaming(ToolStateFields)
    case running(ToolStateFields)
    case completed(ToolStateFields)
    case error(ToolStateFields)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["streaming", "running", "completed", "error"].contains(raw["status"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["status"], objects: ["metadata", "error"], arrays: ["content"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["status"]?.stringValue ?? "" {
        case "streaming": self = .streaming(.init(raw: raw))
        case "running": self = .running(.init(raw: raw))
        case "completed": self = .completed(.init(raw: raw))
        case "error": self = .error(.init(raw: raw))
        default: self = .unknown(type: raw["status"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .streaming(let value), .running(let value), .completed(let value), .error(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: ToolStateFields { .init(raw: raw) }
    public var type: String { raw["status"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

public struct ToolStateFields: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var status: String { string("status") }
    public var input: JSONValue { self["input"] ?? .object([:]) }
    public var metadata: JSONValue? { self["metadata"] }
    public var error: StructuredError? { optional("error") }
    public var content: [ToolContent] { self["content"]?.lossy(ToolContent.self).values ?? [] }
}

public enum ToolContent: Codable, Sendable, Equatable {
    case text(ToolContentFields)
    case file(ToolContentFields)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["text", "file"].contains(raw["type"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["type", "text", "uri", "mime", "name"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["type"]?.stringValue ?? "" {
        case "text": self = .text(.init(raw: raw))
        case "file": self = .file(.init(raw: raw))
        default: self = .unknown(type: raw["type"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .text(let value), .file(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: ToolContentFields { .init(raw: raw) }
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

public struct ToolContentFields: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var text: String { string("text") }
    public var uri: String { string("uri") }
    public var mime: String { string("mime") }
    public var name: String? { self["name"]?.stringValue }
}

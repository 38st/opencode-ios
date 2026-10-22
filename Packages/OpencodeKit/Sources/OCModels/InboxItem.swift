import Foundation
import OCFoundation

public enum InboxItem: Codable, Sendable, Equatable {
    case user(InboxFields)
    case synthetic(InboxFields)
    case compaction(InboxFields)
    case move(InboxFields)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["user", "synthetic", "compaction", "move"].contains(raw["type"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["id", "sessionID", "type", "delivery"], objects: ["payload", "time"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["type"]?.stringValue ?? "" {
        case "user": self = .user(.init(raw: raw))
        case "synthetic": self = .synthetic(.init(raw: raw))
        case "compaction": self = .compaction(.init(raw: raw))
        case "move": self = .move(.init(raw: raw))
        default: self = .unknown(type: raw["type"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .user(let value), .synthetic(let value), .compaction(let value), .move(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: InboxFields { .init(raw: raw) }
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

public extension InboxItem {
    var id: String { fields.id }
    var sessionID: String { fields.sessionID }
    var delivery: Delivery { .init(raw: fields["delivery"] ?? .string("steer")) }
}
public enum Delivery: Codable, Sendable, Equatable {
    case steer, queue, unknown(String)
    public init(raw: JSONValue) {
        switch raw.stringValue ?? "" {
        case "steer": self = .steer
        case "queue": self = .queue
        case let value: self = .unknown(value)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws {
        let value: String
        switch self { case .steer: value = "steer"; case .queue: value = "queue"; case .unknown(let raw): value = raw }
        try value.encode(to: encoder)
    }
}
public struct InboxFields: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var sessionID: String { string("sessionID") }
    public var time: WireTime { object("time") }
    public var payload: MessageFields { object("payload") }
}

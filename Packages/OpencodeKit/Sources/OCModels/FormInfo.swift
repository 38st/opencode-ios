import Foundation
import OCFoundation

public struct PermissionRequest: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var sessionID: String { string("sessionID") }
    public var action: String { string("action") }
    public var resources: [String] { strings("resources") }
    public var save: [String] { strings("save") }
    public var metadata: JSONValue? { self["metadata"] }
    public var source: PermissionSource? { optional("source") }
    public var message: String? { self["message"]?.stringValue }
}
public struct PermissionRule: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var action: String { string("action") }
    public var resource: String { string("resource") }
    public var effect: String { string("effect") }
}
public struct FormInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var sessionID: String { string("sessionID") }
    public var title: String { string("title") }
    public var metadata: JSONValue? { self["metadata"] }
    public var fields: [FormField] { self["fields"]?.lossy(FormField.self).values ?? [] }
    public var state: FormState? { self["state"].map(FormState.init(raw:)) }
}

public enum FormField: Codable, Sendable, Equatable {
    case string(FormFieldInfo)
    case number(FormFieldInfo)
    case integer(FormFieldInfo)
    case boolean(FormFieldInfo)
    case multiselect(FormFieldInfo)
    case external(FormFieldInfo)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["string", "number", "integer", "boolean", "multiselect", "external"].contains(raw["type"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["type", "key", "title", "description", "format", "pattern", "placeholder", "url"], numbers: ["minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems"], arrays: ["when", "options"], bools: ["required", "hidden", "custom"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["type"]?.stringValue ?? "" {
        case "string": self = .string(.init(raw: raw))
        case "number": self = .number(.init(raw: raw))
        case "integer": self = .integer(.init(raw: raw))
        case "boolean": self = .boolean(.init(raw: raw))
        case "multiselect": self = .multiselect(.init(raw: raw))
        case "external": self = .external(.init(raw: raw))
        default: self = .unknown(type: raw["type"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .string(let value), .number(let value), .integer(let value), .boolean(let value), .multiselect(let value), .external(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: FormFieldInfo { .init(raw: raw) }
    public var type: String { raw["type"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

public struct FormFieldInfo: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var key: String { string("key") }
    public var title: String? { self["title"]?.stringValue }
    public var description: String? { self["description"]?.stringValue }
    public var required: Bool { self["required"]?.boolValue ?? false }
    public var hidden: Bool { self["hidden"]?.boolValue ?? false }
    public var when: [FormCondition] { self["when"]?.lossy(FormCondition.self).values ?? [] }
    public var format: String? { self["format"]?.stringValue }
    public var pattern: String? { self["pattern"]?.stringValue }
    public var placeholder: String? { self["placeholder"]?.stringValue }
    public var defaultValue: JSONValue? { self["default"] }
    public var options: [FormOption] { self["options"]?.lossy(FormOption.self).values ?? [] }
    public var custom: Bool { self["custom"]?.boolValue ?? false }
    public var minLength: Double? { self["minLength"]?.wireNumber }
    public var maxLength: Double? { self["maxLength"]?.wireNumber }
    public var minimum: Double? { self["minimum"]?.wireNumber }
    public var maximum: Double? { self["maximum"]?.wireNumber }
    public var minItems: Double? { self["minItems"]?.wireNumber }
    public var maxItems: Double? { self["maxItems"]?.wireNumber }
    public var url: String? { self["url"]?.stringValue }
}
public struct FormOption: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var value: String { string("value") }
    public var label: String { string("label") }
    public var description: String? { self["description"]?.stringValue }
}

public enum FormState: Codable, Sendable, Equatable {
    case pending(WireObject)
    case answered(WireObject)
    case cancelled(WireObject)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)
    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        if ["pending", "answered", "cancelled"].contains(raw["status"]?.stringValue ?? ""), let error = WireValidation.issue(raw, strings: ["status", "message"], objects: ["answer"]) { self = .undecodable(raw: raw, error: error); return }
        switch raw["status"]?.stringValue ?? "" {
        case "pending": self = .pending(.init(raw: raw))
        case "answered": self = .answered(.init(raw: raw))
        case "cancelled": self = .cancelled(.init(raw: raw))
        default: self = .unknown(type: raw["status"]?.stringValue ?? "", raw: raw)
        }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .pending(let value), .answered(let value), .cancelled(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var fields: WireObject { .init(raw: raw) }
    public var type: String { raw["status"]?.stringValue ?? "" }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
}

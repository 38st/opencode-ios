import Foundation
import OCFoundation

public struct ProjectIcon: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var url: String? { self["url"]?.stringValue }
    public var override: String? { self["override"]?.stringValue }
    public var color: String? { self["color"]?.stringValue }
}
public struct LocationProject: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var directory: String { string("directory") }
    public var canonical: String { string("canonical") }
}
public struct PermissionSource: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var type: String { string("type") }
    public var messageID: String { string("messageID") }
    public var id: String { string("id") }
}
public struct FormCondition: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var key: String { string("key") }
    public var op: String { string("op") }
    public var value: JSONValue? { self["value"] }
}
public struct ModelCapabilities: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var tools: Bool { self["tools"]?.boolValue ?? false }
    public var input: [String] { strings("input") }
    public var output: [String] { strings("output") }
}
public struct ModelLimits: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var context: Double { number("context") }
    public var input: Double? { self["input"]?.wireNumber }
    public var output: Double { number("output") }
}
public struct ModelVariant: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var settings: JSONValue? { self["settings"] }
    public var headers: JSONValue? { self["headers"] }
    public var body: JSONValue? { self["body"] }
}
public struct PromptMention: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var start: Double { number("start") }
    public var end: Double { number("end") }
    public var text: String { string("text") }
}
public struct PromptAgent: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var name: String { string("name") }
    public var mention: PromptMention? { optional("mention") }
}
public struct PromptSkill: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var name: String { string("name") }
    public var text: String? { self["text"]?.stringValue }
    public var mention: PromptMention? { optional("mention") }
}
public struct StepSnapshot: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var start: String? { self["start"]?.stringValue }
    public var end: String? { self["end"]?.stringValue }
    public var files: [String] { strings("files") }
}
public struct ModelCostTier: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var type: String { string("type") }
    public var size: Double { number("size") }
}
public struct CacheCost: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var read: Double { number("read") }
    public var write: Double { number("write") }
}

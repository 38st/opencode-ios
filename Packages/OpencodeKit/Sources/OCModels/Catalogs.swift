import OCFoundation

public struct ModelRef: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var providerID: String { string("providerID") }
    public var variant: String? { self["variant"]?.stringValue }
}
public struct AgentInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var name: String { string("name") }
    public var model: ModelRef? { optional("model") }
    public var request: JSONValue? { self["request"] }
    public var system: String? { self["system"]?.stringValue }
    public var description: String? { self["description"]?.stringValue }
    public var mode: String { string("mode") }
    public var hidden: Bool { self["hidden"]?.boolValue ?? false }
    public var color: String? { self["color"]?.stringValue }
    public var steps: Double? { self["steps"]?.wireNumber }
    public var permissions: [PermissionRule] { self["permissions"]?.lossy(PermissionRule.self).values ?? [] }
}
public struct ModelInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var modelID: String { string("modelID") }
    public var providerID: String { string("providerID") }
    public var canonical: String? { self["canonical"]?.stringValue }
    public var family: String? { self["family"]?.stringValue }
    public var name: String { string("name") }
    public var package: String? { self["package"]?.stringValue }
    public var compatibility: JSONValue? { self["compatibility"] }
    public var settings: JSONValue? { self["settings"] }
    public var headers: JSONValue? { self["headers"] }
    public var body: JSONValue? { self["body"] }
    public var capabilities: ModelCapabilities { object("capabilities") }
    public var variants: [ModelVariant] { self["variants"]?.lossy(ModelVariant.self).values ?? [] }
    public var time: WireTime { object("time") }
    public var cost: [ModelCost] { self["cost"]?.lossy(ModelCost.self).values ?? [] }
    public var status: String { string("status") }
    public var enabled: Bool { self["enabled"]?.boolValue ?? false }
    public var limit: ModelLimits { object("limit") }
}
public struct ModelCost: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var tier: ModelCostTier? { optional("tier") }
    public var input: Double { number("input") }
    public var output: Double { number("output") }
    public var cache: CacheCost { object("cache") }
}
public struct ProviderInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var canonical: String? { self["canonical"]?.stringValue }
    public var integrationID: String? { self["integrationID"]?.stringValue }
    public var name: String { string("name") }
    public var activation: String { string("activation") }
    public var package: String { string("package") }
    public var compatibility: JSONValue? { self["compatibility"] }
    public var settings: JSONValue? { self["settings"] }
    public var headers: JSONValue? { self["headers"] }
    public var body: JSONValue? { self["body"] }
}

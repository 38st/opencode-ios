import OCFoundation

public enum MCPStatus: Codable, Sendable, Equatable {
    case connected(WireObject), pending(WireObject), disabled(WireObject), failed(WireObject), needsAuth(WireObject)
    case unknown(type: String, raw: JSONValue)
    case undecodable(raw: JSONValue, error: String)

    public init(raw: JSONValue) {
        guard raw.objectValue != nil else { self = .undecodable(raw: raw, error: "Expected an object"); return }
        let type = raw["status"]?.stringValue ?? ""
        if ["connected", "pending", "disabled", "failed", "needs_auth"].contains(type),
           let error = WireValidation.issue(raw, strings: ["status", "error"]) {
            self = .undecodable(raw: raw, error: error); return
        }
        switch type {
        case "connected": self = .connected(.init(raw: raw))
        case "pending": self = .pending(.init(raw: raw))
        case "disabled": self = .disabled(.init(raw: raw))
        case "failed": self = .failed(.init(raw: raw))
        case "needs_auth": self = .needsAuth(.init(raw: raw))
        default: self = .unknown(type: type, raw: raw)
        }
    }
    public var isFallback: Bool {
        switch self { case .unknown, .undecodable: true; default: false }
    }
    public init(from decoder: any Decoder) throws { self.init(raw: try JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    public var raw: JSONValue {
        switch self {
        case .connected(let value), .pending(let value), .disabled(let value), .failed(let value), .needsAuth(let value): value.raw
        case .unknown(_, let raw), .undecodable(let raw, _): raw
        }
    }
    public var error: String? { raw["error"]?.stringValue }
}

public struct MCPServer: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { name }
    public var name: String { string("name") }
    public var status: MCPStatus { .init(raw: self["status"] ?? .object([:])) }
    public var integrationID: String? { self["integrationID"]?.stringValue }
}

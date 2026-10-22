import Foundation
import OCFoundation

/// Raw JSON is the storage representation; typed views never discard future fields.
public protocol WireValue: Codable, Sendable, Equatable {
    var raw: JSONValue { get set }
    init(raw: JSONValue)
}

public extension WireValue {
    init(from decoder: any Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard raw.objectValue != nil else {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected an object"))
        }
        self.init(raw: raw)
    }
    func encode(to encoder: any Encoder) throws { try raw.omittingNullFields.encode(to: encoder) }
    subscript(_ key: String) -> JSONValue? {
        get { raw[key].flatMap { $0.isNull ? nil : $0 } }
        set { raw.set(key, newValue) }
    }
    func string(_ key: String, default fallback: String = "") -> String { self[key]?.stringValue ?? fallback }
    func number(_ key: String, default fallback: Double = 0) -> Double { self[key]?.wireNumber ?? fallback }
    func object<T: WireValue>(_ key: String, as: T.Type = T.self) -> T { T(raw: self[key] ?? .object([:])) }
    func optional<T: WireValue>(_ key: String, as: T.Type = T.self) -> T? { self[key].map(T.init(raw:)) }
    func strings(_ key: String) -> [String] { self[key]?.arrayValue?.compactMap(\.stringValue) ?? [] }
}

public extension JSONValue {
    static func number(_ value: Double) -> JSONValue {
        if !value.isFinite { return .string(value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity")) }
        if let integer = Int64(exactly: value) { return .integer(integer) }
        return .double(value)
    }
    var wireNumber: Double? {
        switch self {
        case .integer(let n): Double(n)
        case .double(let n): n
        case .string("NaN"): .nan
        case .string("Infinity"): .infinity
        case .string("-Infinity"): -.infinity
        default: nil
        }
    }
    var wireInt: Int? {
        if case .integer(let value) = self { return Int(exactly: value) }
        if case .string(let value) = self, let integer = Int(value) { return integer }
        guard let n = wireNumber, n.isFinite else { return nil }
        return Int(exactly: n)
    }
    mutating func set(_ key: String, _ value: JSONValue?) {
        var fields = objectValue ?? [:]
        fields[key] = value.flatMap { $0.isNull ? nil : $0 }
        self = .object(fields)
    }
    mutating func set(_ path: [String], _ value: JSONValue?) {
        guard let first = path.first else { return }
        if path.count == 1 { set(first, value); return }
        var child = self[first] ?? .object([:])
        child.set(Array(path.dropFirst()), value)
        set(first, child)
    }
    var omittingNullFields: JSONValue {
        switch self {
        case .object(let fields): .object(fields.filter { !$0.value.isNull }.mapValues(\.omittingNullFields))
        case .array(let values): .array(values.map(\.omittingNullFields))
        default: self
        }
    }
    func decoded<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
    /// Each union decoder retains its own fallback, including non-object elements.
    func lossy<T: Decodable & Sendable>(_ type: T.Type = T.self) -> LossyArray<T> {
        (try? decoded(LossyArray<T>.self)) ?? .init()
    }
}

public struct WireObject: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue = .object([:])) { self.raw = raw }
}
public struct WireTime: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue = .object([:])) { self.raw = raw }
    public var created: Double { number("created") }
    public var updated: Double { number("updated") }
    public var idle: Double? { self["idle"]?.wireNumber }
    public var viewed: Double? { self["viewed"]?.wireNumber }
    public var archived: Double? { self["archived"]?.wireNumber }
    public var released: Double? { self["released"]?.wireNumber }
    public var started: Double? { self["started"]?.wireNumber }
    public var active: Double? { self["active"]?.wireNumber }
    public var streamed: Double? { self["streamed"]?.wireNumber }
    public var ran: Double? { self["ran"]?.wireNumber }
    public var completed: Double? { self["completed"]?.wireNumber }
}
public struct TokenUsage: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue = .object([:])) { self.raw = raw }
    public var input: Double { number("input") }
    public var output: Double { number("output") }
    public var reasoning: Double { number("reasoning") }
    public var cacheRead: Double { raw["cache"]?["read"]?.wireNumber ?? 0 }
    public var cacheWrite: Double { raw["cache"]?["write"]?.wireNumber ?? 0 }
}
public struct StructuredError: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var type: String { string("type") }
    public var message: String { string("message") }
    public var status: Int? { self["status"]?.wireInt }
    public var response: JSONValue? { self["response"] }
}

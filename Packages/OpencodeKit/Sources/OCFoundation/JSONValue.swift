import Foundation

/// Arbitrary JSON without coercing strings, booleans or representable integers.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var isNull: Bool { self == .null }
    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
    public var integerValue: Int64? {
        guard case .integer(let value) = self else { return nil }
        return value
    }
    public var doubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
    public var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }
    public subscript(index: Int) -> JSONValue? {
        guard let values = arrayValue, values.indices.contains(index) else { return nil }
        return values[index]
    }

    public func prettyPrinted() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let a), .bool(let b)): a == b
        case (.integer(let a), .integer(let b)): a == b
        case (.double(let a), .double(let b)): a == b || (a.isNaN && b.isNaN)
        case (.string(let a), .string(let b)): a == b
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)): a == b
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null: hasher.combine(0)
        case .bool(let value): hasher.combine(1); hasher.combine(value)
        case .integer(let value): hasher.combine(2); hasher.combine(value)
        case .double(let value):
            hasher.combine(3)
            if value.isNaN { hasher.combine("NaN") } else { hasher.combine(value) }
        case .string(let value): hasher.combine(4); hasher.combine(value)
        case .array(let value): hasher.combine(5); hasher.combine(value)
        case .object(let value): hasher.combine(6); hasher.combine(value)
        }
    }
}

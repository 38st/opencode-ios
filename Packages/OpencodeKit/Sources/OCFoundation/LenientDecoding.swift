import Foundation

public extension KeyedDecodingContainer {
    /// Missing and null values use the default. Malformed present values still throw.
    func decode<T: Decodable>(
        _ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T
    ) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue()
    }

    func decodeNumberIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try superDecoder(forKey: key).singleValueContainer().decodeNumber()
    }

    func decodeNumber(forKey key: Key, default defaultValue: Double = 0) throws -> Double {
        try decodeNumberIfPresent(forKey: key) ?? defaultValue
    }
}

public extension SingleValueDecodingContainer {
    func decodeNumber() throws -> Double {
        if let value = try? decode(Double.self) { return value }
        if let value = try? decode(String.self) {
            switch value {
            case "NaN": return .nan
            case "Infinity": return .infinity
            case "-Infinity": return -.infinity
            default: break
            }
        }
        throw DecodingError.typeMismatch(Double.self, .init(
            codingPath: codingPath,
            debugDescription: "Expected a number, NaN, Infinity or -Infinity"
        ))
    }
}

public extension KeyedEncodingContainer {
    /// Raw JSON can retain nulls; outbound object fields must omit them.
    mutating func encodeIfNotNull(_ value: JSONValue?, forKey key: Key) throws {
        guard let value, !value.isNull else { return }
        try encode(value, forKey: key)
    }
}

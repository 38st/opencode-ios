/// Preserves array positions and raw JSON when a known union case is malformed.
/// Unknown union cases should be handled by Element's own decoder.
public struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
    public enum Entry: Sendable {
        case value(Element)
        case undecodable(raw: JSONValue, error: String)
    }

    public let entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public init(from decoder: any Decoder) throws {
        if try decoder.singleValueContainer().decodeNil() {
            entries = []
            return
        }
        var container = try decoder.unkeyedContainer()
        var entries: [Entry] = []
        while !container.isAtEnd {
            // Taking a decoder advances once, regardless of how far Element gets.
            let elementDecoder = try container.superDecoder()
            let raw = try JSONValue(from: elementDecoder)
            do {
                entries.append(.value(try Element(from: elementDecoder)))
            } catch {
                entries.append(.undecodable(raw: raw, error: String(describing: error)))
            }
        }
        self.entries = entries
    }

    public var values: [Element] {
        entries.compactMap {
            guard case .value(let value) = $0 else { return nil }
            return value
        }
    }
}

extension LossyArray.Entry: Equatable where Element: Equatable {}
extension LossyArray.Entry: Hashable where Element: Hashable {}
extension LossyArray: Equatable where Element: Equatable {}
extension LossyArray: Hashable where Element: Hashable {}

extension LossyArray: Encodable where Element: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for entry in entries {
            switch entry {
            case .value(let value): try container.encode(value)
            case .undecodable(let raw, _): try container.encode(raw)
            }
        }
    }
}

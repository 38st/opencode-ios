import Foundation
import Testing
@testable import OCFoundation

struct LossyArrayTests {
    private enum Part: Decodable, Sendable, Equatable {
        case text(String)
        case unknown(type: String, raw: JSONValue)

        enum CodingKeys: String, CodingKey { case type, text }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text": self = .text(try container.decode(String.self, forKey: .text))
            default: self = .unknown(type: type, raw: try JSONValue(from: decoder))
            }
        }
    }

    @Test func retainsUnknownAndMalformedEntriesAndContinues() throws {
        let data = try Fixture.data("lossy-union")
        let parts = try JSONDecoder().decode(LossyArray<Part>.self, from: data)
        let raw = try JSONDecoder().decode([JSONValue].self, from: data)
        #expect(parts.entries.count == 6)
        #expect(parts.entries[0] == .value(.text("before")))
        #expect(parts.entries[1] == .value(.unknown(type: "future", raw: raw[1])))
        for index in 2...4 {
            guard case .undecodable(let value, let error) = parts.entries[index] else {
                Issue.record("Expected undecodable entry at \(index)")
                continue
            }
            #expect(value == raw[index])
            #expect(!error.isEmpty)
        }
        #expect(parts.entries[5] == .value(.text("after")))
        #expect(parts.values.count == 3)
    }

    @Test func retainsDecoderConfigurationAndCodingPath() throws {
        struct Dated: Decodable, Sendable {
            let createdAt: Date
            let arrayIndex: Int?
            enum CodingKeys: String, CodingKey { case createdAt }
            init(from decoder: any Decoder) throws {
                arrayIndex = decoder.codingPath.last?.intValue
                let container = try decoder.container(keyedBy: CodingKeys.self)
                createdAt = try container.decode(Date.self, forKey: .createdAt)
            }
        }
        struct Envelope: Decodable { let items: LossyArray<Dated> }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        let result = try decoder.decode(Envelope.self, from: Data(
            #"{"items":[{"created_at":10},{"created_at":{}},{"created_at":20}]}"#.utf8
        ))
        #expect(result.items.values.map(\.createdAt.timeIntervalSince1970) == [10, 20])
        #expect(result.items.values.map(\.arrayIndex) == [0, 2])
        guard case .undecodable(_, let error) = result.items.entries[1] else {
            Issue.record("Missing malformed date")
            return
        }
        #expect(error.contains("items") && error.contains("createdAt"))
    }

    @Test func nullIsEmptyAndFailedValuesCanRoundTrip() throws {
        let null = try JSONDecoder().decode(LossyArray<Int>.self, from: Data("null".utf8))
        #expect(null.entries.isEmpty)
        let data = Data(#"[1,"broken",null,2]"#.utf8)
        let array = try JSONDecoder().decode(LossyArray<Int>.self, from: data)
        #expect(array.values == [1, 2])
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(array))
                == JSONDecoder().decode(JSONValue.self, from: data))
    }
}

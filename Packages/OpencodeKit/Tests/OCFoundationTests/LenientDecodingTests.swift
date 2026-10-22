import Foundation
import Testing
@testable import OCFoundation

struct LenientDecodingTests {
    private struct Defaults: Decodable {
        let name: String
        let items: LossyArray<String>
        let count: Int
        let optionalNumber: Double?
        let numbers: [Double]

        enum CodingKeys: String, CodingKey { case name, items, count, optionalNumber, nan, positive, negative, finite }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name, default: "untitled")
            items = try container.decode(LossyArray<String>.self, forKey: .items, default: .init())
            count = try container.decode(Int.self, forKey: .count, default: 0)
            optionalNumber = try container.decodeNumberIfPresent(forKey: .optionalNumber)
            numbers = try [.nan, .positive, .negative, .finite].map { try container.decodeNumber(forKey: $0) }
        }
    }

    @Test func treatsNullAndMissingAsAbsent() throws {
        let null = try JSONDecoder().decode(Defaults.self, from: Fixture.data("defaults"))
        let absent = try JSONDecoder().decode(Defaults.self, from: Data("{}".utf8))
        #expect(null.name == absent.name)
        #expect(null.items.entries.isEmpty && absent.items.entries.isEmpty)
        #expect(null.count == absent.count)
        #expect(null.optionalNumber == nil && absent.optionalNumber == nil)
        #expect(null.numbers[0].isNaN)
        #expect(null.numbers[1] == .infinity)
        #expect(null.numbers[2] == -.infinity)
        #expect(null.numbers[3] == 12.5)
        #expect(absent.numbers == [0, 0, 0, 0])
    }

    @Test(arguments: ["{\"name\":1}", "{\"finite\":\"12\"}", "{\"finite\":\"nan\"}", "{\"finite\":false}"])
    func malformedPresentValuesDoNotSilentlyDefault(json: String) {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Defaults.self, from: Data(json.utf8)) }
    }

    @Test func outboundOptionalFieldsOmitNull() throws {
        struct Payload: Encodable {
            enum CodingKeys: String, CodingKey { case absent, null, present }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfNotNull(nil, forKey: .absent)
                try container.encodeIfNotNull(.null, forKey: .null)
                try container.encodeIfNotNull(.integer(7), forKey: .present)
            }
        }
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(Payload()))
        #expect(raw == .object(["present": .integer(7)]))
    }
}

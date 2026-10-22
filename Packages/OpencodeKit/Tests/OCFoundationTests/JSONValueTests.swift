import Foundation
import Testing
@testable import OCFoundation

struct JSONValueTests {
    @Test func preservesJSONTypesAndLargeIntegers() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Fixture.data("values"))
        #expect(value["integer"] == .integer(9_007_199_254_740_993))
        #expect(value["maximum"]?.integerValue == .max)
        #expect(value["minimum"]?.integerValue == .min)
        #expect(value["fraction"] == .double(1.25))
        #expect(value["boolean"]?.boolValue == true)
        #expect(value["string"]?.stringValue == "NaN")
        #expect(value["null"]?.isNull == true)
        #expect(value["missing"] == nil)
        #expect(value["array"]?[0] == .null)
        #expect(value["array"]?[-1] == nil)
        #expect(value["array"]?[99] == nil)
        #expect(value["fraction"]?.integerValue == nil)
        #expect(value["integer"]?.doubleValue != nil)
        #expect(value["array"]?[4]?["extra"]?.arrayValue == [.integer(1), .integer(2)])
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func prettyPrintsInStableKeyOrder() throws {
        let value = JSONValue.object(["z": .bool(false), "a": .string("https://example.test")])
        let pretty = try value.prettyPrinted()
        #expect(pretty.contains("\n"))
        #expect(pretty.contains("https://example.test"))
        let a = try #require(pretty.range(of: "\"a\""))
        let z = try #require(pretty.range(of: "\"z\""))
        #expect(a.lowerBound < z.lowerBound)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(pretty.utf8)) == value)
    }

    @Test func hashingSeparatesNumbersAndNormalizesNaN() {
        let values: Set<JSONValue> = [.integer(1), .double(1), .double(.nan), .double(.nan)]
        #expect(values.count == 3)
        #expect(JSONValue.double(-0.0) == .double(0.0))
        #expect(Set([JSONValue.double(-0.0), .double(0.0)]).count == 1)
        #expect(JSONValue.object(["a": .null, "b": .bool(true)]).hashValue
                == JSONValue.object(["b": .bool(true), "a": .null]).hashValue)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(JSONValue.self, from: Data("[1, {".utf8))
        }
    }
}

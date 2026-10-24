import Foundation
import OCFoundation

/// RFC 8785 (JCS) serialization of the JSON the push contracts hash. Members are sorted by the
/// UTF-16 code units of their names and only `"`, `\` and U+0000–U+001F are escaped. Numbers
/// must be integers within ±(2^53 − 1): the contract never hashes anything else, and Swift then
/// needs no ECMAScript number formatting.
public enum CanonicalJSON {
    public struct UnsupportedNumber: Error, Equatable {
        public let value: Double
    }

    private static let maxSafeInteger: Int64 = 9_007_199_254_740_991

    public static func serialize(_ value: JSONValue) throws -> String {
        var output = ""
        try append(value, to: &output)
        return output
    }

    private static func append(_ value: JSONValue, to output: inout String) throws {
        switch value {
        case .null: output += "null"
        case .bool(let flag): output += flag ? "true" : "false"
        case .integer(let number):
            guard (-maxSafeInteger...maxSafeInteger).contains(number) else { throw UnsupportedNumber(value: Double(number)) }
            output += String(number)
        case .double(let number):
            guard number.isFinite, number.rounded() == number, abs(number) <= Double(maxSafeInteger) else { throw UnsupportedNumber(value: number) }
            output += String(Int64(number))
        case .string(let text): quote(text, to: &output)
        case .array(let items):
            output += "["
            for (index, item) in items.enumerated() {
                if index > 0 { output += "," }
                try append(item, to: &output)
            }
            output += "]"
        case .object(let members):
            output += "{"
            for (index, key) in members.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }).enumerated() {
                if index > 0 { output += "," }
                quote(key, to: &output)
                output += ":"
                try append(members[key] ?? .null, to: &output)
            }
            output += "}"
        }
    }

    private static func quote(_ text: String, to output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x08: output += "\\b"
            case 0x09: output += "\\t"
            case 0x0A: output += "\\n"
            case 0x0C: output += "\\f"
            case 0x0D: output += "\\r"
            case 0..<0x20: output += "\\u00" + (scalar.value < 0x10 ? "0" : "") + String(scalar.value, radix: 16)
            default: output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

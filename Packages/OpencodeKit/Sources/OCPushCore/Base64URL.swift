import Foundation

/// RFC 4648 §5 base64url without padding, decoded strictly as `server/contracts` requires:
/// only the alphabet, no `=`, and zero unused trailing bits.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        guard text.utf8.allSatisfy({ isAlphabet($0) }), text.utf8.count % 4 != 1 else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: standard), encode(data) == text else { return nil }
        return data
    }

    /// A-Z, a-z, 0-9, `-` and `_`, which is also the alphabet of a `kid`.
    static func isAlphabet(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }
}

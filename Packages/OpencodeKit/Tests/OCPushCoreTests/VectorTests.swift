import CryptoKit
import Foundation
import OCFoundation
import OCModels
import Testing
@testable import OCPushCore

/// The shared vectors in `server/contracts/vectors`, run against the Swift implementation.
enum Vectors {
    static var contracts: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appending(path: "server/contracts")
    }
    static func json(_ name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: contracts.appending(path: "vectors/\(name)")))
    }
    static func cases(_ name: String, _ key: String) -> [JSONValue] {
        (try? json(name)[key]?.arrayValue) ?? []
    }
    static func bytes(_ segments: JSONValue?) -> Data {
        var data = Data()
        for segment in segments?.arrayValue ?? [] {
            guard let type = segment[0]?.stringValue else { continue }
            switch type {
            case "hex": data.append(hex(segment[1]?.stringValue ?? ""))
            case "zeros": data.append(Data(count: Int(segment[1]?.integerValue ?? 0)))
            default: data.append(contentsOf: (0..<Int(segment[1]?.integerValue ?? 0)).map { UInt8($0 % 251) })
            }
        }
        return data
    }
    static func hex(_ text: String) -> Data {
        var data = Data(), index = text.startIndex
        while index < text.endIndex, let next = text.index(index, offsetBy: 2, limitedBy: text.endIndex), let byte = UInt8(text[index..<next], radix: 16) {
            data.append(byte); index = next
        }
        return data
    }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func name(_ item: JSONValue) -> String { item["name"]?.stringValue ?? "?" }
}

extension JSONValue: CustomTestStringConvertible {
    public var testDescription: String { self["name"]?.stringValue ?? "value" }
}

/// The parameterized tests below pass vacuously without cases, so a moved vector file must fail here.
@Test func everyVectorFileHasCases() {
    let sets = [("jcs.json", "cases"), ("digest.json", "permissions"), ("digest.json", "forms"), ("padding.json", "pad"), ("padding.json", "unpad"),
                ("risk.json", "cases"), ("payload.json", "cases"), ("envelope.json", "valid"), ("envelope.json", "rejections")]
    for (file, key) in sets { #expect(!Vectors.cases(file, key).isEmpty, "\(file) \(key)") }
}

@Test(arguments: Vectors.cases("jcs.json", "cases"))
func canonicalJSONVector(item: JSONValue) throws {
    #expect(try CanonicalJSON.serialize(try #require(item["input"])) == item["canonical"]?.stringValue)
}

@Test(arguments: Vectors.cases("digest.json", "permissions"))
func permissionDigestVector(item: JSONValue) throws {
    let input = try #require(item["input"])
    #expect(try CanonicalJSON.serialize(PushDigest.permissionInput(input)) == item["canonical"]?.stringValue)
    #expect(try PushDigest.permission(raw: input) == item["digest"]?.stringValue)
    #expect(try PushDigest.permission(PermissionRequest(raw: input)) == item["digest"]?.stringValue)
}

@Test(arguments: Vectors.cases("digest.json", "forms"))
func formDigestVector(item: JSONValue) throws {
    let input = try #require(item["input"])
    #expect(try CanonicalJSON.serialize(PushDigest.formInput(input)) == item["canonical"]?.stringValue)
    #expect(try PushDigest.form(FormInfo(raw: input)) == item["digest"]?.stringValue)
}

@Test(arguments: Vectors.cases("padding.json", "pad"))
func paddingVector(item: JSONValue) throws {
    let input = Vectors.bytes(item["input"])
    if item["error"] != nil {
        #expect(throws: PushPadding.Failure.tooLarge) { try PushPadding.pad(input) }
        return
    }
    let padded = try PushPadding.pad(input)
    #expect(Int64(padded.count) == item["length"]?.integerValue)
    #expect(Vectors.hex(Data(SHA256.hash(data: padded))) == item["sha256"]?.stringValue)
    #expect(try PushPadding.unpad(padded) == input)
}

@Test(arguments: Vectors.cases("padding.json", "unpad"))
func unpaddingVector(item: JSONValue) throws {
    let input = Vectors.bytes(item["input"])
    if item["error"] != nil { #expect(throws: PushPadding.Failure.invalid) { try PushPadding.unpad(input) } }
    else { #expect(Vectors.hex(try PushPadding.unpad(input)) == item["output"]?.stringValue) }
}

@Test(arguments: Vectors.cases("risk.json", "cases"))
func riskVector(item: JSONValue) throws {
    let result = PermissionRisk.classify(action: try #require(item["action"]?.stringValue), resources: item["resources"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    #expect(result.tier.rawValue == item["tier"]?.stringValue)
    #expect(result.rule == item["rule"]?.stringValue)
}

@Test(arguments: Vectors.cases("payload.json", "cases"))
func payloadVector(item: JSONValue) throws {
    let plaintext = Data(try #require(item["plaintext"]?.stringValue).utf8)
    #expect(Int64(plaintext.count) == item["bytes"]?.integerValue)
    let payload = try PushPayload(plaintext: plaintext), expected = try #require(item["payload"])
    #expect(payload.kind == expected["kind"]?.stringValue)
    #expect(payload.server == expected["server"]?.stringValue)
    #expect(payload.expiry == expected["exp"]?.integerValue)
    #expect(Int64(payload.pending) == expected["pending"]?.integerValue)
    #expect(payload.title == expected["title"]?.stringValue)
    #expect(payload.summary == expected["summary"]?.stringValue)
    #expect(payload.options == expected["options"]?.arrayValue?.compactMap(\.stringValue))
    #expect(payload.digest == expected["digest"]?.stringValue)
    #expect(PushPadding.bucket(for: plaintext.count).map(Int64.init) == item["bucket"]?.integerValue)
}

private struct Keyring {
    let entries: [String: PushRecipientKey]
    init() throws {
        var entries: [String: PushRecipientKey] = [:]
        for entry in try Vectors.json("envelope.json")["keyring"]?.arrayValue ?? [] {
            guard let kid = entry["kid"]?.stringValue, let privateKey = entry["recipientPrivateKey"]?.stringValue.flatMap(Base64URL.decode),
                  let sender = entry["senderPublicKey"]?.stringValue.flatMap(Base64URL.decode) else { continue }
            entries[kid] = PushRecipientKey(privateKey: privateKey, senderPublicKey: sender)
        }
        self.entries = entries
    }
}

@Test(arguments: Vectors.cases("envelope.json", "valid"))
func envelopeOpensVector(item: JSONValue) throws {
    let keyring = try Keyring()
    let now = Date(timeIntervalSince1970: TimeInterval(try #require(item["now"]?.integerValue)))
    let opened = try PushSealing.open(try #require(item["envelope"]), now: now) { keyring.entries[$0] }
    #expect(String(data: opened.plaintext, encoding: .utf8) == item["plaintext"]?.stringValue)
    #expect(String(data: opened.envelope.additionalData, encoding: .utf8) == item["aad"]?.stringValue)
    #expect(opened.envelope.json == item["envelope"])
}

@Test(arguments: Vectors.cases("envelope.json", "rejections"))
func envelopeRejectionVector(item: JSONValue) throws {
    let keyring = try Keyring()
    let now = Date(timeIntervalSince1970: TimeInterval(try #require(item["now"]?.integerValue)))
    let expected = try #require(item["error"]?.stringValue.flatMap(PushEnvelopeError.init(rawValue:)))
    #expect(throws: expected) { try PushSealing.open(try #require(item["envelope"]), now: now) { keyring.entries[$0] } }
}

@Test func rfc9180AuthModeVector() throws {
    let vector = try Vectors.json("rfc9180-a23.json")
    func field(_ name: String) throws -> Data { Vectors.hex(try #require(vector[name]?.stringValue)) }
    let recipientKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: try field("skRm"))
    #expect(recipientKey.publicKey.rawRepresentation == (try field("pkRm")))
    let senderKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: try field("skSm"))
    #expect(senderKey.publicKey.rawRepresentation == (try field("pkSm")))
    var recipient = try HPKE.Recipient(privateKey: recipientKey, ciphersuite: PushSealing.suite, info: try field("info"),
                                       encapsulatedKey: try field("enc"), authenticatedBy: senderKey.publicKey)
    for item in vector["encryptions"]?.arrayValue ?? [] {
        let opened = try recipient.open(Vectors.hex(item["ct"]?.stringValue ?? ""), authenticating: Vectors.hex(item["aad"]?.stringValue ?? ""))
        #expect(Vectors.hex(opened) == item["pt"]?.stringValue)
    }
}

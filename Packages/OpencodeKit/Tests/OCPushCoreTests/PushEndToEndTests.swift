import Foundation
import OCFoundation
import OCModels
import Testing
@testable import OCPushCore

/// Tools/push-e2e captures the pushes the sandboxed plugin sent through the local relay to the mock
/// APNs, with the device's key, and has the app's code open them. Skipped without that capture.
private let capturePath = ProcessInfo.processInfo.environment["OPENCODE_PUSH_E2E_CAPTURE"]

@Test(.enabled(if: capturePath != nil, "Requires the capture written by Tools/push-e2e"))
func pushesFromTheEndToEndRunOpenInSwift() throws {
    let capture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(capturePath))))
    let keyID = try #require(capture["keyID"]?.stringValue)
    let key = PushRecipientKey(privateKey: try #require(capture["recipientPrivateKey"]?.stringValue.flatMap(Base64URL.decode)),
                               senderPublicKey: try #require(capture["senderPublicKey"]?.stringValue.flatMap(Base64URL.decode)))
    let now = Date(timeIntervalSince1970: TimeInterval(try #require(capture["now"]?.integerValue)))
    let pushes = try #require(capture["pushes"]?.arrayValue)
    #expect(!pushes.isEmpty)
    for push in pushes {
        let envelope = try #require(push["envelope"])
        let opened = try PushSealing.open(envelope, now: now) { $0 == keyID ? key : nil }
        // The same JSON the TypeScript contracts opened, field for field.
        #expect(try JSONDecoder().decode(JSONValue.self, from: opened.plaintext) == push["payload"])
        #expect(opened.payload.kind == push["payload"]?["kind"]?.stringValue)
        if let request = push["request"], request != .null {
            #expect(try PushDigest.permission(raw: request) == opened.payload.digest, "permission digest")
            #expect(PermissionRisk.classify(action: opened.payload.action ?? "", resources: PermissionRequest(raw: request).resources).tier == opened.payload.riskTier)
        }
        if let form = push["form"], form != .null {
            #expect(try PushDigest.form(raw: form) == opened.payload.digest, "form digest")
        }
        // Tampering with the ciphertext or an authenticated field is refused.
        var object = try #require(envelope.objectValue)
        var ciphertext = try #require(object["ct"]?.stringValue.flatMap(Base64URL.decode))
        ciphertext[ciphertext.startIndex] ^= 0x01
        object["ct"] = .string(Base64URL.encode(ciphertext))
        #expect(throws: PushEnvelopeError.authentication) { try PushSealing.open(.object(object), now: now) { _ in key } }
        var later = try #require(envelope.objectValue)
        later["exp"] = .integer(try #require(envelope["exp"]?.integerValue) + 1)
        #expect(throws: PushEnvelopeError.authentication) { try PushSealing.open(.object(later), now: now) { _ in key } }
        print("PASS Swift opened the \(opened.payload.kind) push for \(opened.payload.requestID ?? "-") and refused its tampered copies")
    }
}

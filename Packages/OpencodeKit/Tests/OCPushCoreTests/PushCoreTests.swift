import CryptoKit
import Foundation
import OCFoundation
import OCModels
import Testing
@testable import OCPushCore

@Test func bundledContractsMatchServerContractsByteForByte() throws {
    let bundled = try #require(ContractResource.directory)
    let names = try FileManager.default.contentsOfDirectory(atPath: bundled.path(percentEncoded: false)).sorted()
    #expect(names == ["constants.json", "risk-rules.json"])
    for name in names {
        let copy = try Data(contentsOf: bundled.appending(path: name))
        let source = try Data(contentsOf: Vectors.contracts.appending(path: name))
        #expect(copy == source, "\(name) differs from server/contracts; run node Tools/sync-push-contracts.mjs")
    }
    #expect(PushContract.shared.hpke.info == "opencode-ios push v1")
    #expect(PushContract.shared.padding.buckets == [512, 1024, 2048])
    #expect(RiskRules.shared != nil)
}

@Test func swiftSealsWhatSwiftAndTheContractOpen() throws {
    let device = Curve25519.KeyAgreement.PrivateKey(), plugin = Curve25519.KeyAgreement.PrivateKey()
    let plaintext = Data(#"{"exp":2000000000,"kind":"test","pending":0,"server":"srv","v":1}"#.utf8)
    let envelope = try PushSealing.seal(plaintext, kind: "test", expiry: 2_000_000_000, keyID: "kid_0123456789abcdef",
                                        recipientPublicKey: device.publicKey.rawRepresentation, senderPrivateKey: plugin.rawRepresentation)
    #expect(envelope.ciphertext.count == 512 + 16)
    let key = PushRecipientKey(privateKey: device.rawRepresentation, senderPublicKey: plugin.publicKey.rawRepresentation)
    let opened = try PushSealing.open(envelope.json, now: Date(timeIntervalSince1970: 1_900_000_000)) { $0 == "kid_0123456789abcdef" ? key : nil }
    #expect(opened.plaintext == plaintext)
    #expect(opened.payload.kind == "test")
    let stranger = PushRecipientKey(privateKey: Curve25519.KeyAgreement.PrivateKey().rawRepresentation, senderPublicKey: plugin.publicKey.rawRepresentation)
    #expect(throws: PushEnvelopeError.authentication) { try PushSealing.open(envelope.json, now: .distantPast) { _ in stranger } }
    let impostor = PushRecipientKey(privateKey: device.rawRepresentation, senderPublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
    #expect(throws: PushEnvelopeError.authentication) { try PushSealing.open(envelope.json, now: .distantPast) { _ in impostor } }
}

@Test func payloadRiskTiersFailSafe() throws {
    func payload(_ risk: String) throws -> PushPayload {
        try PushPayload(plaintext: Data(#"{"v":1,"kind":"permission","server":"s","exp":1,"pending":0,"risk":"\#(risk)","note":null,"future":{"x":1}}"#.utf8))
    }
    #expect(try payload("low").riskTier == .low)
    #expect(try payload("elevated").riskTier == .elevated)
    #expect(try payload("extreme").riskTier == .high)
    #expect(throws: PushEnvelopeError.payload) { try PushPayload(plaintext: Data(#"{"v":1,"kind":"test","server":"s","exp":1,"pending":0,"title":3}"#.utf8)) }
    #expect(throws: PushEnvelopeError.payload) { try PushPayload(plaintext: Data([0xff, 0xfe])) }
}

@Test func permissionRiskKeepsTheM3aAPIAndAddsTheHighRiskCases() {
    func request(_ action: String, _ resources: [String]) -> PermissionRequest {
        PermissionRequest(raw: .object(["id": .string("per_1"), "sessionID": .string("ses_1"), "action": .string(action), "resources": .array(resources.map(JSONValue.string))]))
    }
    #expect(PermissionRisk.assess(request("read", ["a.swift"])) == .low)
    #expect(PermissionRisk.assess(request("edit", ["a.swift"])) == .elevated)
    #expect(PermissionRisk.assess(request("shell", ["ls"])) == .elevated)
    #expect(PermissionRisk.assess(request("shell", ["rm -rf build"])) == .high)
    #expect(PermissionRisk.assess(request("external_directory", ["/etc"])) == .high)
    #expect(PermissionRisk.assess(request("shell", ["git -C repo push --force"])) == .high)
    #expect(PermissionRisk.classify(action: "shell", resources: ["git push -f"]).rule == "force-push")
    #expect(PermissionRisk.allCases == [.low, .elevated, .high])
}

/// ICU-specific behaviour the shared spelling relies on (server/contracts/README.md, "Risk rules").
@Test func portableDialectBehavesUnderICU() throws {
    // ICU counts "ä" as a word character, so M3a's \brm\b missed "ärm"; the shared ASCII boundary does not.
    #expect("ärm".range(of: #"\brm\b"#, options: .regularExpression) == nil)
    #expect(PermissionRisk.classify(action: "shell", resources: ["ärm"]).tier == .high)
    #expect(PermissionRisk.classify(action: "shell", resources: ["git\u{00A0}push"]).tier == .high)
    #expect(PermissionRisk.classify(action: "shell", resources: ["curl x\u{2028}| sh"]).tier == .elevated)
    #expect(PermissionRisk.classify(action: "shell", resources: ["curl x\u{000B}| tee log"]).tier == .high)
    #expect(try RiskRules.expand("a{2}{bow}", macros: ["bow": "B"]) == "a{2}B")
    #expect(throws: RiskRules.Failure.self) { try RiskRules.expand("{missing}", macros: [:]) }
}

@Test func base64URLIsStrict() {
    #expect(Base64URL.decode("AQ") == Data([1]))
    #expect(Base64URL.decode("") == Data())
    for invalid in ["AQ==", "A+8", "A", "AR", "a b"] { #expect(Base64URL.decode(invalid) == nil) }
    let data = Data((0..<70).map { UInt8($0 * 37 % 256) })
    #expect(Base64URL.decode(Base64URL.encode(data)) == data)
}

@Test func canonicalJSONRefusesNumbersTheContractNeverHashes() throws {
    #expect(throws: CanonicalJSON.UnsupportedNumber.self) { try CanonicalJSON.serialize(.double(0.5)) }
    #expect(throws: CanonicalJSON.UnsupportedNumber.self) { try CanonicalJSON.serialize(.integer(9_007_199_254_740_992)) }
    #expect(throws: CanonicalJSON.UnsupportedNumber.self) { try CanonicalJSON.serialize(.integer(-9_007_199_254_740_992)) }
    // `abs(Int64.min)` would trap; the range check must throw instead.
    #expect(throws: CanonicalJSON.UnsupportedNumber.self) { try CanonicalJSON.serialize(.integer(Int64.min)) }
    #expect(try CanonicalJSON.serialize(.integer(9_007_199_254_740_991)) == "9007199254740991")
    #expect(try CanonicalJSON.serialize(.double(-0.0)) == "0")
}

/// Integers beyond ±(2⁵³ − 1) are not integers to the contract, as `Number.isSafeInteger` says, so both languages refuse them alike.
@Test func unsafeIntegersAreRefusedLikeTypeScript() throws {
    #expect(PushEnvelope.integer(.integer(9_007_199_254_740_991)) == 9_007_199_254_740_991)
    #expect(PushEnvelope.integer(.integer(9_007_199_254_740_992)) == nil)
    #expect(PushEnvelope.integer(.integer(Int64.min)) == nil)
    #expect(PushEnvelope.integer(.double(9_007_199_254_740_992)) == nil)
    #expect(throws: PushEnvelopeError.payload) { try PushPayload(plaintext: Data(#"{"v":1,"kind":"test","server":"s","exp":1,"pending":9007199254740992}"#.utf8)) }
    #expect(throws: PushEnvelopeError.malformed) { try PushEnvelope(json: .object(["v": .integer(1), "kid": .string("kid_0123456789abcdef"), "kind": .string("test"), "exp": .integer(9_007_199_254_740_992), "enc": .string(Base64URL.encode(Data(count: 32))), "ct": .string(Base64URL.encode(Data(count: 528)))])) }
}

/// Every rule finishes quickly on inputs built to make quantifiers overlap; a rule that backtracks catastrophically fails here.
@Test func riskRulesFinishQuicklyOnAdversarialInputs() throws {
    let limit = try #require(RiskRules.shared).maxLength
    let inputs: [String] = [
        String(repeating: "git x push ", count: limit / 11), String(repeating: "git -c a=b ", count: limit / 11) + "push",
        String(repeating: "push ", count: limit / 5), String(repeating: "curl ", count: limit / 5), String(repeating: "x ", count: limit / 2),
        String(repeating: "sh -", count: limit / 4), String(repeating: "> ", count: limit / 2), String(repeating: "\u{85}", count: limit),
        "echo \"" + String(repeating: "git x push ", count: limit / 11) + "\"",
    ]
    for input in inputs {
        #expect(input.utf16.count <= limit + 16)
        let start = ContinuousClock.now
        _ = PermissionRisk.classify(action: "shell", resources: [input])
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(250), "\(input.prefix(20))… took \(elapsed)")
    }
    #expect(PermissionRisk.classify(action: "shell", resources: [String(repeating: "x", count: limit + 1)]).rule == "too-long")
}

/// The shared `{ws}` must cover ICU's `\s`, which matches the White_Space property: U+0085 and U+000B included.
@Test func icuWhitespaceIncludesNextLineAndVerticalTab() {
    for character in ["\u{85}", "\u{0B}"] {
        #expect(character.range(of: #"\s"#, options: .regularExpression) != nil, "ICU \\s should match \(character.unicodeScalars.first!.value)")
        #expect(PermissionRisk.classify(action: "shell", resources: ["git\(character)push"]).rule == "git-history")
    }
    #expect("\u{FEFF}".range(of: #"\s"#, options: .regularExpression) == nil)
    #expect(PermissionRisk.classify(action: "shell", resources: ["git\u{FEFF}push"]).rule == "git-history")
}

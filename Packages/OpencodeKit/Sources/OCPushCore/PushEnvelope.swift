import CryptoKit
import Foundation
import OCFoundation

/// Why an envelope was refused, in the order `server/contracts` checks: structure, version,
/// expiry, key, authentication, padding, payload, then kind and expiry agreement.
public enum PushEnvelopeError: String, Error, Sendable, CaseIterable {
    case malformed, unsupportedVersion, expired, unknownKey, authentication, padding, payload, mismatch
}

/// The APNs payload's `oc` object. Everything but the ciphertext is visible to the relay, and
/// `aad` binds those fields to it.
public struct PushEnvelope: Sendable, Equatable {
    public let keyID: String
    public let kind: String
    /// Unix seconds; the envelope is expired once now >= expiry.
    public let expiry: Int64
    public let encapsulatedKey: Data
    public let ciphertext: Data

    private static let latestExpiry: Int64 = 4_102_444_800

    public init(keyID: String, kind: String, expiry: Int64, encapsulatedKey: Data, ciphertext: Data) {
        self.keyID = keyID; self.kind = kind; self.expiry = expiry
        self.encapsulatedKey = encapsulatedKey; self.ciphertext = ciphertext
    }

    public init(json: JSONValue) throws {
        guard let object = json.objectValue else { throw PushEnvelopeError.malformed }
        let contract = PushContract.shared
        guard let version = Self.integer(object["v"]) else { throw PushEnvelopeError.malformed }
        guard version == Int64(contract.envelope.version) else { throw PushEnvelopeError.unsupportedVersion }
        guard let keyID = object["kid"]?.stringValue, (16...64).contains(keyID.utf8.count), keyID.utf8.allSatisfy(Base64URL.isAlphabet),
              let kind = object["kind"]?.stringValue, contract.kinds[kind] != nil,
              let expiry = Self.integer(object["exp"]), (0...Self.latestExpiry).contains(expiry),
              let enc = object["enc"]?.stringValue, let key = Base64URL.decode(enc), key.count == contract.envelope.keyBytes,
              let ct = object["ct"]?.stringValue, ct.utf8.count <= contract.envelope.maxEncodedCiphertext,
              let ciphertext = Base64URL.decode(ct), contract.padding.buckets.map({ $0 + contract.envelope.tagBytes }).contains(ciphertext.count)
        else { throw PushEnvelopeError.malformed }
        self.init(keyID: keyID, kind: kind, expiry: expiry, encapsulatedKey: key, ciphertext: ciphertext)
    }

    public var json: JSONValue {
        .object([
            "v": .integer(Int64(PushContract.shared.envelope.version)), "kid": .string(keyID), "kind": .string(kind),
            "exp": .integer(expiry), "enc": .string(Base64URL.encode(encapsulatedKey)), "ct": .string(Base64URL.encode(ciphertext)),
        ])
    }

    /// "oc1|kind|exp|kid" in UTF-8.
    public var additionalData: Data { Data("\(PushContract.shared.envelope.aadPrefix)|\(kind)|\(expiry)|\(keyID)".utf8) }

    /// An integer within ±(2⁵³ − 1), as ECMAScript's `Number.isSafeInteger` accepts; anything else is not an integer here.
    static func integer(_ value: JSONValue?) -> Int64? {
        let safe: ClosedRange<Int64> = -9_007_199_254_740_991...9_007_199_254_740_991
        switch value {
        case .integer(let number) where safe.contains(number): return number
        case .double(let number) where number.rounded() == number && abs(number) <= 9_007_199_254_740_991: return Int64(number)
        default: return nil
        }
    }
}

/// The device's key for one paired server, as the extension finds it by `kid`.
public struct PushRecipientKey: Sendable {
    /// Raw 32-byte X25519 private key (`rawRepresentation`).
    public let privateKey: Data
    /// The plugin's static public key, pinned at registration.
    public let senderPublicKey: Data
    public init(privateKey: Data, senderPublicKey: Data) {
        self.privateKey = privateKey; self.senderPublicKey = senderPublicKey
    }
}

public struct OpenedPush: Sendable {
    public let envelope: PushEnvelope
    public let plaintext: Data
    public let payload: PushPayload
}

/// HPKE auth mode: DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, ChaCha20-Poly1305.
public enum PushSealing {
    static let suite = HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .chaChaPoly)
    static var info: Data { Data(PushContract.shared.hpke.info.utf8) }

    /// Opens an envelope. Throws `PushEnvelopeError`.
    public static func open(_ json: JSONValue, now: Date, key: (String) -> PushRecipientKey?) throws -> OpenedPush {
        let envelope = try PushEnvelope(json: json)
        guard Int64(now.timeIntervalSince1970.rounded(.down)) < envelope.expiry else { throw PushEnvelopeError.expired }
        guard let entry = key(envelope.keyID) else { throw PushEnvelopeError.unknownKey }
        let padded: Data
        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: entry.privateKey)
            let sender = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: entry.senderPublicKey)
            var recipient = try HPKE.Recipient(privateKey: privateKey, ciphersuite: suite, info: info,
                                               encapsulatedKey: envelope.encapsulatedKey, authenticatedBy: sender)
            padded = try recipient.open(envelope.ciphertext, authenticating: envelope.additionalData)
        } catch { throw PushEnvelopeError.authentication }
        let plaintext: Data
        do { plaintext = try PushPadding.unpad(padded) } catch { throw PushEnvelopeError.padding }
        let payload = try PushPayload(plaintext: plaintext)
        guard payload.kind == envelope.kind, payload.expiry == envelope.expiry else { throw PushEnvelopeError.mismatch }
        return OpenedPush(envelope: envelope, plaintext: plaintext, payload: payload)
    }

    /// Seals a plaintext the way the plugin does; for tests and diagnostics. CryptoKit chooses a
    /// fresh ephemeral key, so two seals of the same plaintext differ.
    public static func seal(_ plaintext: Data, kind: String, expiry: Int64, keyID: String,
                            recipientPublicKey: Data, senderPrivateKey: Data) throws -> PushEnvelope {
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let sender = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: senderPrivateKey)
        var context = try HPKE.Sender(recipientKey: recipient, ciphersuite: suite, info: info, authenticatedBy: sender)
        let unsealed = PushEnvelope(keyID: keyID, kind: kind, expiry: expiry, encapsulatedKey: context.encapsulatedKey, ciphertext: Data())
        let ciphertext = try context.seal(try PushPadding.pad(plaintext), authenticating: unsealed.additionalData)
        return PushEnvelope(keyID: keyID, kind: kind, expiry: expiry, encapsulatedKey: context.encapsulatedKey, ciphertext: ciphertext)
    }
}

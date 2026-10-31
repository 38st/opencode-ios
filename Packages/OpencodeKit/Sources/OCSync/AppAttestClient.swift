import CryptoKit
import Foundation
import OCFoundation
import OCNetworking
import OCSecurity

public enum AppAttestError: Error, Equatable, Sendable {
    /// The relay refused the registration, with its error code.
    case refused(status: Int, code: String?)
}

/// Registers this device with the relay, proving with App Attest that the request comes from this app on a
/// genuine device when the relay asks for it.
///
/// States: no key → generated key (kept in the Keychain) → attested key (the relay stored it). A relay with
/// App Attest off answers the challenge route with 404, and registration goes ahead without an assertion, as
/// it does on devices without App Attest (the simulator among them).
@MainActor public final class AppAttestClient {
    public typealias Exchange = @Sendable (HTTPMethod, String, [String: String], Data?) async throws -> RelayReply
    struct Stored: Codable, Equatable {
        var keyID: String
        var attested: Bool
    }
    static let account = "app-attest"
    private let service: (any AppAttestService)?
    private let secrets: any SecretStore
    private let exchange: Exchange

    public init(service: (any AppAttestService)?, secrets: any SecretStore, exchange: @escaping Exchange) {
        self.service = service; self.secrets = secrets; self.exchange = exchange
    }

    /// `POST /v1/devices` with `fields`, attested when the relay requires it. Returns the relay's answer.
    public func registerDevice(_ fields: [String: JSONValue]) async throws -> JSONValue {
        for attempt in 0..<2 {
            guard let service, service.isSupported else { return try await plain(fields) }
            let first = try await exchange(.post, "/v1/attest/challenge", [:], Data("{}".utf8))
            if first.status == 404 { return try await plain(fields) }
            let challenge = try challengeValue(first)
            let (keyID, used) = try await attestedKey(service, challenge: challenge)
            var body = fields
            // A challenge works once: an attestation that used it needs a new one for the assertion.
            if used { body["challenge"] = .string(try challengeValue(await exchange(.post, "/v1/attest/challenge", [:], Data("{}".utf8)))) }
            else { body["challenge"] = .string(challenge) }
            let data = try Self.encode(body)
            let assertion = try await service.generateAssertion(keyID, clientDataHash: Data(SHA256.hash(data: data)))
            let reply = try await exchange(.post, "/v1/devices", ["X-App-Attest-Key": keyID, "X-App-Attest-Assertion": assertion.base64EncodedString()], data)
            // The relay lost the key (or never stored it): attest a new one once.
            if reply.status == 401, reply.error == "attest_key_unknown", attempt == 0 { try await forget(); continue }
            if reply.status == 401, reply.error == "attestation_invalid" { try await forget() }
            return try result(reply)
        }
        throw AppAttestError.refused(status: 401, code: "attest_key_unknown")
    }

    /// The attested key, attesting one first if needed. `used` is true when the challenge went into an attestation.
    private func attestedKey(_ service: any AppAttestService, challenge: String) async throws -> (String, used: Bool) {
        let stored = try await load()
        if let stored, stored.attested { return (stored.keyID, false) }
        var keyID: String
        if let stored { keyID = stored.keyID } else { keyID = try await newKey(service) }
        let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation: Data
        do { attestation = try await service.attestKey(keyID, clientDataHash: hash) }
        catch AppAttestServiceError.invalidKey {
            // A key that failed or was already attested on the device: start over with a fresh one.
            keyID = try await newKey(service)
            attestation = try await service.attestKey(keyID, clientDataHash: hash)
        }
        let body = try Self.encode(["keyID": .string(keyID), "challenge": .string(challenge), "attestation": .string(attestation.base64EncodedString())])
        let reply = try await exchange(.post, "/v1/attest/keys", [:], body)
        switch reply.status {
        case 201, 409: try await save(.init(keyID: keyID, attested: true))
        default:
            if reply.status == 401 { try await forget() }
            throw AppAttestError.refused(status: reply.status, code: reply.error)
        }
        return (keyID, true)
    }

    private func newKey(_ service: any AppAttestService) async throws -> String {
        let keyID = try await service.generateKey()
        try await save(.init(keyID: keyID, attested: false))
        return keyID
    }
    private func plain(_ fields: [String: JSONValue]) async throws -> JSONValue {
        try result(await exchange(.post, "/v1/devices", [:], Self.encode(fields)))
    }
    private func challengeValue(_ reply: RelayReply) throws -> String {
        guard reply.status == 201, let value = reply.body["challenge"]?.stringValue else {
            throw AppAttestError.refused(status: reply.status, code: reply.error)
        }
        return value
    }
    private func result(_ reply: RelayReply) throws -> JSONValue {
        guard (200..<300).contains(reply.status) else { throw AppAttestError.refused(status: reply.status, code: reply.error) }
        return reply.body
    }
    func load() async throws -> Stored? {
        guard let data = try await secrets.read(account: Self.account) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }
    private func save(_ value: Stored) async throws { try await secrets.write(JSONEncoder().encode(value), account: Self.account) }
    private func forget() async throws { try await secrets.delete(account: Self.account) }
    /// Sorted keys, so the bytes the assertion signs are the bytes sent.
    static func encode(_ value: [String: JSONValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(value))
    }
}

import CryptoKit
import Foundation
import Testing
import OCFoundation
import OCNetworking
import OCSecurity
@testable import OCSync

private actor FakeAttestService: AppAttestService {
    nonisolated let isSupported: Bool
    private(set) var generated: [String] = []
    private(set) var attested: [(String, Data)] = []
    private(set) var asserted: [(String, Data)] = []
    var invalidKeys: Set<String> = []
    init(supported: Bool = true) { isSupported = supported }
    func invalidate(_ keyID: String) { invalidKeys.insert(keyID) }
    func generateKey() -> String { let key = "key\(generated.count + 1)"; generated.append(key); return key }
    func attestKey(_ keyID: String, clientDataHash: Data) throws -> Data {
        if invalidKeys.contains(keyID) { throw AppAttestServiceError.invalidKey }
        attested.append((keyID, clientDataHash)); return Data("attestation-\(keyID)".utf8)
    }
    func generateAssertion(_ keyID: String, clientDataHash: Data) -> Data {
        asserted.append((keyID, clientDataHash)); return Data("assertion-\(keyID)".utf8)
    }
}

/// A relay that follows the routes: challenges, key attestation and device registration.
private actor FakeRelay {
    var appAttest = true
    var forgetKeys = false
    var keys: Set<String> = []
    var challenges: [String] = []
    var calls: [(path: String, headers: [String: String], body: Data?)] = []
    func setForgetKeys(_ value: Bool) { forgetKeys = value }
    func exchange(_ method: HTTPMethod, _ path: String, _ headers: [String: String], _ body: Data?) -> RelayReply {
        calls.append((path, headers, body))
        let json = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        switch path {
        case "/v1/attest/challenge":
            guard appAttest else { return .init(status: 404, body: .object(["error": .string("not_found")])) }
            let value = "atc_\(challenges.count)"; challenges.append(value)
            return .init(status: 201, body: .object(["challenge": .string(value)]))
        case "/v1/attest/keys":
            let key = json?["keyID"]?.stringValue ?? ""
            if keys.contains(key) { return .init(status: 409, body: .object(["error": .string("key_exists")])) }
            keys.insert(key); return .init(status: 201, body: .object(["keyID": .string(key)]))
        default:
            if forgetKeys { keys.removeAll(); forgetKeys = false }
            if appAttest {
                guard let key = headers["X-App-Attest-Key"] else { return .init(status: 401, body: .object(["error": .string("attestation_required")])) }
                guard keys.contains(key) else { return .init(status: 401, body: .object(["error": .string("attest_key_unknown")])) }
            }
            return .init(status: 201, body: .object(["deviceID": .string("dev"), "deviceSecret": .string("secret")]))
        }
    }
    var paths: [String] { calls.map(\.path) }
}

@MainActor @Suite struct AppAttestClientTests {
    private let fields: [String: JSONValue] = ["apnsToken": .string("ab"), "env": .string("sandbox"), "bundleID": .string("dev.example")]
    private func client(_ service: FakeAttestService?, _ relay: FakeRelay, secrets: any SecretStore = InMemorySecretStore()) -> AppAttestClient {
        AppAttestClient(service: service, secrets: secrets) { method, path, headers, body in await relay.exchange(method, path, headers, body) }
    }

    @Test func unsupportedDevicesAndRelaysWithAppAttestOffRegisterPlainly() async throws {
        let unsupported = client(FakeAttestService(supported: false), FakeRelay())
        await #expect(throws: AppAttestError.refused(status: 401, code: "attestation_required")) { try await unsupported.registerDevice(fields) }

        let off = FakeRelay(); await off.setAppAttest(false)
        let service = FakeAttestService()
        let result = try await client(service, off).registerDevice(fields)
        #expect(result["deviceID"]?.stringValue == "dev")
        #expect(await off.paths == ["/v1/attest/challenge", "/v1/devices"])
        #expect(await off.calls.last?.headers.isEmpty == true)
        #expect(await service.generated.isEmpty)
    }

    @Test func attestsOnceThenAssertsOverTheExactBody() async throws {
        let relay = FakeRelay(), service = FakeAttestService(), secrets = InMemorySecretStore()
        let attest = client(service, relay, secrets: secrets)
        _ = try await attest.registerDevice(fields)
        #expect(await relay.paths == ["/v1/attest/challenge", "/v1/attest/keys", "/v1/attest/challenge", "/v1/devices"])
        let attested = try #require(await service.attested.first)
        #expect(attested.1 == Data(SHA256.hash(data: Data("atc_0".utf8))))
        let registration = try #require(await relay.calls.last)
        #expect(registration.headers["X-App-Attest-Key"] == "key1")
        let body = try #require(registration.body)
        #expect(try JSONDecoder().decode(JSONValue.self, from: body)["challenge"]?.stringValue == "atc_1")
        #expect(await service.asserted.last?.1 == Data(SHA256.hash(data: body)))
        #expect(try await attest.load() == .init(keyID: "key1", attested: true))

        _ = try await attest.registerDevice(fields)
        #expect(await relay.paths.suffix(2) == ["/v1/attest/challenge", "/v1/devices"])
        #expect(await service.generated == ["key1"])
        #expect(await service.attested.count == 1)
    }

    @Test func aRelayThatLostTheKeyGetsANewOneOnce() async throws {
        let relay = FakeRelay(), service = FakeAttestService()
        let attest = client(service, relay)
        _ = try await attest.registerDevice(fields)
        await relay.setForgetKeys(true)
        _ = try await attest.registerDevice(fields)
        // A device key can be attested only once, so the retry uses a new key.
        #expect(await service.generated == ["key1", "key2"])
        #expect(await service.attested.map(\.0) == ["key1", "key2"])
        #expect(await relay.calls.last?.headers["X-App-Attest-Key"] == "key2")
    }

    @Test func anInvalidDeviceKeyIsReplaced() async throws {
        let relay = FakeRelay(), service = FakeAttestService(), secrets = InMemorySecretStore()
        try await secrets.write(JSONEncoder().encode(AppAttestClient.Stored(keyID: "stale", attested: false)), account: AppAttestClient.account)
        await service.invalidate("stale")
        _ = try await client(service, relay, secrets: secrets).registerDevice(fields)
        #expect(await service.generated == ["key1"])
        #expect(await relay.calls.last?.headers["X-App-Attest-Key"] == "key1")
    }
}

private extension FakeRelay {
    func setAppAttest(_ value: Bool) { appAttest = value }
}

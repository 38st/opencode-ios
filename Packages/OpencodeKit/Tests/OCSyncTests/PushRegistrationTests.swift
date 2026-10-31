import CryptoKit
import Foundation
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCPushCore
import OCSecurity
import OCShared
@testable import OCSync

private actor RelayFake {
    var calls: [(HTTPMethod, String)] = []
    var senders = 0
    var failing = false
    func setFailing(_ value: Bool) { failing = value }
    func request(_ method: HTTPMethod, _ path: String, _ secret: String?, _ body: JSONValue?) throws -> JSONValue {
        if failing { throw URLError(.cannotConnectToHost) }
        calls.append((method, path))
        if method == .post && path == "/v1/devices" { return .object(["deviceID": .string("device"), "deviceSecret": .string("secret")]) }
        if method == .post && path.hasSuffix("/senders") {
            senders += 1; return .object(["senderID": .string("sender\(senders)"), "sendToken": .string("token\(senders)")])
        }
        return .null
    }
}
@MainActor @Suite struct PushRegistrationTests {
    @Test func unreachableRelayShowsInDeliveryHealth() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PushRegistration(relayURL: try #require(URL(string: "https://relay.example.invalid")),
            keys: PushKeyStore(secrets: InMemorySecretStore()), store: PushSnapshotStore(directory: root),
            secrets: InMemorySecretStore(), relay: { _, _, _, _ in throw PushRelayError.unreachable })
        await #expect(throws: PushRelayError.unreachable) { try await manager.registerToken("token", bundleID: "dev.example") }
        #expect(manager.relayState == "Relay unreachable")
    }
    @Test func registrationRotationSeparateSendersAndUnpair() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PushSnapshotStore(directory: root), relay = RelayFake(), secrets = InMemorySecretStore()
        let keys = PushKeyStore(secrets: InMemorySecretStore())
        let manager = PushRegistration(relayURL: try #require(URL(string: "https://relay.example.invalid")), keys: keys, store: store, secrets: secrets, relay: { method, path, secret, body in try await relay.request(method, path, secret, body) })
        let senderPublicKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        var inputs: [JSONValue] = [], removed: [String] = [], activities: [JSONValue] = []
        let rpc: PushRegistration.RPC = { method, input in
            if method == "registerDevice" { inputs.append(input) }
            if method == "registerActivity" { activities.append(input) }
            if method == "unregisterDevice" { removed.append(input["keyID"]?.stringValue ?? "") }
            return .object(["serverPublicKey": .string(Base64URL.encode(senderPublicKey)), "pluginVersion": .string("0.1.0"), "devices": .array([])])
        }
        await #expect(throws: PushRegistrationError.self) {
            try await manager.registerActivity(token: "activity-token", ref: "activity", expiresAt: .now,
                server: ServerID(), sessionID: "ses_test", rpc: rpc)
        }
        #expect(await relay.calls.isEmpty)
        try await manager.registerToken("token1", bundleID: "test")
        try await manager.registerToken("token2", bundleID: "test")
        let one = ServerID(), two = ServerID()
        await manager.register(server: one, name: "one", rpc: rpc)
        await manager.register(server: two, name: "two", rpc: rpc)
        await manager.register(server: one, name: "one", rpc: rpc)
        #expect(await relay.senders == 2)
        #expect(inputs[0]["sendToken"] != inputs[1]["sendToken"])
        #expect(inputs[0]["keyID"] == inputs[2]["keyID"])
        #expect(await relay.calls.filter { $0.0 == .post && $0.1 == "/v1/devices" }.count == 1)
        #expect(await relay.calls.contains { $0.0 == .put && $0.1 == "/v1/devices/device" })
        let key = try #require(try await keys.existingKey(for: one))
        #expect(try store.server(keyID: key.keyID) == one.rawValue.uuidString)
        try await manager.registerActivity(token: "activity-token", ref: "activity", expiresAt: .now.addingTimeInterval(3600),
            server: one, sessionID: "ses_test", rpc: rpc)
        #expect(await relay.calls.contains { $0.0 == .put && $0.1 == "/v1/devices/device/activities/activity" })
        #expect(activities == [.object(["keyID": .string(key.keyID), "activityRef": .string("activity"), "sessionID": .string("ses_test")])])
        await manager.unregister(server: one, rpc: rpc)
        #expect(removed == [key.keyID])
        #expect(try await keys.existingKey(for: one) == nil)
        #expect(try await keys.existingKey(for: two) != nil)
        #expect(try store.server(keyID: key.keyID) == nil)
        #expect(await relay.calls.contains { $0.0 == .delete && $0.1.hasSuffix("/sender1") })
        await manager.register(server: ServerID(), name: "missing") { _, _ in throw APIError.server(tag: "NotFound", status: 404, body: .null) }
        #expect(manager.health.values.contains { $0.pluginMissing })
        #expect(await relay.senders == 2)
        // Unpairing an unreachable server (no RPC, relay down) still removes every local trace and queues the
        // relay revocation for the next token registration.
        let twoKey = try #require(try await keys.existingKey(for: two))
        await relay.setFailing(true)
        await manager.unregister(server: two) { _, _ in throw URLError(.cannotConnectToHost) }
        #expect(try await keys.existingKey(for: two) == nil)
        #expect(try store.server(keyID: twoKey.keyID) == nil)
        #expect(await secrets.read(account: "sender." + two.rawValue.uuidString) == nil)
        #expect(manager.health[two.rawValue.uuidString] == nil)
        #expect(manager.pendingRevocations == [two.rawValue.uuidString])
        // A relaunch never loses the queue: neither another failed unpair nor the launch's token registration
        // may write before the saved list is loaded.
        let relaunch = { PushRegistration(relayURL: manager.relayURL, keys: keys, store: store, secrets: secrets, relay: { method, path, secret, body in try await relay.request(method, path, secret, body) }) }
        let three = ServerID()
        try await secrets.write(JSONEncoder().encode(["senderID": "sender3", "sendToken": "token3"]), account: "sender." + three.rawValue.uuidString)
        let offline = relaunch()
        await offline.unregister(server: three) { _, _ in throw URLError(.cannotConnectToHost) }
        #expect(offline.pendingRevocations == [two.rawValue.uuidString, three.rawValue.uuidString])
        await relay.setFailing(false)
        let online = relaunch()
        try await online.registerToken("token3", bundleID: "test")
        #expect(online.pendingRevocations.isEmpty)
        #expect(await relay.calls.contains { $0.0 == .delete && $0.1.hasSuffix("/sender2") })
        #expect(await relay.calls.contains { $0.0 == .delete && $0.1.hasSuffix("/sender3") })
        #expect(await secrets.read(account: "revoke." + two.rawValue.uuidString) == nil)
        #expect(await secrets.read(account: "revoke." + three.rawValue.uuidString) == nil)
        await online.loadPendingRevocations()
        #expect(online.pendingRevocations.isEmpty)
        // The App Group never contains either app-only relay secret.
        for url in FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [] where url.pathExtension == "json" {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("secret") && !text.contains("sendToken"))
        }
    }
}

/// Relay or direct to Apple, chosen per server: in direct mode the plugin receives the APNs and Live Activity
/// tokens over the server connection, and the relay is never asked for a sender.
@MainActor @Suite struct PushDeliveryChoiceTests {
    private func setup(direct: Bool, available: Bool) throws -> (PushRegistration, RelayFake, ServerID, PushRegistration.RPC, () -> [String: [JSONValue]], URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = PushSnapshotStore(directory: root), relay = RelayFake(), server = ServerID()
        var preferences = PushPreferences()
        if direct { preferences.directServers.insert(server.rawValue.uuidString) }
        try store.save(preferences: preferences)
        let manager = PushRegistration(relayURL: try #require(URL(string: "https://relay.example.invalid")), keys: PushKeyStore(secrets: InMemorySecretStore()),
            store: store, secrets: InMemorySecretStore(), relay: { method, path, secret, body in try await relay.request(method, path, secret, body) })
        let serverKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        var calls: [String: [JSONValue]] = [:]
        let rpc: PushRegistration.RPC = { method, input in
            calls[method, default: []].append(input)
            if method == "status" {
                return .object(["pluginVersion": .string("0.2.0"), "direct": .object(available
                    ? ["available": .bool(true), "bundleID": .string("dev.example.client"), "environment": .string("sandbox")]
                    : ["available": .bool(false)])])
            }
            return .object(["serverPublicKey": .string(Base64URL.encode(serverKey)), "pluginVersion": .string("0.2.0"), "devices": .array([])])
        }
        return (manager, relay, server, rpc, { calls }, root)
    }

    @Test func directModeRegistersTheAPNsTokenWithThePluginOnly() async throws {
        let (manager, relay, server, rpc, calls, root) = try setup(direct: true, available: true)
        defer { try? FileManager.default.removeItem(at: root) }
        await relay.setFailing(true) // The relay being down does not matter in direct mode.
        try? await manager.registerToken("abcd1234", bundleID: "dev.example.client", environment: "sandbox")
        await manager.register(server: server, name: "direct", rpc: rpc)
        let input = try #require(calls()["registerDevice"]?.first)
        #expect(input["transport"] == .string("direct"))
        #expect(input["apnsToken"] == .string("abcd1234"))
        #expect(input["bundleID"] == .string("dev.example.client"))
        #expect(input["environment"] == .string("sandbox"))
        #expect(input["sendToken"] == nil && input["relayURL"] == nil)
        #expect(manager.health[server.rawValue.uuidString]?.isRegistered == true)
        #expect(manager.health[server.rawValue.uuidString]?.directAvailable == true)

        try await manager.registerActivity(token: "beef", ref: "activity", expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                                           server: server, sessionID: "ses_test", rpc: rpc)
        let activity = try #require(calls()["registerActivity"]?.first)
        #expect(activity["pushToken"] == .string("beef"))
        #expect(activity["expiresAt"] == .integer(2_000_000_000))
        #expect(await relay.calls.isEmpty)
    }

    @Test func directModeWithoutAKeyOnTheServerSaysSoAndRegistersNothing() async throws {
        let (manager, relay, server, rpc, calls, root) = try setup(direct: true, available: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try await manager.registerToken("abcd1234", bundleID: "dev.example.client")
        await manager.register(server: server, name: "direct", rpc: rpc)
        #expect(calls()["registerDevice"] == nil)
        #expect(manager.health[server.rawValue.uuidString]?.isRegistered == false)
        #expect(await relay.calls.map(\.1) == ["/v1/devices"])
    }

    @Test func relayModeStaysTheDefault() async throws {
        let (manager, relay, server, rpc, calls, root) = try setup(direct: false, available: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await manager.registerToken("abcd1234", bundleID: "dev.example.client")
        await manager.register(server: server, name: "relay", rpc: rpc)
        let input = try #require(calls()["registerDevice"]?.first)
        #expect(input["transport"] == nil)
        #expect(input["sendToken"] != nil && input["apnsToken"] == nil)
        #expect(await relay.calls.map(\.1).contains { $0.hasSuffix("/senders") })
        #expect(manager.isDirect(server.rawValue.uuidString) == false)
    }
}

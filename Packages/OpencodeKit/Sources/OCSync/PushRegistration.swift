import Foundation
import Observation
import OCFoundation
import OCModels
import OCNetworking
import OCPushCore
import OCSecurity
import OCShared

public struct PushServerHealth: Sendable, Identifiable {
    public let id: String
    public var name: String
    public var pluginVersion: String?
    public var registration = "Not registered"
    public var pluginMissing = false
    public var lastDelivery: String?
    public var lastDeliveryAt: Date?
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct RelayIdentity: Codable, Sendable {
    public let deviceID: String
    public let deviceSecret: String
}
struct PushSender: Codable, Sendable {
    let senderID: String
    let sendToken: String
}

enum PushRegistrationError: Error { case deviceNotRegistered }

@MainActor @Observable public final class PushRegistration {
    public typealias Relay = @Sendable (HTTPMethod, String, String?, JSONValue?) async throws -> JSONValue
    public typealias RPC = @MainActor @Sendable (String, JSONValue) async throws -> JSONValue
    public private(set) var relayState = "Waiting for notification permission"
    public private(set) var health: [String: PushServerHealth] = [:]
    /// Removed servers whose relay sender could not be revoked yet; retried on every token registration.
    public private(set) var pendingRevocations: [String] = []
    public let relayURL: URL
    public let keys: PushKeyStore
    public let store: PushSnapshotStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let relay: Relay
    @ObservationIgnored private var registering: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var tokenTask: Task<Void, any Error>?
    @ObservationIgnored private var revocationsLoaded = false

    public init(relayURL: URL, keys: PushKeyStore, store: PushSnapshotStore, secrets: any SecretStore, relay: @escaping Relay) {
        self.relayURL = relayURL; self.keys = keys; self.store = store; self.secrets = secrets; self.relay = relay
    }
    deinit { tokenTask?.cancel(); for task in registering.values { task.cancel() } }
    public func unavailable() { relayState = "APNs registration unavailable in this build" }
    public func registerToken(_ token: String, bundleID: String, environment: String = "sandbox") async throws {
        let previous = tokenTask
        let task = Task { [self] in
            _ = try? await previous?.value
            try Task.checkCancellation()
            if let identity = try await identity() {
                _ = try await relay(.put, "/v1/devices/" + identity.deviceID, identity.deviceSecret,
                                    .object(["apnsToken": .string(token), "env": .string(environment)]))
            } else {
                let raw = try await relay(.post, "/v1/devices", nil,
                    .object(["apnsToken": .string(token), "env": .string(environment), "bundleID": .string(bundleID)]))
                let identity = try JSONDecoder().decode(RelayIdentity.self, from: JSONEncoder().encode(raw))
                try await secrets.write(JSONEncoder().encode(identity), account: "device")
            }
            relayState = "Registered"
        }
        tokenTask = task
        do { try await task.value }
        catch PushRelayError.unreachable { relayState = "Relay unreachable"; throw PushRelayError.unreachable }
        catch { relayState = "Could not register with the relay"; throw error }
        await retryRevocations()
    }
    public func identity() async throws -> RelayIdentity? {
        guard let data = try await secrets.read(account: "device") else { return nil }
        return try JSONDecoder().decode(RelayIdentity.self, from: data)
    }
    public func register(server: ServerID, name: String, rpc: @escaping RPC) async {
        let ref = server.rawValue.uuidString
        if let task = registering[ref] { await task.value; return }
        let task = Task { [self] in
            var state = PushServerHealth(id: ref, name: name)
            defer { health[ref] = state }
            do {
                let status = try await rpc("status", .object([:]))
                state.pluginVersion = status["pluginVersion"]?.stringValue
                guard let identity = try await identity(), relayState == "Registered" else { state.registration = "Waiting for APNs registration"; return }
                let key = try await keys.key(for: server)
                let sender: PushSender
                if let data = try await secrets.read(account: "sender." + ref) {
                    sender = try JSONDecoder().decode(PushSender.self, from: data)
                } else {
                    let raw = try await relay(.post, "/v1/devices/\(identity.deviceID)/senders", identity.deviceSecret, nil)
                    sender = try JSONDecoder().decode(PushSender.self, from: JSONEncoder().encode(raw))
                    try await secrets.write(JSONEncoder().encode(sender), account: "sender." + ref)
                }
                let output = try await rpc("registerDevice", .object([
                    "sendToken": .string(sender.sendToken), "relayURL": .string(relayURL.absoluteString),
                    "devicePublicKey": .string(Base64URL.encode(key.publicKey)), "keyID": .string(key.keyID),
                    "appServerRef": .string(ref), "label": .string("Opencode iOS"), "prefs": .object([:])]))
                guard let encoded = output["serverPublicKey"]?.stringValue, let pinned = Base64URL.decode(encoded) else { throw PushEnvelopeError.authentication }
                try await keys.pin(serverPublicKey: pinned, for: server)
                try store.register(keyID: key.keyID, server: ref)
                state.pluginVersion = output["pluginVersion"]?.stringValue
                state.registration = "Registered"
                let devices = try await rpc("listDevices", .object([:]))
                if let device = devices["devices"]?.arrayValue?.first(where: { $0["keyID"]?.stringValue == key.keyID }),
                   let delivery = device["lastDelivery"] {
                    state.lastDelivery = delivery["result"]?.stringValue
                    if let time = delivery["at"]?.doubleValue { state.lastDeliveryAt = Date(timeIntervalSince1970: time / 1000) }
                }
            } catch APIError.server(_, 404, _) { state.pluginMissing = true; state.registration = "Plugin not installed" }
            catch PushRelayError.unreachable { state.registration = "Relay unreachable" }
            catch { state.registration = "Registration unavailable. Try again." }
        }
        registering[ref] = task
        await task.value
        registering[ref] = nil
    }
    /// Unpairing never waits on the network: an in-flight registration is cancelled, the plugin and relay
    /// revocations are best effort with deadlines, and the local key, shown files, pending count and sender
    /// are always removed. A sender the relay could not revoke is kept under `revoke.<ref>` and retried on
    /// every token registration. Until it is revoked, a plugin that still holds the registration (because
    /// `unregisterDevice` did not reach it) keeps delivering through the relay; with the key deleted, the
    /// NSE can only show those pushes as the generic Open-only alert.
    public func unregister(server: ServerID, rpc: @escaping RPC) async {
        let ref = server.rawValue.uuidString
        if let task = registering[ref] { task.cancel(); await task.value }
        if let key = try? await keys.existingKey(for: server) {
            _ = try? await withActionDeadline(seconds: .seconds(5)) { try await rpc("unregisterDevice", .object(["keyID": .string(key.keyID)])) }
        }
        if let data = try? await secrets.read(account: "sender." + ref) {
            if await revoke(data) == false { try? await secrets.write(data, account: "revoke." + ref); await addPending(ref) }
        }
        try? await secrets.delete(account: "sender." + ref)
        try? await keys.delete(for: server)
        try? store.remove(server: ref)
        health.removeValue(forKey: ref)
    }
    /// True once the relay no longer holds the sender (a 404 counts: it is already gone).
    private func revoke(_ data: Data) async -> Bool {
        guard let sender = try? JSONDecoder().decode(PushSender.self, from: data), let identity = try? await identity() else { return false }
        do {
            _ = try await withActionDeadline(seconds: .seconds(5)) {
                try await self.relay(.delete, "/v1/devices/\(identity.deviceID)/senders/\(sender.senderID)", identity.deviceSecret, nil)
            }
            return true
        } catch APIError.server(_, 404, _) { return true } catch { return false }
    }
    private func addPending(_ ref: String) async {
        await loadPendingRevocationsIfNeeded()
        if !pendingRevocations.contains(ref) { pendingRevocations.append(ref) }
        try? await secrets.write(JSONEncoder().encode(pendingRevocations), account: "revocations")
    }
    /// The saved list is the source of truth; anything added in memory before the first load is kept.
    public func loadPendingRevocations() async {
        let saved = (try? await secrets.read(account: "revocations")).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        pendingRevocations = saved + pendingRevocations.filter { !saved.contains($0) }
        revocationsLoaded = true
    }
    /// Every write of the list goes through here first, so a launch that registers its token before
    /// Settings loads the list can never overwrite the saved revocations with an empty one.
    private func loadPendingRevocationsIfNeeded() async {
        if !revocationsLoaded { await loadPendingRevocations() }
    }
    public func retryRevocations() async {
        await loadPendingRevocationsIfNeeded()
        for ref in pendingRevocations {
            guard let data = try? await secrets.read(account: "revoke." + ref) else { pendingRevocations.removeAll { $0 == ref }; continue }
            if await revoke(data) { try? await secrets.delete(account: "revoke." + ref); pendingRevocations.removeAll { $0 == ref } }
        }
        try? await secrets.write(JSONEncoder().encode(pendingRevocations), account: "revocations")
    }
    public func registerActivity(token: String, ref: String, expiresAt: Date, server: ServerID, sessionID: String, rpc: RPC) async throws {
        guard let identity = try await identity(), let key = try await keys.existingKey(for: server) else { throw PushRegistrationError.deviceNotRegistered }
        _ = try await relay(.put, "/v1/devices/\(identity.deviceID)/activities/\(ref)", identity.deviceSecret,
            .object(["pushToken": .string(token), "expiresAt": .integer(Int64(expiresAt.timeIntervalSince1970))]))
        _ = try await rpc("registerActivity", .object(["keyID": .string(key.keyID), "activityRef": .string(ref), "sessionID": .string(sessionID)]))
    }
}

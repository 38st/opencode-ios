import CryptoKit
import Foundation
import OCModels
import Security

/// The device's X25519 key pair for one paired server (ARCHITECTURE §4.4), with the plugin's
/// public key once `registerDevice` returns it.
public struct PushKey: Codable, Sendable, Equatable {
    /// The `kid` the app registers and every envelope for this server carries.
    public let keyID: String
    public let server: ServerID
    /// Raw 32-byte X25519 private key.
    public let privateKey: Data
    /// The plugin's static public key, pinned at registration.
    public var serverPublicKey: Data?

    public var publicKey: Data {
        (try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey))?.publicKey.rawRepresentation ?? Data()
    }
}

/// Push keys in the Keychain. `KeychainStore` writes with `AfterFirstUnlockThisDeviceOnly`, so the
/// Notification Service Extension can read them on a locked phone, and they never leave the device.
/// The app passes the App Group's Keychain access group so the extension shares them.
public actor PushKeyStore {
    public static let service = "app.opencode.push-keys"
    private let secrets: any SecretStore
    /// Keys being created, so concurrent callers for one server share one key instead of orphaning one.
    private var creating: [ServerID: Task<PushKey, any Error>] = [:]

    public init(secrets: any SecretStore) { self.secrets = secrets }

    public static func keychain(accessGroup: String?) -> PushKeyStore {
        PushKeyStore(secrets: KeychainStore(service: service, accessGroup: accessGroup))
    }

    /// The key for a server, created on first use.
    public func key(for server: ServerID) async throws -> PushKey {
        if let existing = try await existingKey(for: server) { return existing }
        // The actor interleaved at the awaits above: another caller may be creating the key already.
        if let inFlight = creating[server] { return try await inFlight.value }
        let secrets = self.secrets
        let task = Task<PushKey, any Error> {
            let created = PushKey(keyID: Self.newKeyID(), server: server, privateKey: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
            try await secrets.write(JSONEncoder().encode(created), account: Self.keyAccount(created.keyID))
            try await secrets.write(Data(created.keyID.utf8), account: Self.serverAccount(server))
            return created
        }
        creating[server] = task
        defer { creating[server] = nil }
        return try await task.value
    }

    /// The server's key, if one was created.
    public func existingKey(for server: ServerID) async throws -> PushKey? {
        guard let keyID = try await secrets.read(account: Self.serverAccount(server)).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        return try await key(keyID: keyID)
    }

    /// The extension's lookup by an envelope's `kid`.
    public func key(keyID: String) async throws -> PushKey? {
        guard let data = try await secrets.read(account: Self.keyAccount(keyID)) else { return nil }
        return try JSONDecoder().decode(PushKey.self, from: data)
    }

    /// Pins the plugin's key to the server's existing push key; it never creates one, so a key that
    /// `registerDevice` never saw cannot be pinned.
    public func pin(serverPublicKey: Data, for server: ServerID) async throws {
        guard serverPublicKey.count == 32 else { throw KeychainError(status: errSecParam) }
        guard var current = try await existingKey(for: server) else { throw KeychainError(status: errSecItemNotFound) }
        if let pinned = current.serverPublicKey, pinned != serverPublicKey { throw KeychainError(status: errSecAuthFailed) }
        current.serverPublicKey = serverPublicKey
        try await save(current)
    }

    /// Unpairing a server deletes its key, so a stale envelope can no longer be opened.
    public func delete(for server: ServerID) async throws {
        if let keyID = try await secrets.read(account: Self.serverAccount(server)).flatMap({ String(data: $0, encoding: .utf8) }) {
            try await secrets.delete(account: Self.keyAccount(keyID))
        }
        try await secrets.delete(account: Self.serverAccount(server))
    }

    private func save(_ key: PushKey) async throws {
        try await secrets.write(JSONEncoder().encode(key), account: Self.keyAccount(key.keyID))
    }

    private static func serverAccount(_ server: ServerID) -> String { "server." + server.rawValue.uuidString }
    private static func keyAccount(_ keyID: String) -> String { "key." + keyID }

    /// 16 random bytes in base64url: 22 characters, within the contract's `kid` pattern.
    static func newKeyID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

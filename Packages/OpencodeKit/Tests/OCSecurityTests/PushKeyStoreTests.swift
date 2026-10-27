import CryptoKit
import Foundation
import OCModels
import Security
import Testing
@testable import OCSecurity

@Test func pushKeysArePerServerStableAndFoundByKeyID() async throws {
    let store = PushKeyStore(secrets: InMemorySecretStore())
    let first = ServerID(), second = ServerID()
    let key = try await store.key(for: first)
    #expect(try await store.key(for: first) == key)
    #expect(try await store.key(for: second) != key)
    #expect(key.keyID.wholeMatch(of: /[A-Za-z0-9_-]{22}/) != nil)
    #expect(key.publicKey == (try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: key.privateKey)).publicKey.rawRepresentation)
    #expect(try await store.key(keyID: key.keyID) == key)
    #expect(key.serverPublicKey == nil)
}

@Test func concurrentCallersShareOneKey() async throws {
    let secrets = InMemorySecretStore(), store = PushKeyStore(secrets: secrets), server = ServerID()
    // Every call interleaves at the store's awaits before any key exists.
    let keys = try await withThrowingTaskGroup(of: PushKey.self) { group in
        for _ in 0..<8 { group.addTask { try await store.key(for: server) } }
        return try await group.reduce(into: [PushKey]()) { $0.append($1) }
    }
    #expect(Set(keys.map(\.keyID)).count == 1)
    #expect(try await store.key(for: server) == keys[0])
    // One key account and one server account: no orphaned key is left in the store.
    #expect(try await store.key(keyID: keys[0].keyID) == keys[0])
    try await store.delete(for: server)
    #expect(await secrets.read(account: "key." + keys[0].keyID) == nil)
}

@Test func pinningNeedsAnExistingKey() async throws {
    let store = PushKeyStore(secrets: InMemorySecretStore())
    let pinned = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    await #expect(throws: KeychainError(status: errSecItemNotFound)) { try await store.pin(serverPublicKey: pinned, for: ServerID()) }
    #expect(try await store.existingKey(for: ServerID()) == nil)
}

@Test func pinningAndDeletingAPushKey() async throws {
    let store = PushKeyStore(secrets: InMemorySecretStore()), server = ServerID()
    let pinned = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    let key = try await store.key(for: server)
    try await store.pin(serverPublicKey: pinned, for: server)
    #expect(try await store.key(keyID: key.keyID)?.serverPublicKey == pinned)
    await #expect(throws: KeychainError.self) { try await store.pin(serverPublicKey: Data(count: 31), for: server) }
    try await store.delete(for: server)
    #expect(try await store.key(keyID: key.keyID) == nil)
    #expect(try await store.key(for: server).keyID != key.keyID)
}

@Test func pinnedSenderCannotBeSilentlyReplaced() async throws {
    let store = PushKeyStore(secrets: InMemorySecretStore()), server = ServerID()
    _ = try await store.key(for: server)
    let first = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    try await store.pin(serverPublicKey: first, for: server)
    await #expect(throws: KeychainError(status: errSecAuthFailed)) {
        try await store.pin(serverPublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation, for: server)
    }
    #expect(try await store.existingKey(for: server)?.serverPublicKey == first)
}

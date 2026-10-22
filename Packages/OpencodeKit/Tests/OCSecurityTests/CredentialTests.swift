import Foundation
import Testing
import OCModels
import OCSecurity

#if DEBUG
@Test func uiTestResetCannotDeleteProductionKeychainService() async {
    await #expect(throws: KeychainError.self) { try await KeychainStore().resetForUITesting() }
}
#endif

@Test func credentialsRoundTrip() async throws {
    let store = CredentialStore(secrets: InMemorySecretStore())
    let server = ServerID()
    try await store.save(.password("test"), headers: ["X-Test": "secret"], for: server)
    #expect(try await store.credential(for: server) == .password("test"))
    #expect(try await store.headers(for: server) == ["X-Test": "secret"])
    try await store.delete(for: server)
    #expect(try await store.credential(for: server) == nil)
}

@Test func tokenExpiryUsesUnixSecondsAndFiveDayBoundary() throws {
    let token = "1790000000." + String(repeating: "A", count: 43)
    let expiry = try #require(PairingToken.expiry(token))
    #expect(expiry.timeIntervalSince1970 == 1_790_000_000)
    let credential = try #require(PairingToken.credential(token))
    #expect(credential.expiresWithinFiveDays(now: expiry.addingTimeInterval(-5 * 86400)))
    #expect(!credential.expiresWithinFiveDays(now: expiry.addingTimeInterval(-5 * 86400 - 1)))
    #expect(credential.expiresWithinFiveDays(now: expiry.addingTimeInterval(1)))
    #expect(!Credential.password("test").expiresWithinFiveDays())
    #expect(String(describing: credential) == "Credential([REDACTED])")
    for invalid in ["", "1790000000", "x.sig", "1790000000.sig", "1.a.b", "9007199254740992." + String(repeating: "A", count: 43)] {
        #expect(PairingToken.expiry(invalid) == nil)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["OPENCODE_TEST_KEYCHAIN"] == "1",
               "Opt in only on a host with an unlocked, usable Keychain"))
func keychainRoundTripWhenUsable() async throws {
    let store = KeychainStore(service: "app.opencode.tests." + UUID().uuidString)
    let account = UUID().uuidString
    do { try await store.write(Data("first".utf8), account: account) }
    catch let error as KeychainError {
        // CLI runners can lack signing entitlements or an unlocked login Keychain.
        print("SKIP Keychain unavailable (OSStatus \(error.status))")
        return
    }
    do {
        #expect(try await store.read(account: account) == Data("first".utf8))
        try await store.write(Data("second".utf8), account: account)
        #expect(try await store.read(account: account) == Data("second".utf8))
        try await store.delete(account: account)
        #expect(try await store.read(account: account) == nil)
    } catch {
        try? await store.delete(account: account)
        throw error
    }
}

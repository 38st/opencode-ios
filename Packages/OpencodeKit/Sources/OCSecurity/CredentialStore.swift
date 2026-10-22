import Foundation
import OCModels

public actor CredentialStore {
    private struct Secrets: Codable { var credential: Credential; var headers: [String: String] }
    private let secrets: any SecretStore
    public init(secrets: any SecretStore) { self.secrets = secrets }
    public func credential(for server: ServerID) async throws -> Credential? {
        try await load(server)?.credential
    }
    public func headers(for server: ServerID) async throws -> [String: String] {
        try await load(server)?.headers ?? [:]
    }
    public func save(_ credential: Credential, headers: [String: String] = [:], for server: ServerID) async throws {
        try await secrets.write(JSONEncoder().encode(Secrets(credential: credential, headers: headers)),
                                account: server.rawValue.uuidString)
    }
    public func delete(for server: ServerID) async throws {
        try await secrets.delete(account: server.rawValue.uuidString)
    }
    private func load(_ server: ServerID) async throws -> Secrets? {
        guard let data = try await secrets.read(account: server.rawValue.uuidString) else { return nil }
        return try JSONDecoder().decode(Secrets.self, from: data)
    }
}

public enum PairingToken {
    /// auth.ts issues `<decimal Unix seconds>.<base64url HMAC-SHA256>`.
    /// Reading expiry does not authenticate the signature; only the server can do that.
    public static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].utf8.allSatisfy({ (48...57).contains($0) }),
              let seconds = Double(parts[0]), seconds <= 9_007_199_254_740_991,
              parts[1].count == 43, parts[1].utf8.allSatisfy({
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
              }) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    public static func credential(_ token: String) -> Credential? {
        expiry(token).map { .pairingToken(token, expiresAt: $0) }
    }
}

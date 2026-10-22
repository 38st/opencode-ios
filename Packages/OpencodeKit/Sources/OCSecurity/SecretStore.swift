import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(account: String) async throws -> Data?
    func write(_ data: Data, account: String) async throws
    func delete(account: String) async throws
}

public actor InMemorySecretStore: SecretStore {
    private var values: [String: Data] = [:]
    public init() {}
    public func read(account: String) -> Data? { values[account] }
    public func write(_ data: Data, account: String) { values[account] = data }
    public func delete(account: String) { values.removeValue(forKey: account) }
}

public struct KeychainError: Error, Sendable, Equatable {
    public let status: OSStatus
}

public actor KeychainStore: SecretStore {
    private let service: String
    private let accessGroup: String?
    public init(service: String = "app.opencode.credentials", accessGroup: String? = nil) {
        self.service = service; self.accessGroup = accessGroup
    }
    private func query(_ account: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
    public func read(account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }
    public func write(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd(query(account).merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
    #if DEBUG
    public func resetForUITesting() throws {
        guard service.hasPrefix("app.opencode.uitests.ui-") else { throw KeychainError(status: errSecParam) }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
    #endif
}

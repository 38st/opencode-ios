import Foundation

/// The shared push constants: a byte-identical copy of `server/contracts/constants.json`
/// (`Tools/sync-push-contracts.mjs` keeps it in sync, and a test checks the bytes).
public struct PushContract: Decodable, Sendable {
    public struct Names: Decodable, Sendable {
        public let package: String
        public let plugin: String
        public let rpc: String
    }
    public struct Relay: Decodable, Sendable {
        public let defaultURL: URL
    }
    public struct HPKE: Decodable, Sendable {
        public let info: String
    }
    public struct Envelope: Decodable, Sendable {
        public let version: Int
        public let aadPrefix: String
        public let keyBytes: Int
        public let tagBytes: Int
        public let maxEncodedCiphertext: Int
    }
    public struct Padding: Decodable, Sendable {
        public let buckets: [Int]
        public let marker: UInt8
    }
    public struct Payload: Decodable, Sendable {
        public let version: Int
    }
    public struct Kind: Decodable, Sendable {
        public let alert: String
        public let category: String
        public let interruptionLevel: String
        public let priority: Int
        public let ttlSeconds: Int
    }
    public struct Presence: Decodable, Sendable {
        public let heartbeatSeconds: Int
        public let validSeconds: Int
    }
    public struct Activity: Decodable, Sendable {
        public let updateIntervalSeconds: Int
        public let staleSeconds: Int
        public let dismissSeconds: Int
        public let maxLifetimeSeconds: Int
    }

    public let version: Int
    public let names: Names
    public let relay: Relay
    public let hpke: HPKE
    public let envelope: Envelope
    public let padding: Padding
    public let payload: Payload
    public let kinds: [String: Kind]
    public let categories: [String]
    public let presence: Presence
    public let activity: Activity

    /// The bundled copy. A missing or unreadable resource is a build error, caught by the tests.
    public static let shared: PushContract = {
        do { return try JSONDecoder().decode(PushContract.self, from: ContractResource.data("constants.json")) }
        catch { preconditionFailure("OCPushCore's bundled constants.json is unreadable: \(error)") }
    }()
}

enum ContractResource {
    static var directory: URL? { Bundle.module.url(forResource: "Contracts", withExtension: nil) }
    static func data(_ name: String) throws -> Data {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: directory.appending(path: name))
    }
}

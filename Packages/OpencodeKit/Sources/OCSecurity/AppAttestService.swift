import Foundation
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// The device's App Attest key operations (`DCAppAttestService`), behind a protocol so the client's
/// state machine can be tested without the Secure Enclave. The simulator does not support App Attest.
public protocol AppAttestService: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

public enum AppAttestServiceError: Error, Equatable, Sendable {
    /// The key is unknown to the device or was already attested: generate a new one.
    case invalidKey
    case unavailable
}

#if canImport(DeviceCheck)
public struct DeviceAppAttestService: AppAttestService {
    public init() {}
    public var isSupported: Bool { DCAppAttestService.shared.isSupported }
    public func generateKey() async throws -> String { try await mapped { try await DCAppAttestService.shared.generateKey() } }
    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await mapped { try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash) }
    }
    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await mapped { try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash) }
    }
    private func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch let error as DCError where error.code == .invalidKey { throw AppAttestServiceError.invalidKey }
        catch let error as DCError where error.code == .featureUnsupported { throw AppAttestServiceError.unavailable }
    }
}
#endif

import Foundation
import LocalAuthentication

public protocol BiometricAuthenticating: Sendable {
    func authenticate(reason: String) async throws
}

/// Device-owner authentication permits Face ID, Touch ID, or the device passcode.
public actor BiometricGate: BiometricAuthenticating {
    public init() {}
    public func authenticate(reason: String) async throws {
        let context = LAContext()
        defer { context.invalidate() }
        let allowed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        if !allowed { throw CancellationError() }
    }
}

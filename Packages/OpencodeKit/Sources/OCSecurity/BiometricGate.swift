import Foundation
import LocalAuthentication

public protocol BiometricAuthenticating: Sendable {
    func authenticate(reason: String) async throws
    /// How the device confirms its owner; checked before offering a gated action.
    func method() async -> DeviceAuthenticationMethod
}

extension BiometricAuthenticating {
    public func method() async -> DeviceAuthenticationMethod { .passcode }
}

public enum DeviceAuthenticationMethod: Sendable, Equatable {
    case faceID, touchID, opticID, passcode, unavailable

    public var prompt: String {
        switch self {
        case .faceID: localized("Confirm with Face ID or passcode…")
        case .touchID: localized("Confirm with Touch ID or passcode…")
        case .opticID: localized("Confirm with Optic ID or passcode…")
        case .passcode, .unavailable: localized("Confirm with your passcode…")
        }
    }
}

/// Classified gate failures. Cancelling is the user's choice and is never reported as an error.
public enum DeviceAuthenticationError: Error, Equatable, Sendable {
    case cancelled, passcodeNotSet, lockedOut, failed

    public init(_ error: any Error) {
        if let error = error as? DeviceAuthenticationError { self = error; return }
        if error is CancellationError { self = .cancelled; return }
        guard let error = error as? LAError else { self = .failed; return }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: self = .cancelled
        case .passcodeNotSet: self = .passcodeNotSet
        case .biometryLockout: self = .lockedOut
        default: self = .failed
        }
    }

    public var message: String? {
        switch self {
        case .cancelled: nil
        case .passcodeNotSet: localized("Set a device passcode in Settings to approve this request.")
        case .lockedOut: localized("Authentication is locked. Unlock your device with its passcode, then try again.")
        case .failed: localized("Could not confirm it is you. Try again.")
        }
    }
}

/// Device-owner authentication permits Face ID, Touch ID, or the device passcode.
public actor BiometricGate: BiometricAuthenticating {
    public init() {}
    public func authenticate(reason: String) async throws {
        let context = LAContext()
        defer { context.invalidate() }
        do {
            let allowed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if !allowed { throw DeviceAuthenticationError.cancelled }
        } catch { throw DeviceAuthenticationError(error) }
    }
    public func method() async -> DeviceAuthenticationMethod {
        let context = LAContext()
        defer { context.invalidate() }
        // Without a passcode, device-owner authentication can never succeed.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }
}

import Foundation
import LocalAuthentication
import Testing
import OCSecurity

@Test func gateFailuresAreClassifiedSoCancellingStaysSilent() {
    for code in [LAError.Code.userCancel, .appCancel, .systemCancel] {
        #expect(DeviceAuthenticationError(LAError(code)) == .cancelled)
    }
    #expect(DeviceAuthenticationError(CancellationError()) == .cancelled)
    #expect(DeviceAuthenticationError(LAError(.passcodeNotSet)) == .passcodeNotSet)
    #expect(DeviceAuthenticationError(LAError(.biometryLockout)) == .lockedOut)
    #expect(DeviceAuthenticationError(URLError(.timedOut)) == .failed)
    #expect(DeviceAuthenticationError.cancelled.message == nil)
    #expect(DeviceAuthenticationError.passcodeNotSet.message?.contains("passcode") == true)
    #expect(DeviceAuthenticationMethod.touchID.prompt.contains("Touch ID"))
}

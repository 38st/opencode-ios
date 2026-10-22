import Testing
@testable import OCFoundation

struct RedactingLoggerTests {
    @Test func dropsAuthorizationAndAllOtherRuntimeValuesBeforeLogging() {
        let headers = ["Authorization": "Basic TEST_ONLY_SECRET", "authorization": "Bearer TEST_ONLY_TOKEN"]
        let message: RedactedLogMessage = "Request headers: \(headers); Authorization: \(headers["Authorization"] ?? ""); error: \("TEST_ONLY_PASSWORD")"
        #expect(message.text == "Request headers: [REDACTED]; Authorization: [REDACTED]; error: [REDACTED]")
        #expect(!message.text.contains("TEST_ONLY"))
    }

    @Test func neverEvenDescribesSensitiveObjects() {
        struct Secret: CustomStringConvertible {
            var description: String {
                Issue.record("A sensitive value was formatted")
                return "secret"
            }
        }
        let message: RedactedLogMessage = "Credential \(Secret())"
        #expect(message.text == "Credential [REDACTED]")
        OCLog.security.debug(message)
    }

    @Test func literalDiagnosticsRemainReadable() {
        let message: RedactedLogMessage = "Connection closed; retry scheduled"
        #expect(message.text == "Connection closed; retry scheduled")
    }
}

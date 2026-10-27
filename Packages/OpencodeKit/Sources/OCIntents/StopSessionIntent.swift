#if os(iOS)
import AppIntents
import Foundation

@MainActor public enum SessionIntentHandler {
    public static var stop: (@MainActor @Sendable (String, String) async throws -> Void)?
}

public struct StopSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop session"
    public static let description = IntentDescription("Interrupt this opencode session.")
    public static let openAppWhenRun = false
    @Parameter(title: "Server") public var server: String
    @Parameter(title: "Session") public var session: String
    public init() {}
    public init(server: String, session: String) { self.server = server; self.session = session }
    @MainActor public func perform() async throws -> some IntentResult {
        guard let stop = SessionIntentHandler.stop else { throw StopError.unavailable }
        try await stop(server, session)
        return .result()
    }
    enum StopError: Error { case unavailable }
}
public struct OpencodeIntents: AppIntentsPackage {}
#endif

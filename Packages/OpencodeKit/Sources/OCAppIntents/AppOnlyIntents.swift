import AppIntents
import Foundation
import OCIntents
import OCShared

// The intents that only the app process can run: they send, ask a server, or open a session. Only the app includes
// this module's intents; the Widgets extension includes OCIntents alone (its configuration, its controls' intents and
// the entities), so the system has no extension to run these in.

public enum PromptDestination: String, AppEnum {
    case session, newSession
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    public static let caseDisplayRepresentations: [PromptDestination: DisplayRepresentation] = [
        .session: "An existing session", .newSession: "A new session in a project",
    ]
}

/// Sends a prompt through the app's outbox: it reaches the server once, and survives the app being closed.
public struct SendPromptIntent: AppIntent {
    public static let title: LocalizedStringResource = "Send a prompt"
    public static let description = IntentDescription("Send a prompt to a session, or start a new session in a project with it. When the server cannot be reached, the prompt waits on this device and sends later.")
    public static let supportedModes: IntentModes = .background
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Send to", default: .session) public var destination: PromptDestination
    @Parameter(title: "Session") public var session: SessionEntity?
    @Parameter(title: "Project") public var project: ProjectEntity?
    @Parameter(title: "Prompt", inputOptions: String.IntentInputOptions(multiline: true)) public var prompt: String
    public static var parameterSummary: some ParameterSummary {
        Switch(\.$destination) {
            Case(.newSession) { Summary("Start a session in \(\.$project) with \(\.$prompt)") { \.$destination } }
            DefaultCase { Summary("Send \(\.$prompt) to \(\.$session)") { \.$destination } }
        }
    }
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<SessionEntity> & ProvidesDialog {
        IntentTrace.record("send")
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw $prompt.needsValueError("What do you want to send?") }
        let request: PromptRequest
        switch destination {
        case .session:
            guard let session else { throw $session.needsValueError("Which session?") }
            request = .init(destination: .session(server: session.server, session: session.session), text: text)
        case .newSession:
            guard let project else { throw $project.needsValueError("Which project?") }
            request = .init(destination: .newSession(server: project.server, project: project.project), text: text)
        }
        let receipt = try await Self.send(request, app: IntentEnvironment.app)
        IntentTrace.result("send", Self.message(receipt))
        return .result(value: SessionEntity(receipt.session, serverName: receipt.serverName), dialog: "\(Self.message(receipt))")
    }
    @MainActor static func send(_ request: PromptRequest, app: (any IntentApp)?) async throws -> PromptReceipt {
        guard let app else { throw IntentError.appUnavailable }
        return try await app.send(request)
    }
    static func message(_ receipt: PromptReceipt) -> String {
        receipt.delivered ? "Sent to “\(receipt.session.title)”."
            : "Saved on this device. It sends to “\(receipt.session.title)” when \(receipt.serverName) can be reached."
    }
}

public struct GetSessionStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get session status"
    public static let description = IntentDescription("Get a session's status and when it was last active.")
    public static let supportedModes: IntentModes = .background
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Session") public var session: SessionEntity
    public static var parameterSummary: some ParameterSummary { Summary("Get the status of \(\.$session)") }
    public init() {}
    public init(session: SessionEntity) { self.session = session }
    @MainActor public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        IntentTrace.record("status")
        let report = try await Self.status(session, app: IntentEnvironment.app)
        IntentTrace.result("status", report.summary(now: .now))
        return .result(value: report.label, dialog: "\(report.summary(now: .now))")
    }
    @MainActor static func status(_ session: SessionEntity, app: (any IntentApp)?) async throws -> SessionStatusReport {
        guard let app else { throw IntentError.appUnavailable }
        return try await app.status(server: session.server, session: session.session)
    }
}

/// Opens a session; also what a session found in Spotlight runs.
public struct OpenSessionIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open a session"
    public static let description = IntentDescription("Open a session in the app.")
    @Parameter(title: "Session") public var target: SessionEntity
    public init() {}
    public init(target: SessionEntity) { self.target = target }
    @MainActor public func perform() async throws -> some IntentResult {
        IntentTrace.record("open")
        try Self.open(target, app: IntentEnvironment.app)
        return .result()
    }
    @MainActor static func open(_ target: SessionEntity, app: (any IntentApp)?) throws {
        guard let app else { throw IntentError.appUnavailable }
        guard let url = target.url else { throw IntentError.sessionNotFound }
        app.open(url)
    }
}

#if os(iOS)
/// Registers these intents, and OCIntents' through it, with the app.
public struct OpencodeAppOnlyIntents: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] { [OpencodeIntents.self] }
}
#endif

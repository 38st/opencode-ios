import AppIntents
import Foundation
import OCShared

/// Opens the next waiting permission or question in the app. Nothing is ever approved from here: silence is never
/// consent, and approvals happen in the app or from a notification's actions.
public struct ReviewNextApprovalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Review the next approval"
    public static let description = IntentDescription("Open the next permission or question that waits for you. You answer it in the app.")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentTrace.record("review")
        let opened = try await Self.review(app: IntentEnvironment.app)
        return .result(dialog: IntentDialog(opened ? LocalizedStringResource("Opening the request.", bundle: .module) : LocalizedStringResource("Nothing is waiting for your approval.", bundle: .module)))
    }
    /// Opens the request, if one waits; true when it did.
    @MainActor static func review(app: (any IntentApp)?) async throws -> Bool {
        guard let app else { throw IntentError.appUnavailable }
        guard let url = await app.nextApproval() else { return false }
        app.open(url)
        return true
    }
}

/// Opens a new session's composer in the last used project.
public struct NewPromptIntent: AppIntent {
    public static let title: LocalizedStringResource = "New prompt"
    public static let description = IntentDescription("Open a new session's composer in the project you used last.")
    public static let supportedModes: IntentModes = .foreground(.immediate)
    public init() {}
    @MainActor public func perform() async throws -> some IntentResult {
        IntentTrace.record("new-prompt")
        try await Self.compose(app: IntentEnvironment.app)
        return .result()
    }
    @MainActor static func compose(app: (any IntentApp)?) async throws {
        guard let app else { throw IntentError.appUnavailable }
        if let url = await app.newPrompt() { app.open(url) }
    }
}

/// The server a Home or Lock Screen widget shows; All servers when none is chosen.
public struct SessionsWidgetIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Sessions"
    public static let description = IntentDescription("Choose the server the widget shows.")
    public static let isDiscoverable = false
    @Parameter(title: "Server") public var server: ServerEntity?
    public init() {}
    public init(server: ServerEntity?) { self.server = server }
    /// The server to show, or nil for every server.
    public var serverID: String? { server?.serverID }
}

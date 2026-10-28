import AppIntents
import OCAppIntents
import OCIntents

/// Siri and Shortcuts phrases. Each names the app through `.applicationName`, so a rename is the display name alone.
/// The provider lives in the app target: the App Shortcuts of a provider in a package are not carried into the app's
/// metadata.
nonisolated struct OpencodeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendPromptIntent(), phrases: ["Send a prompt with \(.applicationName)", "Send a prompt to \(.applicationName)"],
                    shortTitle: "Send a prompt", systemImageName: "paperplane")
        AppShortcut(intent: GetSessionStatusIntent(), phrases: ["Get session status in \(.applicationName)", "Check \(\.$session) in \(.applicationName)"],
                    shortTitle: "Session status", systemImageName: "gauge.with.dots.needle.50percent")
        AppShortcut(intent: OpenSessionIntent(), phrases: ["Open a session in \(.applicationName)", "Open \(\.$target) in \(.applicationName)"],
                    shortTitle: "Open session", systemImageName: "bubble.left")
        AppShortcut(intent: ReviewNextApprovalIntent(), phrases: ["Review the next approval in \(.applicationName)", "Review approvals in \(.applicationName)"],
                    shortTitle: "Review approval", systemImageName: "checkmark.shield")
        AppShortcut(intent: NewPromptIntent(), phrases: ["New prompt in \(.applicationName)", "Start a new \(.applicationName) session"],
                    shortTitle: "New prompt", systemImageName: "square.and.pencil")
    }
    static let shortcutTileColor: ShortcutTileColor = .grayBlue
}

/// The intents, entities and queries live in the package's OCAppIntents and OCIntents modules; including them registers
/// them with this app, so the system can run them here. The Widgets extension includes OCIntents alone.
nonisolated struct OpencodeAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [OpencodeAppOnlyIntents.self] }
}

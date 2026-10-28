import AppIntents
import OCIntents

/// Registers the OCIntents package with the extension, for the widgets' configuration and the controls' intents.
nonisolated struct WidgetAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [OpencodeIntents.self] }
}

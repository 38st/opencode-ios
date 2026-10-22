import FeatureServers
import OCSync
import SwiftUI

@main
struct OpencodeApp: App {
    @State private var registry: ServerRegistry?
    @State private var startupError: String?
    @State private var incomingURL: URL?
    var body: some Scene {
        WindowGroup {
            Group {
                if let registry { ServerRootView(registry: registry, incomingURL: $incomingURL) }
                else if let startupError { ContentUnavailableView("Could not open saved servers", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError)) }
                else { ProgressView("Opening servers…") }
            }
            .onOpenURL { incomingURL = $0 }
            .task {
                guard registry == nil else { return }
                do { registry = try await ServerRegistry.live() }
                catch { startupError = "Application Support is unavailable. Relaunch the app to try again." }
            }
        }
    }
}

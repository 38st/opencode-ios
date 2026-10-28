import AppIntents
import FeatureServers
import OCModels
import OCSync
import SwiftUI

@main
struct OpencodeApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    @State private var registry: ServerRegistry?
    @State private var startupError: String?
    init() { ApplicationServices.appShortcutsChanged = { OpencodeShortcuts.updateAppShortcutParameters() } }
    var body: some Scene {
        // Each window shows one session; links and notifications are routed by the window coordinator.
        WindowGroup(id: ServerRootView.windowGroup, for: SessionRef.self) { $session in
            Group {
                if let registry { ServerRootView(registry: registry, windows: ApplicationServices.windows, links: ApplicationServices.links, window: $session) }
                else if let startupError { ContentUnavailableView("Could not open saved servers", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError)) }
                else { ProgressView("Opening servers…") }
            }
            .task {
                guard registry == nil else { return }
                do {
                    let registry = try await ApplicationServices.registry()
                    ApplicationServices.windows.applyPhase = { await registry.setScenePhase($0) }
                    self.registry = registry
                }
                catch { startupError = "Application Support is unavailable. Relaunch the app to try again." }
            }
        }
        .commands { WorkspaceCommands() }
    }
}

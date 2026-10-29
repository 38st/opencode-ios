#if os(iOS)
import SwiftUI
import OCModels
import OCSync
import FeatureInbox

struct WorkspaceSidebar: View {
    let registry: ServerRegistry
    @Binding var selectedServer: ServerID?
    @Binding var selectedProject: String?
    let openSettings: () -> Void
    let newSession: () -> Void
    var selectedSession: SessionRef? = nil
    var openInNewWindow: ((SessionRef) -> Void)? = nil
    var openPalette: (() -> Void)? = nil
    var shortcut: (SessionRef) -> String? = { _ in nil }
    var search: Binding<String>? = nil
    var showHidden: Binding<Bool>? = nil
    var openTerminals: ((ServerID, String) -> Void)? = nil
    let selectSession: (SessionRef) -> Void
    var body: some View {
        HomeView(registry: registry, selectedServer: $selectedServer, selectedProject: $selectedProject,
                 openSettings: openSettings, newSession: newSession, selectedSession: selectedSession,
                 openInNewWindow: openInNewWindow, openPalette: openPalette, shortcut: shortcut, search: search, showHidden: showHidden,
                 openTerminals: openTerminals, selectSession: selectSession)
    }
}
#endif

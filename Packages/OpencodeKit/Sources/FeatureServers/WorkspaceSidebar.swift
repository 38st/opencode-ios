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
    let selectSession: (SessionRef) -> Void
    var body: some View {
        HomeView(registry: registry, selectedServer: $selectedServer, selectedProject: $selectedProject,
                 openSettings: openSettings, newSession: newSession, selectedSession: selectedSession, selectSession: selectSession)
    }
}
#endif

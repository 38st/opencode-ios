#if os(iOS)
import SwiftUI
import OCSync

extension View {
    @ViewBuilder func uiTestConnectionDiagnostics(_ registry: ServerRegistry) -> some View {
        #if DEBUG
        if let defaults = registry.uiTestDefaults {
            accessibilityElement(children: .contain)
                .accessibilityIdentifier("connectionDiagnostics")
                .accessibilityValue(registry.connectionDiagnostics)
                .defaultAppStorage(defaults)
        } else { self }
        #else
        self
        #endif
    }
}
#endif

import OCDesign
import OCSync
import SwiftUI

#if os(iOS)

/// One open demo; a new one is made each time, so every demo starts from the recording.
struct DemoSession: Identifiable {
    let id = UUID()
    let registry: ServerRegistry
}

/// The app as it looks with a server, driven by the recorded demo, with a bar that says so and leads out.
struct DemoRootView: View {
    let registry: ServerRegistry
    let exit: () -> Void

    var body: some View {
        // Stacked above the app rather than inset into it, so the navigation bar and its Back button stay below it.
        VStack(spacing: 0) {
            if !Self.hidesBar { bar }
            ServerRootView(registry: registry, windows: WindowCoordinator(), links: LinkInbox(), initialState: nil, exitDemo: exit)
        }
    }

    private var bar: some View {
        HStack(spacing: OCSpacing.sm) {
            OCIcon("eye", size: 14).foregroundStyle(OCColor.iconMuted).accessibilityHidden(true)
            Text(localized("Demo: recorded sessions, no server", comment: "Banner shown while the demo is open"))
                .font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: OCSpacing.sm)
            Button(localized("Exit demo"), action: exit)
                .font(OCType.small.weight(.medium)).foregroundStyle(OCColor.text)
                .frame(minHeight: OCLayout.touchTarget)
                .accessibilityIdentifier("exitDemo")
        }
        .padding(.horizontal, OCSpacing.lg)
        .background(OCColor.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(OCColor.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    /// Store and README screenshots show the app without the bar.
    private static var hidesBar: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-screenshots")
        #else
        false
        #endif
    }
}
#endif

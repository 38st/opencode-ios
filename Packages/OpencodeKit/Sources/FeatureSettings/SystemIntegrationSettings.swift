#if os(iOS)
import SwiftUI
import UIKit
import OCDesign
import OCSync

/// Settings → Widgets and Shortcuts: the Spotlight switch, and what the widgets, controls and Shortcuts actions show.
public struct SystemIntegrationSection: View {
    @Bindable var system: SystemIntegration
    let openSystemSettings: @MainActor () -> Void
    public init(system: SystemIntegration, openSystemSettings: @escaping @MainActor () -> Void = SystemIntegrationSection.openAppSettings) {
        self.system = system; self.openSystemSettings = openSystemSettings
    }
    public var body: some View {
        OCSection("Widgets and Shortcuts") {
            OCToggleRow("Show sessions in Spotlight",
                        detail: "Session titles, project names and server names appear in search, never what a session says. Turning this off removes them.",
                        isOn: Binding(get: { system.spotlightEnabled }, set: { value in Task { await system.setSpotlight(value) } }))
                .accessibilityIdentifier("spotlightToggle")
            explanation("Widgets", "Needs you, Running and Recent show session titles on the Home Screen. On the Lock Screen titles stay hidden until you unlock; counts stay visible.")
            explanation("Controls", "New prompt and Review approval work in Control Center, on the Lock Screen and with the Action button.")
            explanation("Shortcuts and Siri", "Send a prompt, Get session status, Open a session, Review the next approval and New prompt. Requests are always answered in the app.")
            Button("Open Siri & Search settings", action: openSystemSettings).buttonStyle(OCButtonStyle())
                .accessibilityHint("Opens this app's page in the Settings app")
                .accessibilityIdentifier("openSystemSettings")
        }
    }
    private func explanation(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            Text(title).font(OCType.body)
            Text(detail).font(OCType.small).foregroundStyle(OCColor.textMuted)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    /// This app's page in the Settings app, where Siri & Search lives.
    public static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif

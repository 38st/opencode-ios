#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCActivity
import OCDesign
import OCFoundation
import OCModels
import OCNetworking
import OCSecurity
import OCShared
import FeatureSettings
@testable import OCSync

@MainActor @Suite(.serialized) struct PushSnapshots {
    @Test func notificationSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ServerRegistry(records: JSONServerRecordStore(url: directory.appending(path: "servers.json")), credentials: CredentialStore(secrets: InMemorySecretStore()), pathMonitor: nil)
        let store = PushSnapshotStore(directory: directory.appending(path: "push"))
        try store.append(.init(server: "server", requestID: "per_1", action: "ALLOW_ONCE", result: "Approved", date: Date(timeIntervalSince1970: 1_800_000_000)))
        let controller = PushController(registry: registry, store: store, keys: PushKeyStore(secrets: InMemorySecretStore()), secrets: InMemorySecretStore())
        controller.registration.unavailable()
        await controller.registration.register(server: ServerID(), name: "Studio") { _, _ in
            .object(["pluginVersion": .string("0.1.0")])
        }
        capture(NotificationSettings(controller: controller, refreshOnAppear: false), name: "notifications", height: 3000)
        controller.setNotifications("finished", enabled: false)
        controller.setQuietHours(QuietHours(start: 22 * 60, end: 7 * 60))
        controller.setMuted(true, server: "server", sessionID: "ses_1")
        capture(NotificationSettings(controller: controller, refreshOnAppear: false), name: "notifications-quiet", height: 3000)
    }
    @Test func liveActivityStates() {
        let attributes = SessionActivityAttributes(serverID: UUID().uuidString, sessionID: "ses_snapshot", title: "Review the connection changes", project: "opencode-ios")
        for phase in ["running", "needsInput", "retrying", "succeeded", "failed", "interrupted", "unknown"] {
            let state = SessionActivityAttributes.ContentState(phase: phase, step: 4, toolGlyph: "shell", startedAt: 1_800_000_000, updatedAt: 1_800_000_060)
            capture(SessionActivityView(attributes: attributes, state: state), name: "activity-" + phase, height: 500)
            capture(HStack { SessionActivityGlyph(state: state); SessionActivityCompact(state: state) }, name: "island-" + phase, height: 120)
        }
        capture(SessionActivityView(attributes: attributes, state: .init(startedAt: 0, updatedAt: 0), stale: true), name: "activity-stale", height: 500)
    }
    private func capture(_ view: some View, name: String, height: CGFloat) {
        for dark in [false, true] {
            for width: CGFloat in [393, 820] {
                let content = view.environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).environment(\.dynamicTypeSize, .accessibility5).environment(\.colorScheme, dark ? .dark : .light).ocTheme()
                let controller = UIHostingController(rootView: content)
                assertSnapshot(of: controller, as: .image(size: CGSize(width: width, height: height), traits: UITraitCollection { traits in
                    traits.userInterfaceStyle = dark ? .dark : .light
                    traits.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                    traits.horizontalSizeClass = width > 600 ? .regular : .compact
                }), named: name + "-" + (dark ? "dark" : "light") + "-\(Int(width))", record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
            }
        }
    }
}
#endif

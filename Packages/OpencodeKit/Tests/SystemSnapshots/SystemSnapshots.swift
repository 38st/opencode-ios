#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import WidgetKit
import OCDesign
import OCShared
import OCSync
import FeatureSettings

private let now = Date(timeIntervalSince1970: 1_800_036_000)
private let studio = "00000000-0000-0000-0000-0000000000B1", laptop = "00000000-0000-0000-0000-0000000000B2"
private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
private func row(_ id: String, _ title: String, server: String = studio, project: String = "opencode-ios", status: SystemSnapshot.Status, minutes: Double,
                 unread: Bool = false, request: SystemSnapshot.Request? = nil) -> SystemSnapshot.Session {
    .init(server: server, session: id, title: title, project: project, projectID: "prj_" + project, status: status, unread: unread, activity: at(minutes),
          runningSince: status.isRunning ? at(minutes - 12) : nil, requests: request == nil || request?.kind == .failure ? 0 : 1, request: request)
}
private let sessions = [
    row("ses_1", "Allow the edit to the pairing parser", status: .needsYou, minutes: -3, request: .init(id: "per_1", kind: .permission)),
    row("ses_2", "Choose the release branch", server: laptop, project: "docs", status: .needsYou, minutes: -9, request: .init(id: "frm_1", kind: .question)),
    row("ses_3", "Run the migration tests", status: .failed, minutes: -30, unread: true, request: .init(id: "error", kind: .failure)),
    row("ses_4", "Port the session panel widths", status: .running, minutes: -1),
    row("ses_5", "Profile the transcript scrolling", server: laptop, project: "desktop", status: .running, minutes: -2),
    row("ses_6", "Retry the flaky upload", status: .retrying, minutes: -6),
    row("ses_7", "Write the release notes", project: "docs", status: .idle, minutes: -40, unread: true),
    row("ses_8", "Tidy the review fixtures", status: .idle, minutes: -70),
    row("ses_9", "Sketch the widget layouts", server: laptop, project: "design", status: .idle, minutes: -200),
    row("ses_10", "Update the pairing guide", project: "docs", status: .idle, minutes: -600),
]
private let servers: [SystemSnapshot.Server] = [.init(id: studio, name: "Studio Mac", reachability: .online), .init(id: laptop, name: "Laptop", reachability: .online)]
private let pending = [studio: 1, laptop: 1]

/// The widget content of each state the snapshots cover.
private enum WidgetState: String, CaseIterable {
    case placeholder, noData = "no-data", needsApp = "needs-app", noServer = "no-server", removed = "server-removed", empty, many, stale, server = "per-server"
    /// The four states every kind shows the same way (no data, an update needed, no server, a removed server) are
    /// drawn for Needs you only; the five that differ by kind, for every kind.
    var kindSpecific: Bool { [.placeholder, .empty, .many, .stale, .server].contains(self) }
    func content(_ kind: WidgetKind, _ size: WidgetSize) -> WidgetContent {
        let all = SystemSnapshot(writtenAt: now, servers: servers, sessions: sessions)
        switch self {
        case .placeholder: return .placeholder(kind: kind, size: size)
        case .noData: return .make(.missing, pending: [:], kind: kind, server: nil, size: size, now: now)
        case .needsApp: return .make(.newer(SystemSnapshot.currentVersion + 1), pending: [:], kind: kind, server: nil, size: size, now: now)
        case .noServer: return .make(.snapshot(.init(writtenAt: now)), pending: [:], kind: kind, server: nil, size: size, now: now)
        case .removed: return .make(.snapshot(all), pending: pending, kind: kind, server: "00000000-0000-0000-0000-0000000000FF", size: size, now: now)
        case .empty: return .make(.snapshot(.init(writtenAt: now, servers: servers)), pending: [:], kind: kind, server: nil, size: size, now: now)
        case .many: return .make(.snapshot(all), pending: pending, kind: kind, server: nil, size: size, now: now)
        case .stale:
            // Last synced two hours ago, so every row is older than that.
            let paused = servers.map { SystemSnapshot.Server(id: $0.id, name: $0.name, reachability: .paused, syncedAt: at(-125)) }
            let earlier = sessions.map { row in
                var row = row
                row.activity = row.activity.addingTimeInterval(-125 * 60); row.runningSince = row.runningSince?.addingTimeInterval(-125 * 60)
                return row
            }
            return .make(.snapshot(.init(writtenAt: at(-120), servers: paused, sessions: earlier)), pending: pending, kind: kind, server: nil, size: size, now: now)
        case .server: return .make(.snapshot(all), pending: pending, kind: kind, server: studio, size: size, now: now)
        }
    }
}

private enum Rendering: String, CaseIterable { case light, dark, tinted }

@MainActor @Suite(.serialized) struct SystemSnapshots {
    private let record = ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1"

    /// Home Screen widgets: every kind, size and state in light, dark and the tinted Home Screen.
    @Test func homeScreenWidgets() {
        for size in [WidgetSize.small, .medium, .large] {
            for kind in WidgetKind.allCases {
                for state in WidgetState.allCases where state.kindSpecific || kind == .needsYou {
                    for rendering in Rendering.allCases {
                        capture(SessionWidgetView(content: state.content(kind, size), size: size, now: now), size: size, rendering: rendering,
                                name: "\(kind.rawValue)-\(size.rawValue)-\(state.rawValue)-\(rendering.rawValue)")
                    }
                }
            }
        }
    }
    /// Lock Screen accessories, unlocked and locked: titles are redacted while locked, counts stay.
    @Test func lockScreenWidgets() {
        for size in [WidgetSize.circular, .rectangular, .inline] {
            for state in WidgetState.allCases {
                for locked in [false, true] {
                    capture(SessionWidgetView(content: state.content(.needsYou, size), size: size, now: now), size: size, rendering: .dark, locked: locked,
                            name: "needs-you-\(size.rawValue)-\(state.rawValue)-\(locked ? "locked" : "unlocked")")
                }
            }
        }
    }
    /// The same rows at an accessibility text size still fit their widget.
    @Test func largeTextWidgets() {
        for size in [WidgetSize.small, .medium, .large] {
            capture(SessionWidgetView(content: WidgetState.many.content(.needsYou, size), size: size, now: now), size: size, rendering: .light,
                    name: "needs-you-\(size.rawValue)-many-accessibility3", typeSize: .accessibility3)
        }
    }
    /// Settings → Widgets and Shortcuts.
    @Test func settingsSection() {
        let system = SystemIntegration(store: nil, index: NoIndex(), manifest: nil, defaults: nil, reload: { _ in })
        let view = OCForm { SystemIntegrationSection(system: system) {} }
        for dark in [false, true] { for accessibility in [false, true] { for width: CGFloat in [393, 820] {
            let content = view.environment(\.colorScheme, dark ? .dark : .light).environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large).ocTheme()
            let controller = UIHostingController(rootView: content)
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            assertSnapshot(of: controller, as: .image(size: CGSize(width: width, height: accessibility ? 1700 : 760), traits: UITraitCollection { traits in
                traits.userInterfaceStyle = dark ? .dark : .light
                traits.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
                traits.horizontalSizeClass = width > 600 ? .regular : .compact
            }), named: "settings-\(dark ? "dark" : "light")-\(Int(width))-\(accessibility ? "accessibility5" : "default")", record: record)
        } } }
    }

    /// Draws a widget at its size. Full colour shows the container background; the tinted Home Screen keeps only the
    /// view's shape in one tint (the system's accent group is not reproduced); the Lock Screen is vibrant white.
    private func capture(_ view: SessionWidgetView, size: WidgetSize, rendering: Rendering, locked: Bool = false, name: String,
                         typeSize: DynamicTypeSize = .large, test: String = #function) {
        let frame = Self.frame(size)
        let mode: WidgetRenderingMode = size.isAccessory ? .vibrant : rendering == .tinted ? .accented : .fullColor
        let content = view
            .padding(size.isAccessory ? 0 : 16)
            .frame(width: frame.width, height: frame.height)
            .environment(\.widgetRenderingMode, mode)
            .environment(\.colorScheme, rendering == .light ? .light : .dark)
            .environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .environment(\.dynamicTypeSize, typeSize)
            .redacted(reason: locked ? .privacy : [])
        let drawn: AnyView
        switch mode {
        case .fullColor: drawn = AnyView(content.background(WidgetStyle.background).clipShape(RoundedRectangle(cornerRadius: 22)))
        case .accented: drawn = AnyView(ZStack { Color(red: 0.11, green: 0.16, blue: 0.24); Color(red: 0.62, green: 0.78, blue: 1).mask(content) }.clipShape(RoundedRectangle(cornerRadius: 22)))
        default: drawn = AnyView(ZStack { Color(white: 0.12); Color.white.mask(content) }.clipShape(RoundedRectangle(cornerRadius: size == .inline ? 4 : 12)))
        }
        let canvas = drawn.padding(8).background(Color(white: rendering == .light ? 0.9 : 0.05))
        let controller = UIHostingController(rootView: canvas)
        controller.overrideUserInterfaceStyle = rendering == .light ? .light : .dark
        assertSnapshot(of: controller, as: .image(size: CGSize(width: frame.width + 16, height: frame.height + 16), traits: UITraitCollection { traits in
            traits.userInterfaceStyle = rendering == .light ? .light : .dark
            traits.preferredContentSizeCategory = typeSize == .large ? .large : .accessibilityLarge
        }), named: name, record: record, testName: test)
    }
    /// iPhone widget sizes (6.3-inch class) in points.
    static func frame(_ size: WidgetSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .circular: CGSize(width: 76, height: 76)
        case .rectangular: CGSize(width: 172, height: 76)
        case .inline: CGSize(width: 257, height: 26)
        }
    }
}

private struct NoIndex: SpotlightIndexing {
    func index(_ items: [SpotlightItem]) async throws {}
    func delete(ids: [String]) async throws {}
    func delete(domains: [String]) async throws {}
    func deleteAll() async throws {}
}
#endif

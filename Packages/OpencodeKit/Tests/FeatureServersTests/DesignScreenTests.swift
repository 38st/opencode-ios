#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCModels
import OCFoundation
import OCDesign
import OCNetworking
import OCSecurity
import OCSync
@testable import FeatureServers

@MainActor @Suite(.serialized) struct DesignScreenTests {
    @Test func screens() async throws {
        let connection = DesignConnection()
        let registry = ServerRegistry(records: DesignRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()),
                                      pathMonitor: nil, localNetworkExplained: true, factory: { _, _, _ in connection })
        await registry.load()
        let endpoint = EndpointRecord(url: try #require(URL(string: "https://studio.example.com")), kind: .https)
        let server = try await registry.add(.init(name: "Studio Mac", endpoints: [endpoint], lastInfo: .init(version: "2.0.32")), credential: .password("fixture"))
        server.readPath.client = nil
        await connection.emit(.state(.connected(endpoint.id, since: .now)))
        for _ in 0..<20 { await Task.yield() }
        server.readPath.projects = [.init(raw: .object(["id": .string("project"), "name": .string("Design system"), "canonical": .string("/work/project")]))]
        let timestamp = Date.now.timeIntervalSince1970 * 1_000
        for (index, title) in ["Question", "Permission request", "Design system"].enumerated() {
            let info = SessionInfo(raw: .object(["id": .string("session-\(index)"), "projectID": .string("project"),
                "title": .string(title), "time": .object(["created": .number(timestamp - Double(index) * 1_000), "updated": .number(timestamp - Double(index) * 1_000)])]))
            server.readPath.sessions[info.id] = SessionModel(info: info)
        }
        let empty = ServerRegistry(records: DesignRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()), pathMonitor: nil)
        await empty.load()
        let screens: [(String, AnyView)] = [
            ("onboarding", AnyView(ServerRootView(registry: empty))),
            ("server-list", AnyView(ServerRootView(registry: registry))),
            ("workspace-home", AnyView(OCWorkspaceShell(homeInitiallyOpen: true) {
                WorkspaceSidebar(registry: registry, selectedServer: .constant(nil), selectedProject: .constant(nil), openSettings: {}, newSession: {}, selectSession: { _ in })
            } tabs: {
                OCProjectTabs(projects: [.init(id: "project", title: "Design system")], selection: .constant("project"))
            } main: { WorkspacePlaceholder(title: "Design system") } panel: { OCWorkspacePanel() })),
            ("server-management", AnyView(ServerSettingsView(registry: registry))),
            ("add-server", AnyView(AddServerView(registry: registry) { _ in })),
            ("add-server-password", AnyView(AddServerView(registry: registry, initialMethod: 1) { _ in })),
            ("re-pair", AnyView(AddServerView(registry: registry, repairing: server) { _ in })),
            ("update", AnyView(NavigationStack { UpdateServerView(server: server, outcome: .v1("1.19.3")) }.ocTheme())),
            ("server-detail", AnyView(NavigationStack { ServerDetailView(registry: registry, server: server) {} }.ocTheme())),
            ("diagnostics", AnyView(NavigationStack { DiagnosticsView(server: server) }.ocTheme())),
            ("local-network", AnyView(LocalNetworkExplanation {})),
        ]
        for (name, view) in screens {
            for dark in [false, true] {
                for size in [CGSize(width: 393, height: 852), CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820)] {
                    if name == "workspace-home" && size.width != 1180 { continue }
                    let controller = UIHostingController(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
                    controller.overrideUserInterfaceStyle = dark ? .dark : .light
                    assertSnapshot(of: controller, as: .image(size: size,
                        traits: UITraitCollection { traits in
                            traits.userInterfaceStyle = dark ? .dark : .light
                            traits.horizontalSizeClass = size.width > 600 ? .regular : .compact
                        }),
                        named: "\(name)-\(dark ? "dark" : "light")-\(Int(size.width))x\(Int(size.height))",
                        record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
                }
            }
        }
        await registry.shutdown(); await empty.shutdown()
    }

    @Test func commandPalette() async throws {
        let server = ServerID(rawValue: try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")))
        let sessions = ["Polish the iPad workspace", "Design system tokens", "Review the switcher", "Fix the pairing flow", "Release notes", "Archive old sessions"].enumerated().map { index, title in
            SwitcherIndex.Session(ref: SessionRef(serverID: server, sessionID: "ses_\(index)"), title: title, project: index % 2 == 0 ? "opencode-ios" : "design", updated: Double(100 - index))
        }
        let projects = [SwitcherIndex.Project(filter: server.rawValue.uuidString + ":design", name: "design", path: "/Users/Shared/design", server: "Studio Mac")]
        let commands = WorkspaceCommand.all.filter { $0 != .commandPalette && $0 != .find }
        for (name, query) in [("palette-empty", ""), ("palette-results", "design"), ("palette-none", "zzz")] {
            let palette = CommandPalette(search: { SwitcherIndex.groups(query: $0, commands: commands, sessions: sessions, projects: projects) },
                                         select: { _, _ in }, supportsWindows: true, maxHeight: 480, query: query, close: {})
                .frame(maxWidth: 640).background(OCColor.background).ocTheme()
            for dark in [false, true] { for accessibility in [false, true] { for width in [393.0, 820.0] {
                let controller = UIHostingController(rootView: palette.environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large).frame(maxHeight: .infinity, alignment: .top).background(OCColor.backgroundDeep))
                controller.overrideUserInterfaceStyle = dark ? .dark : .light
                assertSnapshot(of: controller, as: .image(size: CGSize(width: width, height: 852), traits: UITraitCollection { traits in
                    traits.userInterfaceStyle = dark ? .dark : .light
                    traits.horizontalSizeClass = width > 600 ? .regular : .compact
                    traits.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
                }), named: "\(name)-\(dark ? "dark" : "light")-\(Int(width))-\(accessibility ? "accessibility5" : "default")",
                    record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
            } } }
        }
    }
    /// The shell from a narrow split to a 13-inch screen in both orientations, with Home and review open where they fit.
    @Test func workspaceSizes() async throws {
        let connection = DesignConnection()
        let registry = ServerRegistry(records: DesignRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()),
                                      pathMonitor: nil, localNetworkExplained: true, factory: { _, _, _ in connection })
        await registry.load()
        let endpoint = EndpointRecord(url: try #require(URL(string: "https://studio.example.com")), kind: .https)
        let server = try await registry.add(.init(name: "Studio Mac", endpoints: [endpoint], lastInfo: .init(version: "2.0.32")), credential: .password("fixture"))
        server.readPath.client = nil
        server.readPath.projects = [.init(raw: .object(["id": .string("project"), "name": .string("Design system"), "canonical": .string("/work/project")]))]
        for size in [CGSize(width: 507, height: 1180), CGSize(width: 694, height: 1180), CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820),
                     CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032)] {
            let regular = size.width >= 600
            let view: AnyView = regular ? AnyView(OCWorkspaceShell(layout: .constant(OCWorkspaceLayout(homeOpen: true, reviewOpen: true))) {
                WorkspaceSidebar(registry: registry, selectedServer: .constant(nil), selectedProject: .constant(nil), openSettings: {}, newSession: {}, selectSession: { _ in })
            } tabs: {
                OCProjectTabs(projects: [.init(id: "project", title: "Design system")], selection: .constant("project"))
            } main: { WorkspacePlaceholder(title: "Design system") } panel: { OCWorkspacePanel() }) : AnyView(ServerRootView(registry: registry))
            let controller = UIHostingController(rootView: view.environment(\.colorScheme, .light))
            controller.overrideUserInterfaceStyle = .light
            assertSnapshot(of: controller, as: .image(size: size, traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .light
                traits.horizontalSizeClass = regular ? .regular : .compact
            }), named: "workspace-\(Int(size.width))x\(Int(size.height))", record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
        }
        await registry.shutdown()
    }

    @Test func fontsAndIconsAreBundled() {
        OCFonts.register()
        #expect(UIFont(name: "Inter-Regular", size: 14) != nil)
        #expect(UIFont(name: "JetBrainsMonoNFM-Regular", size: 13) != nil)
        for icon in ["server", "folder", "bubble-5", "refresh", "copy", "review", "terminal", "sidebar", "plus", "lock", "grid-plus", "settings-gear", "magnifying-glass", "brain", "branch"] {
            #expect(OCIcon.isBundled(icon))
        }
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        #expect(UIColor(OCColor.background).resolvedColor(with: light) != UIColor(OCColor.background).resolvedColor(with: dark))
        // Header bands sit on backgroundDeep, which layer1 matches in light mode.
        for traits in [light, dark] {
            #expect(UIColor(OCColor.band).resolvedColor(with: traits) != UIColor(OCColor.backgroundDeep).resolvedColor(with: traits))
        }
    }

    /// Every icon literal in the UI sources must name a bundled asset; a missing one draws an empty button.
    @Test func everyReferencedIconIsBundled() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Sources").standardizedFileURL
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasPrefix("Feature") || ["OCDesign", "OCRender"].contains($0) }
        // The expression after an icon parameter, up to the end of the argument; comparisons inside ternaries are skipped.
        let site = try Regex(#"(?:OCIcon\(|icon: |\.icon = |UIImage\(named: )([^,)\n]*)"#)
        let literal = try Regex(#"(== )?"([a-z0-9][a-z0-9-]*)""#)
        var names: [String: String] = [:]
        for module in modules {
            let enumerator = FileManager.default.enumerator(at: sources.appending(path: module), includingPropertiesForKeys: nil)
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                for match in text.matches(of: site) {
                    guard let expression = match.output[1].substring else { continue }
                    for name in expression.matches(of: literal) where name.output[1].substring == nil {
                        if let value = name.output[2].substring { names[String(value)] = file.lastPathComponent }
                    }
                }
            }
        }
        #expect(names.count > 40)
        for (name, file) in names.sorted(by: { $0.key < $1.key }) { #expect(OCIcon.isBundled(name), "\(file) references missing icon \(name)") }
        #expect(OCIcon.isBundled("dot-grid") && OCIcon.isBundled("chevron-up"))
    }

    /// File icons render `.original`, where `currentColor` resolves to black and vanishes in dark mode.
    @Test func fileIconsHaveNoCurrentColor() throws {
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/OCDesign/Resources/Icons.xcassets").standardizedFileURL
        let sets = try FileManager.default.contentsOfDirectory(atPath: assets.path).filter { $0.hasPrefix("filetype-") }
        #expect(sets.count > 100)
        for set in sets {
            for file in try FileManager.default.contentsOfDirectory(atPath: assets.appending(path: set).path) where file.hasSuffix(".svg") {
                #expect(try !String(contentsOf: assets.appending(path: set).appending(path: file), encoding: .utf8).contains("currentColor"), "\(set)")
            }
        }
    }


    @Test func toolbarIcons() {
        for dark in [false, true] {
            let view = NavigationStack {
                Text("Toolbar icons retain their outlines").font(OCType.body)
                    .ocNavigationTitle("Toolbar")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { OCIconButton("Sidebar", icon: "sidebar") {} }
                        ToolbarItem(placement: .topBarTrailing) { OCIconButton("Remove", icon: "trash") {} }
                    }
            }.ocTheme().environment(\.colorScheme, dark ? .dark : .light)
            let controller = UIHostingController(rootView: view)
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            assertSnapshot(of: controller, as: .image(size: .init(width: 393, height: 180),
                traits: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)), named: dark ? "dark" : "light",
                record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
        }
    }

    @Test func components() {
        for dark in [false, true] {
            let view = OCForm {
                HStack { Button("Connect") {}.buttonStyle(OCButtonStyle(.contrast)); Button("Remove") {}.buttonStyle(OCButtonStyle(.danger)) }
                HStack { OCBadge("V2"); OCPill("Connected", tone: .success); OCIconButton("Add", icon: "plus") {} }
                OCSidebarHeader("Projects")
                OCListRow("opencode-ios", subtitle: "3 sessions", kind: .project)
                OCListRow("Design system", selected: true)
                HStack { Button("Selected tab") {}.buttonStyle(OCTabStyle(selected: true)); Button("Tab") {}.buttonStyle(OCTabStyle(selected: false)) }
                TextField("Server URL", text: .constant("https://studio.example.com"))
                OCToggleRow("Notifications", isOn: .constant(true))
                OCCodeFrame("Terminal") { Text("opencode serve") }
                OCToolRow("Read sample.txt", icon: "code") { Text("original fixture line") }
                OCBanner("Pairing expires soon", tone: .warning)
                OCProgress("Syncing", value: 0.6)
                OCPromptDock { Text("Ask anything…").foregroundStyle(OCColor.textFaint) }
            }.ocTheme().environment(\.colorScheme, dark ? .dark : .light)
            assertSnapshot(of: UIHostingController(rootView: view), as: .image(size: .init(width: 393, height: 1100),
                traits: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)), named: dark ? "dark" : "light",
                record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
        }
    }
}

private actor DesignRecords: ServerRecordStore {
    var records: [ServerRecord] = []
    func load() -> [ServerRecord] { records }
    func save(_ records: [ServerRecord]) { self.records = records }
}
private actor DesignConnection: ConnectionControlling {
    nonisolated let output: AsyncStream<ConnectionOutput>
    let continuation: AsyncStream<ConnectionOutput>.Continuation
    init() { (output, continuation) = AsyncStream.makeStream() }
    func start(rerace: Bool) {}
    func stop() {}
    func forceReconnect(_ reason: ReconnectReason, rerace: Bool) {}
    func snapshot() -> ConnectionSnapshot { .init() }
    func configure(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String]) {}
    func setNetworkPath(_ path: NetworkPathStatus) {}
    func updateEndpoints(_ endpoints: [EndpointRecord]) {}
    func allowLocalNetwork() {}
    func emit(_ output: ConnectionOutput) { continuation.yield(output) }
}
#endif

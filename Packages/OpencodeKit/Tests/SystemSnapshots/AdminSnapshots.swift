#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCDesign
import OCFoundation
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync
@testable import FeatureSettings

/// A server's settings screens with seeded data: light and dark at iPhone width, the largest text size, and the
/// sidebar layout at iPad width.
@MainActor @Suite(.serialized) struct AdminSnapshots {
    @Test func providers() async throws {
        let (server, admin) = try await fixture()
        await capture(NavigationStack { ProvidersSection(admin: admin) }, name: "providers")
        await capture(NavigationStack { ProviderDetailView(admin: admin, integrationID: "openai") }, name: "provider-detail")
        let mock = try #require(admin.integrations.value?.first { $0.id == "mock" })
        await capture(KeyConnectSheet(admin: admin, integration: mock, method: try #require(mock.methods.first)), name: "provider-key")
        await capture(NavigationStack { ServerAdminView(server: server, section: .providers) }, name: "settings-sidebar", widths: [1180])
    }
    @Test func signIn() async throws {
        let (server, admin) = try await fixture()
        defer { withExtendedLifetime(server) {} }
        let openai = try #require(admin.integrations.value?.first { $0.id == "openai" })
        for (name, method) in [("signin-code", "code"), ("signin-waiting", "auto")] {
            admin.beginConnect(openai, method: try #require(openai.methods.first { $0.methodID == method }))
            let flow = try #require(admin.connect)
            await capture(ConnectFlowView(flow: flow) {}, name: name) { flow.phase != .starting }
        }
        let copilot = try #require(admin.integrations.value?.first { $0.id == "github-copilot" })
        admin.beginConnect(copilot, method: try #require(copilot.methods.first))
        let command = try #require(admin.connect)
        await capture(ConnectFlowView(flow: command) {}, name: "signin-command") {
            if case .command(let message) = command.phase { message != nil } else { false }
        }
        admin.beginConnect(openai, method: try #require(openai.methods.first { $0.methodID == "denied" }))
        let failed = try #require(admin.connect)
        await capture(ConnectFlowView(flow: failed) {}, name: "signin-failed") { failed.phase.isFinished }
        admin.endConnect()
    }
    @Test func extensions() async throws {
        let (server, admin) = try await fixture()
        defer { withExtendedLifetime(server) {} }
        await capture(NavigationStack { MCPSection(admin: admin) }, name: "mcp")
        await capture(NavigationStack { SavedPermissionsSection(admin: admin) }, name: "saved-permissions")
        await capture(NavigationStack { CatalogSection(admin: admin) }, name: "agents")
        let agent = try #require(admin.catalog?.agents.value?.first)
        await capture(NavigationStack { AgentDetailView(agent: agent) }, name: "agent-detail")
    }
    @Test func projectsAndConfiguration() async throws {
        let (server, admin) = try await fixture()
        await capture(NavigationStack { ProjectsSection(admin: admin) }, name: "projects")
        let project = try #require(admin.project)
        await capture(NavigationStack { ProjectEditView(admin: admin, project: project) }, name: "project-edit")
        await capture(NavigationStack { ConfigurationSection(admin: admin) }, name: "configuration")
        await capture(NavigationStack { AdministrationSection(server: server, admin: admin) }, name: "administration")
        await capture(NavigationStack { WorktreesSection(admin: admin) }, name: "worktrees")
        let worktree = try #require(admin.worktrees(for: "prj").value?.last)
        await capture(WorktreeRemovalSheet(admin: admin, worktree: worktree, projectID: "prj"), name: "worktree-dirty")
    }

    private func fixture() async throws -> (ServerStore, ServerAdminModel) {
        let endpoint = EndpointRecord(url: try #require(URL(string: "https://studio.example.com")), kind: .https)
        let server = ServerStore(record: .init(name: "Studio Mac", endpoints: [endpoint], lastInfo: .init(version: "2.2.1", capabilities: .init(persistentPty: true))),
                                 connection: SnapshotConnection(), credentials: CredentialStore(secrets: InMemorySecretStore()))
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:4096")!, transport: AdminSnapshotTransport())
        server.readPath.client = { api }
        server.readPath.projects = [project("prj", "opencode-ios", active: 3, start: "bun install"), project("docs", "docs", active: 2)]
        let admin = server.readPath.admin
        admin.appear()
        admin.integrations.seed(Self.integrations)
        let catalog = try #require(admin.catalog)
        catalog.mcp.seed([mcp("github", ["status": .string("connected")]), mcp("linear", ["status": .string("needs_auth"), "error": .string("Sign in to continue")], integration: "linear"),
                          mcp("broken", ["status": .string("failed"), "error": .string("NotFound: ChildProcess.spawn (/usr/local/bin/broken-mcp)")]),
                          mcp("sentry", ["status": .string("disabled")])])
        catalog.agents.seed([
            AgentInfo(raw: .object(["id": .string("build"), "name": .string("Build"), "mode": .string("primary"), "hidden": .bool(false),
                                    "description": .string("The default agent. Executes tools based on configured permissions."),
                                    "permissions": .array([rule("*", "*", "allow"), rule("read", "*.env", "ask"), rule("edit", "*", "ask"), rule("browser", "*", "deny")])])),
            AgentInfo(raw: .object(["id": .string("reviewer"), "name": .string("Reviewer"), "mode": .string("primary"), "hidden": .bool(false), "color": .string("#8476CA"),
                                    "model": .object(["providerID": .string("openai"), "id": .string("gpt-5")]), "steps": .integer(40),
                                    "description": .string("Review changes carefully"), "permissions": .array([rule("*", "*", "ask")])])),
            AgentInfo(raw: .object(["id": .string("general"), "name": .string("General"), "mode": .string("subagent"), "hidden": .bool(false),
                                    "description": .string("Research complex questions in parallel."), "permissions": .array([rule("*", "*", "allow"), rule("question", "*", "deny")])]))])
        admin.savedPermissions(for: "prj").seed([
            SavedPermission(raw: .object(["id": .string("psv_2"), "projectID": .string("prj"), "action": .string("shell"), "resource": .string("git status *"), "time": .object(["created": .integer(1_800_000_000_000)])])),
            SavedPermission(raw: .object(["id": .string("psv_1"), "projectID": .string("prj"), "action": .string("edit"), "resource": .string("Sources/**"), "time": .object(["created": .integer(1_799_900_000_000)])]))])
        admin.archivedProjects.seed([project("old", "prototype", active: 1, archived: true)])
        admin.config.seed([
            ConfigEntry(raw: .object(["type": .string("directory"), "path": .string("/Users/Shared/.config/opencode")])),
            ConfigEntry(raw: .object(["type": .string("document"), "path": .string("/Users/Shared/.config/opencode/opencode.json"), "info": .object([
                "model": .object(["providerID": .string("openai"), "model": .string("gpt-5")]), "shell": .string("/bin/zsh"),
                "providers": .object(["openai": .object(["settings": .object(["apiKey": .string("sk-live-secret"), "baseURL": .string("https://api.openai.com/v1")])])]),
                "mcp": .object(["servers": .object(["github": .object(["type": .string("remote"), "url": .string("https://mcp.example.com"),
                                                                       "headers": .object(["Authorization": .string("Bearer secret")])])])])])]))])
        admin.shells.seed([ShellOption(raw: .object(["path": .string("/bin/zsh"), "name": .string("zsh"), "acceptable": .bool(true)])),
                           ShellOption(raw: .object(["path": .string("/bin/bash"), "name": .string("bash"), "acceptable": .bool(true)]))])
        admin.locations.seed([Location(directory: "/Users/Shared/opencode-ios"), Location(directory: "/Users/Shared/docs")])
        admin.worktrees(for: "prj").seed([WorktreeInfo(raw: .object(["directory": .string("/Users/Shared/opencode-ios")])),
                                          WorktreeInfo(raw: .object(["directory": .string("/Users/Shared/worktree/brave-falcon"), "strategy": .string("git")]))])
        server.readPath.handle(ServerEvent.decode(Data(#"{"id":"evt_1","type":"installation.update-available","created":1,"data":{"version":"2.3.0"}}"#.utf8)))
        // Seeded values count as loaded, so the screens' own loads keep them.
        try await fresh(admin.integrations); try await fresh(admin.config); try await fresh(admin.shells); try await fresh(admin.locations)
        try await fresh(admin.archivedProjects); try await fresh(admin.savedPermissions(for: "prj")); try await fresh(admin.worktrees(for: "prj"))
        try await fresh(catalog.mcp); try await fresh(catalog.agents)
        _ = try await catalog.models.load { [] }; _ = try await catalog.providers.load { [] }; _ = try await catalog.defaultModel.load { nil }
        _ = try await catalog.commands.load { .array([.object(["name": .string("review"), "description": .string("review changes [commit|branch|pr]")])]) }
        _ = try await catalog.skills.load { .array([.object(["id": .string("release"), "name": .string("release"), "description": .string("Cut a release"), "path": .string("/skills/release/SKILL.md"), "content": .string("# Release\n\nTag, then publish.")])]) }
        _ = try await catalog.references.load { .array([]) }; _ = try await catalog.vcs.load { .object([:]) }
        return (server, admin)
    }
    private func fresh<Value: Sendable>(_ cell: Revalidating<Value>) async throws {
        guard let value = cell.value else { return }
        _ = try await cell.load { value }
    }
    static let integrations: [IntegrationInfo] = [
        IntegrationInfo(raw: .object(["id": .string("openai"), "name": .string("OpenAI"), "methods": .array([
            .object(["type": .string("oauth"), "id": .string("code"), "label": .string("ChatGPT Pro/Plus (paste a code)")]),
            .object(["type": .string("oauth"), "id": .string("auto"), "label": .string("ChatGPT Pro/Plus (browser)")]),
            .object(["type": .string("oauth"), "id": .string("denied"), "label": .string("Denied")]),
            .object(["type": .string("key"), "label": .string("API key")]), .object(["type": .string("env"), "names": .array([.string("OPENAI_API_KEY")])])]),
            "connections": .array([
                .object(["type": .string("credential"), "id": .string("cred_2"), "label": .string("Work"), "method": .string("oauth"),
                         "status": .object(["status": .string("needs_auth"), "message": .string("The session expired")])]),
                .object(["type": .string("credential"), "id": .string("cred_1"), "label": .string("Personal"), "method": .string("key")]),
                .object(["type": .string("env"), "name": .string("OPENAI_API_KEY")])])])),
        IntegrationInfo(raw: .object(["id": .string("mock"), "name": .string("Fixture Mock"), "methods": .array([
            .object(["type": .string("key"), "label": .string("API key"), "form": .array([.object(["key": .string("resourceName"), "title": .string("Resource name"), "type": .string("string"), "required": .bool(true), "placeholder": .string("e.g. my-models")])])])]),
            "connections": .array([.object(["type": .string("credential"), "id": .string("cred_3"), "label": .string("Test account"), "method": .string("key")])])])),
        IntegrationInfo(raw: .object(["id": .string("github-copilot"), "name": .string("GitHub Copilot"), "methods": .array([
            .object(["type": .string("command"), "id": .string("gh"), "label": .string("GitHub CLI login"), "command": .array([.string("gh"), .string("auth"), .string("login")])])]),
            "connections": .array([])])),
        IntegrationInfo(raw: .object(["id": .string("amazon-bedrock"), "name": .string("Amazon Bedrock"), "methods": .array([
            .object(["type": .string("env"), "names": .array([.string("AWS_BEARER_TOKEN_BEDROCK")])]),
            .object(["type": .string("external"), "id": .string("aws-profile"), "label": .string("AWS profile")])]), "connections": .array([])])),
    ]
    private func project(_ id: String, _ name: String, active: Int64, start: String? = nil, archived: Bool = false) -> Project {
        var raw: JSONValue = .object(["id": .string(id), "canonical": .string("/Users/Shared/" + name), "name": .string(name), "vcs": .string("git"),
                                      "time": .object(["created": .integer(0), "updated": .integer(0), "active": .integer(active)])])
        if let start { raw.set("commands", .object(["start": .string(start)])) }
        if archived { raw.set(["time", "archived"], .integer(1)) }
        return Project(raw: raw)
    }
    private func mcp(_ name: String, _ status: [String: JSONValue], integration: String? = nil) -> MCPServer {
        var raw: JSONValue = .object(["name": .string(name), "status": .object(status)])
        raw.set("integrationID", integration.map(JSONValue.string))
        return MCPServer(raw: raw)
    }
    private func rule(_ action: String, _ resource: String, _ effect: String) -> JSONValue {
        .object(["action": .string(action), "resource": .string(resource), "effect": .string(effect)])
    }

    /// Draws the window as laid out, after `ready` holds and navigation titles have faded in.
    private func capture<V: View>(_ view: V, name: String, widths: [Double] = [393], height: Double = 852,
                                  until ready: @escaping () -> Bool = { true }) async {
        var variants: [(Bool, Bool, Double)] = []
        for width in widths { variants += width > 600 ? [(false, false, width)] : [(false, false, width), (true, false, width), (false, true, width)] }
        for (dark, accessibility, width) in variants {
            let size = CGSize(width: width, height: width > 600 ? 820 : height)
            let controller = UIHostingController(rootView: view
                .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.backgroundDeep))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            controller.traitOverrides.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
            controller.traitOverrides.horizontalSizeClass = width > 600 ? .regular : .compact
            controller.view.frame = CGRect(origin: .zero, size: size)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                Issue.record("Snapshots need a connected window scene"); return
            }
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.frame = CGRect(origin: .zero, size: size); window.rootViewController = controller; window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            for _ in 0..<200 where !ready() { try? await Task.sleep(for: .milliseconds(20)) }
            try? await Task.sleep(for: .milliseconds(800))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let label = "\(name)-\(dark ? "dark" : "light")-\(Int(width))-\(accessibility ? "accessibility5" : "default")"
            if ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1" {
                if let result = verifySnapshot(of: image, as: .image, named: label, record: true, testName: "admin"),
                   !result.contains("Record mode is on") { Issue.record(Comment(rawValue: result)) }
            } else {
                // Sheets have a system glass Cancel button, and sign-ins a spinner, that render a little differently each time.
                let sheet = name.hasPrefix("signin-") || name == "worktree-dirty" || name == "provider-key"
                assertSnapshot(of: image, as: .image(precision: sheet ? 0.995 : 1), named: label, testName: "admin")
            }
            window.isHidden = true
        }
    }
}

/// Answers the sign-in and status routes the screens call; seeded lists need no other route.
private struct AdminSnapshotTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = try #require(request.url), path = url.path, method = request.httpMethod ?? "GET"
        let located = { (data: String) in #"{"location":{"directory":"/Users/Shared/opencode-ios"},"data":"# + data + "}" }
        var status = 200, body = #"{"_tag":"NotFound","message":"Not in the fixture"}"#
        switch (method, path) {
        case ("POST", "/api/integration/openai/connect/oauth"):
            let id = (try? JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data()))?["methodID"]?.stringValue ?? "auto"
            body = located(#"{"attemptID":"con_\#(id)","url":"https://auth.example.com/oauth/authorize?client_id=opencode&state=fixture","instructions":"\#(id == "code" ? "Sign in, then copy the code shown." : "Complete authorization in your browser. This window will close automatically.")","mode":"\#(id == "code" ? "code" : "auto")","time":{"created":0,"expires":9999999999999}}"#)
        case ("GET", "/api/integration/openai/connect/oauth/con_denied"): body = located(#"{"status":"failed","message":"Access was denied."}"#)
        case ("GET", _) where path.hasPrefix("/api/integration/openai/connect/oauth/"): body = located(#"{"status":"pending"}"#)
        case ("POST", "/api/integration/github-copilot/connect/command"): body = located(#"{"attemptID":"con_gh","time":{"created":0}}"#)
        case ("GET", "/api/integration/github-copilot/connect/command/con_gh"):
            body = located(#"{"status":"pending","message":"! First copy your one-time code: ABCD-1234\nOpen https://github.com/login/device in your browser."}"#)
        case ("GET", "/api/vcs/status"):
            body = located(#"[{"file":"Sources/App.swift","additions":12,"deletions":3,"status":"modified"},{"file":"notes.md","additions":4,"deletions":0,"status":"added"}]"#)
        default: status = 404
        }
        return .init(data: Data(body.utf8), response: try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
    }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

actor SnapshotConnection: ConnectionControlling {
    nonisolated let output: AsyncStream<ConnectionOutput>
    init() { output = AsyncStream { _ in } }
    func start(rerace: Bool) {}
    func stop() {}
    func forceReconnect(_ reason: ReconnectReason, rerace: Bool) {}
    func snapshot() -> ConnectionSnapshot { .init() }
    func configure(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String]) {}
    func setNetworkPath(_ path: NetworkPathStatus) {}
    func updateEndpoints(_ endpoints: [EndpointRecord]) {}
    func allowLocalNetwork() {}
}
#endif

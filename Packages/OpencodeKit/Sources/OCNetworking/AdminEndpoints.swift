// Routes: packages/protocol/src/groups/{integration,credential,mcp,permission,plugin,project,worktree,config,location,
// debug}.ts at v2.2.1. `GET /api/credential` returns secret values and is never called: integrations' connections carry
// each account's ID, label and method, and the first is the active one.
import Foundation
import OCFoundation
import OCModels

public enum AdminEndpoints {
    // MARK: Integrations and accounts
    public static func integrations(_ directory: String) -> Endpoint<Located<LossyArray<IntegrationInfo>>> {
        .json(path: "/api/integration", scope: .location(directory: directory))
    }
    /// The key travels only in this request's body; the caller clears its copy afterwards.
    public static func connectKey(_ integrationID: String, directory: String, key: String, answers: JSONValue? = nil, label: String? = nil) throws -> Endpoint<Void> {
        var body: JSONValue = .object(["key": .string(key)])
        body.set("answer", answers); body.set("label", label.map(JSONValue.string))
        return void(.post, integration(integrationID, "connect/key"), directory: directory, body: try JSONEncoder().encode(body))
    }
    public static func startOAuth(_ integrationID: String, directory: String, methodID: String, answers: JSONValue? = nil, label: String? = nil) throws -> Endpoint<Located<OAuthAttempt>> {
        .json(method: .post, path: integration(integrationID, "connect/oauth"), scope: .location(directory: directory),
              body: try attemptBody(methodID, answers, label))
    }
    public static func oauthStatus(_ integrationID: String, attempt: String, directory: String) -> Endpoint<AttemptStatus> {
        status(integration(integrationID, "connect/oauth/" + pathSegment(attempt)), directory: directory)
    }
    public static func completeOAuth(_ integrationID: String, attempt: String, directory: String, code: String?) throws -> Endpoint<Void> {
        var body: JSONValue = .object([:]); body.set("code", code.map(JSONValue.string))
        return void(.post, integration(integrationID, "connect/oauth/\(pathSegment(attempt))/complete"), directory: directory, body: try JSONEncoder().encode(body))
    }
    /// Idempotent.
    public static func cancelOAuth(_ integrationID: String, attempt: String, directory: String) -> Endpoint<Void> {
        void(.delete, integration(integrationID, "connect/oauth/" + pathSegment(attempt)), directory: directory)
    }
    /// Runs the method's login command on the server machine.
    public static func startCommand(_ integrationID: String, directory: String, methodID: String, label: String? = nil) throws -> Endpoint<Located<CommandAttempt>> {
        .json(method: .post, path: integration(integrationID, "connect/command"), scope: .location(directory: directory),
              body: try attemptBody(methodID, nil, label))
    }
    public static func commandStatus(_ integrationID: String, attempt: String, directory: String) -> Endpoint<AttemptStatus> {
        status(integration(integrationID, "connect/command/" + pathSegment(attempt)), directory: directory)
    }
    public static func cancelCommand(_ integrationID: String, attempt: String, directory: String) -> Endpoint<Void> {
        void(.delete, integration(integrationID, "connect/command/" + pathSegment(attempt)), directory: directory)
    }
    public static func renameCredential(_ id: String, label: String) throws -> Endpoint<Void> {
        void(.patch, "/api/credential/" + pathSegment(id), body: try JSONEncoder().encode(["label": label]))
    }
    public static func activateCredential(_ id: String) -> Endpoint<Void> { void(.post, "/api/credential/\(pathSegment(id))/activate") }
    public static func removeCredential(_ id: String) -> Endpoint<Void> { void(.delete, "/api/credential/" + pathSegment(id)) }

    // MARK: MCP
    public static func mcpConnect(_ server: String, directory: String) -> Endpoint<Void> {
        void(.post, "/api/experimental/mcp/\(pathSegment(server))/connect", directory: directory)
    }
    public static func mcpDisconnect(_ server: String, directory: String) -> Endpoint<Void> {
        void(.post, "/api/experimental/mcp/\(pathSegment(server))/disconnect", directory: directory)
    }

    // MARK: Saved permissions
    public static func savedPermissions(projectID: String) -> Endpoint<DataResponse<LossyArray<SavedPermission>>> {
        .json(path: "/api/permission/saved", query: [URLQueryItem(name: "projectID", value: projectID)])
    }
    public static func deleteSavedPermission(_ id: String) -> Endpoint<Void> { void(.delete, "/api/permission/saved/" + pathSegment(id)) }

    // MARK: Catalogs
    public static func plugins(_ directory: String) -> Endpoint<Located<LossyArray<PluginInfo>>> {
        .json(path: "/api/plugin", scope: .location(directory: directory))
    }
    /// Checks one package plugin, or all of them without a target, and answers the refreshed list.
    public static func checkPlugins(_ directory: String, target: String? = nil) throws -> Endpoint<Located<LossyArray<PluginInfo>>> {
        var body: JSONValue = .object([:]); body.set("target", target.map(JSONValue.string))
        return .json(method: .post, path: "/api/plugin/check", scope: .location(directory: directory), body: try JSONEncoder().encode(body))
    }
    public static func updatePlugins(_ directory: String, targets: [String]) throws -> Endpoint<Void> {
        void(.post, "/api/plugin/update", directory: directory, body: try JSONEncoder().encode(["targets": targets]))
    }

    // MARK: Projects and worktrees
    public static let archivedProjects = Endpoint<LossyArray<Project>>.json(path: "/api/project", query: [URLQueryItem(name: "archived", value: "true")])
    /// Only the fields given change. An empty string clears a value the server stores as a string.
    public static func updateProject(_ id: String, name: String? = nil, icon: JSONValue? = nil, startCommand: String? = nil) throws -> Endpoint<Project> {
        var body: JSONValue = .object([:])
        body.set("name", name.map(JSONValue.string)); body.set("icon", icon)
        body.set("commands", startCommand.map { .object(["start": .string($0)]) })
        return .json(method: .patch, path: "/api/project/" + pathSegment(id), body: try JSONEncoder().encode(body))
    }
    public static func createWorktree(projectID: String, name: String? = nil) throws -> Endpoint<WorktreeInfo> {
        var body: JSONValue = .object(["projectID": .string(projectID)])
        body.set("name", name.map(JSONValue.string))
        return .json(method: .post, path: "/api/worktree", body: try JSONEncoder().encode(body))
    }
    /// DELETE with a JSON body. Without `force` a worktree with changes fails with `data.forceRequired`.
    public static func removeWorktree(projectID: String, directory: String, force: Bool) throws -> Endpoint<Void> {
        void(.delete, "/api/worktree", body: try JSONEncoder().encode(JSONValue.object([
            "projectID": .string(projectID), "directory": .string(directory), "force": .bool(force)])))
    }
    public static func refreshWorktrees(projectID: String) throws -> Endpoint<Void> {
        void(.post, "/api/worktree/refresh", body: try JSONEncoder().encode(["projectID": projectID]))
    }
    /// Uncommitted changes in a directory.
    public static func vcsStatus(_ directory: String) -> Endpoint<Located<LossyArray<FileDiff>>> {
        .json(path: "/api/vcs/status", scope: .location(directory: directory))
    }

    // MARK: Configuration and administration
    /// Documents and searched directories, lowest precedence first.
    public static func config(_ directory: String) -> Endpoint<LossyArray<ConfigEntry>> {
        .init(path: "/api/config", scope: .location(directory: directory)) { data, _ in
            // Answered bare at v2.2.1; accept the located envelope other routes use.
            let raw = try JSONDecoder().decode(JSONValue.self, from: data)
            return (raw["data"] ?? raw).lossy(ConfigEntry.self)
        }
    }
    /// Patches `shell` in the highest-precedence global document; `nil` returns to the server's default.
    public static func setShell(_ path: String?) throws -> Endpoint<Void> {
        void(.patch, "/api/experimental/config", body: try JSONEncoder().encode(JSONValue.object(["shell": path.map(JSONValue.string) ?? .null])))
    }
    public static let bootedLocations = Endpoint<LossyArray<Location>>.json(path: "/api/debug/location")
    public static func evictLocation(_ directory: String) -> Endpoint<Void> { void(.delete, "/api/debug/location", directory: directory) }
    /// Rebuilds every loaded location: pending permissions and questions are cancelled.
    public static let reloadLocations = void(.post, "/api/location/reload")

    // MARK: Helpers
    static func integration(_ id: String, _ suffix: String) -> String { "/api/integration/\(pathSegment(id))/" + suffix }
    static func attemptBody(_ methodID: String, _ answers: JSONValue?, _ label: String?) throws -> Data {
        var body: JSONValue = .object(["methodID": .string(methodID)])
        body.set("answer", answers); body.set("label", label.map(JSONValue.string))
        return try JSONEncoder().encode(body)
    }
    static func status(_ path: String, directory: String) -> Endpoint<AttemptStatus> {
        .init(path: path, scope: .location(directory: directory)) { data, _ in
            let raw = try JSONDecoder().decode(JSONValue.self, from: data)
            return AttemptStatus(raw: raw["data"] ?? raw)
        }
    }
    static func void(_ method: HTTPMethod, _ path: String, directory: String? = nil, body: Data? = nil) -> Endpoint<Void> {
        .init(method: method, path: path, scope: directory.map { .location(directory: $0) } ?? .global, body: body) { _, _ in () }
    }
}

// Routes: packages/protocol/src/groups/{pty,shell,config}.ts at v2.2.0. PTYs and shells are location-scoped; the shell
// list of `/api/config/shell` is global and answers a bare array.
import Foundation
import OCFoundation
import OCModels

public struct PtyTicket: Decodable, Sendable { public let ticket: String }

public enum TerminalEndpoints {
    public static func list(_ directory: String) -> Endpoint<Located<LossyArray<PtyInfo>>> {
        .json(path: "/api/pty", scope: .location(directory: directory))
    }
    /// Without a command the server starts its configured shell; a login shell gets `-l`.
    public static func create(_ directory: String, command: String? = nil, title: String? = nil) throws -> Endpoint<Located<PtyInfo>> {
        var body: JSONValue = .object([:])
        body.set("command", command.map(JSONValue.string)); body.set("title", title.map(JSONValue.string))
        return .json(method: .post, path: "/api/pty", scope: .location(directory: directory), body: try JSONEncoder().encode(body))
    }
    public static func get(_ id: String, directory: String) -> Endpoint<Located<PtyInfo>> {
        .json(path: path(id), scope: .location(directory: directory))
    }
    public static func update(_ id: String, directory: String, title: String? = nil, cols: Int? = nil, rows: Int? = nil) throws -> Endpoint<Located<PtyInfo>> {
        var body: JSONValue = .object([:])
        body.set("title", title.map(JSONValue.string))
        if let cols, let rows { body.set("size", .object(["cols": .integer(Int64(cols)), "rows": .integer(Int64(rows))])) }
        return .json(method: .put, path: path(id), scope: .location(directory: directory), body: try JSONEncoder().encode(body))
    }
    /// Kills a running PTY and removes it.
    public static func delete(_ id: String, directory: String) -> Endpoint<Void> {
        .init(method: .delete, path: path(id), scope: .location(directory: directory)) { _, _ in () }
    }
    /// A single-use ticket for 60 seconds. Only for an upgrade that lost its Authorization header; the custom header
    /// makes browsers send a CORS preflight.
    public static func connectToken(_ id: String, directory: String) -> Endpoint<Located<PtyTicket>> {
        var endpoint: Endpoint<Located<PtyTicket>> = .json(method: .post, path: path(id) + "/connect-token", scope: .location(directory: directory))
        endpoint.headers = ["x-opencode-ticket": "1"]
        return endpoint
    }
    public static let shells = Endpoint<LossyArray<ShellOption>>.json(path: "/api/config/shell")

    /// Running commands only.
    public static func runningShells(_ directory: String) -> Endpoint<Located<LossyArray<ShellInfo>>> {
        .json(path: "/api/shell", scope: .location(directory: directory))
    }
    public static func runShell(_ directory: String, command: String) throws -> Endpoint<Located<ShellInfo>> {
        .json(method: .post, path: "/api/shell", scope: .location(directory: directory),
              body: try JSONEncoder().encode(JSONValue.object(["command": .string(command)])))
    }
    public static func shell(_ id: String, directory: String) -> Endpoint<Located<ShellInfo>> {
        .json(path: "/api/shell/" + id, scope: .location(directory: directory))
    }
    /// Kills a running command and deletes its captured output.
    public static func removeShell(_ id: String, directory: String) -> Endpoint<Void> {
        .init(method: .delete, path: "/api/shell/" + id, scope: .location(directory: directory)) { _, _ in () }
    }
    static func path(_ id: String) -> String { "/api/pty/" + id }
}

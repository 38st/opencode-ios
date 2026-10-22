import Foundation
import OCFoundation
import OCModels

public enum ComposerEndpoints {
    public static func find(_ query: String, directory: String, type: String? = nil, limit: Int = 50) -> Endpoint<Located<LossyArray<FileEntry>>> {
        .json(path: "/api/fs/find", query: [.init(name: "query", value: query), .init(name: "limit", value: String(min(200, max(1, limit))))] + (type.map { [.init(name: "type", value: $0)] } ?? []), scope: .location(directory: directory))
    }
    public static func list(_ path: String, directory: String) -> Endpoint<Located<LossyArray<FileEntry>>> {
        .json(path: "/api/fs/list", query: [.init(name: "path", value: path)], scope: .location(directory: directory))
    }
    public static func worktrees(projectID: String) -> Endpoint<LossyArray<WorktreeInfo>> {
        .json(path: "/api/worktree", query: [.init(name: "projectID", value: projectID)])
    }
    public static func createWorktree(projectID: String, from: String, branch: String?) throws -> Endpoint<WorktreeInfo> {
        var body: JSONValue = .object(["projectID": .string(projectID), "from": .string(from)])
        body.set("branch", branch.flatMap { $0.isEmpty ? nil : .string($0) })
        return .json(method: .post, path: "/api/worktree", body: try JSONEncoder().encode(body))
    }
    public static func branches(_ search: String, directory: String) -> Endpoint<Located<LossyArray<String>>> {
        .json(path: "/api/vcs/branch", query: [.init(name: "search", value: search), .init(name: "limit", value: "50")], scope: .location(directory: directory))
    }
    public static func wait(_ session: String) -> Endpoint<Void> {
        .init(method: .post, path: "/api/experimental/session/\(session)/wait", scope: .session) { _, _ in () }
    }
}

import Foundation
import OCFoundation
import OCModels
import OCNetworking

extension ReadStore {
    public func findFiles(_ query: String, directory: String, type: String? = nil, limit: Int = 50) async throws -> [FileEntry] {
        try await writeAPI().send(ComposerEndpoints.find(query, directory: directory, type: type, limit: limit)).data.values
    }
    public func listDirectory(_ path: String, directory: String) async throws -> [FileEntry] {
        try await writeAPI().send(ComposerEndpoints.list(path, directory: directory)).data.values
    }
    public func resolveDirectory(_ directory: String) async throws -> Location {
        try await writeAPI().send(ReadEndpoints.location(directory))
    }
    public func worktrees(projectID: String) async throws -> [WorktreeInfo] {
        try await writeAPI().send(ComposerEndpoints.worktrees(projectID: projectID)).values
    }
    public func createWorktree(projectID: String, from: String, branch: String?) async throws -> WorktreeInfo {
        do { return try await writeAPI().send(ComposerEndpoints.createWorktree(projectID: projectID, from: from, branch: branch)) }
        catch APIError.server(tag: "WorktreeError", status: _, body: let raw) { throw WorktreeFailure(raw: raw) }
    }
    public func branches(_ search: String, directory: String) async throws -> [String] {
        try await writeAPI().send(ComposerEndpoints.branches(search, directory: directory)).data.values
    }
    public func waitForIdle(_ session: String) async throws {
        try await writeAPI().send(ComposerEndpoints.wait(session))
    }
}

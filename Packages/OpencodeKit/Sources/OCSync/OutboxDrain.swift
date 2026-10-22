import Foundation
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence

public enum OutboxAcknowledgement: Sendable {
    case prompt(InboxItem), session(SessionInfo)
}

/// A single owned drain preserves submission order. A transport failure blocks only
/// that session for this pass; the store schedules another pass while connected.
public actor OutboxProcessor {
    private let store: OutboxStore
    private let serverID: String
    private var task: Task<Void, any Error>?
    private var acknowledged: Set<String> = []
    public init(store: OutboxStore, serverID: String) { self.store = store; self.serverID = serverID }
    deinit { task?.cancel() }

    public func prepareLaunch(now: Date = Date()) async throws {
        for entry in try await store.entries(serverID: serverID) where entry.state == "pending" && now.timeIntervalSince(entry.createdAt) > 600 {
            try await store.update(id: entry.id, state: "needsConfirmation")
        }
    }
    public func acknowledge(_ id: String) async throws {
        acknowledged.insert(id)
        try await store.remove(id: id)
    }
    public func drain(using api: APIClient,
                      received: @escaping @Sendable (String, OutboxAcknowledgement) async -> Void = { _, _ in }) async throws {
        if let task { return try await task.value }
        let task = Task { try await self.pass(using: api, received: received) }
        self.task = task
        defer { self.task = nil; acknowledged.removeAll() }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func pass(using api: APIClient, received: @Sendable (String, OutboxAcknowledgement) async -> Void) async throws {
        var blocked: Set<String> = [], failedCreates: Set<String> = []
        var retry: (any Error)?
        for entry in try await store.entries(serverID: serverID) {
            if entry.state == "needsConfirmation" { blocked.insert(entry.sessionID) }
            if entry.operation == "create", entry.state != "pending" {
                if entry.state == "failed" { failedCreates.insert(entry.sessionID) }
                else { blocked.insert(entry.sessionID) }
            }
            guard entry.state == "pending", !blocked.contains(entry.sessionID), !acknowledged.contains(entry.id) else { continue }
            try Task.checkCancellation()
            guard !failedCreates.contains(entry.sessionID),
                  let raw = try? JSONDecoder().decode(JSONValue.self, from: entry.body), raw["id"]?.stringValue == entry.id else {
                try await store.update(id: entry.id, state: "failed"); continue
            }
            try await store.update(id: entry.id, state: "pending", attempts: entry.attempts + 1)
            do {
                let result: OutboxAcknowledgement
                if entry.operation == "create" {
                    // A create may have succeeded just before process death. Probe its
                    // minted ID before retrying; never replace an existing session.
                    if entry.attempts > 0, let existing = try await existingSession(entry.sessionID, api: api) {
                        result = .session(existing)
                    } else {
                        result = .session(try await api.send(WriteEndpoints.create(body: entry.body)).data)
                    }
                } else {
                    try await prelude(entry, api: api)
                    if acknowledged.contains(entry.id) { continue }
                    if entry.operation == "compact" {
                        result = .prompt(try await api.send(Endpoint<DataResponse<InboxItem>>.json(
                            method: .post, path: "/api/session/\(entry.sessionID)/compact", scope: .session, body: entry.body)).data)
                    } else {
                        result = .prompt(try await api.send(WriteEndpoints.prompt(entry.sessionID, body: entry.body)).data)
                    }
                }
                // Event callbacks may have delivered/cancelled this item already.
                if !acknowledged.contains(entry.id) { await received(entry.id, result) }
                try await acknowledge(entry.id)
            } catch APIError.server(_, let status, _) where (400..<500).contains(status) {
                if !acknowledged.contains(entry.id) {
                    try await store.update(id: entry.id, state: "failed")
                    if entry.operation == "create" { failedCreates.insert(entry.sessionID) }
                }
            } catch APIError.unauthorized {
                if !acknowledged.contains(entry.id) { try await store.update(id: entry.id, state: "failed") }
                if entry.operation == "create" { failedCreates.insert(entry.sessionID) }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if !acknowledged.contains(entry.id) { blocked.insert(entry.sessionID); retry = error }
            }
        }
        if let retry { throw retry }
    }
    private func existingSession(_ id: String, api: APIClient) async throws -> SessionInfo? {
        do { return try await api.send(ReadEndpoints.session(id)).data }
        catch APIError.server(tag: "SessionNotFoundError", status: 404, body: _) { return nil }
    }
    private func prelude(_ entry: OutboxEntry, api: APIClient) async throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: entry.prelude)
        guard raw["agent"] != nil || raw["model"] != nil || raw["commitRevert"]?.boolValue == true else { return }
        let info = try await api.send(ReadEndpoints.session(entry.sessionID)).data
        if let agent = raw["agent"]?.stringValue, agent != info.agent {
            try await api.send(WriteEndpoints.agent(entry.sessionID, agent: agent))
        }
        if raw["commitRevert"]?.boolValue == true, info.revert != nil {
            if let expected = raw["revertMessageID"]?.stringValue, info.revert?.messageID != expected {
                throw APIError.server(tag: "ConflictError", status: 409, body: .object(["message": .string("The staged revert changed. Review it before resending.")]))
            }
            try await api.send(WriteEndpoints.commitRevert(entry.sessionID))
        }
        // Revert commits remove model-selection rows at and after the boundary.
        // Always reapply the requested model after a commit (the server deduplicates it).
        if let model = raw["model"], !model.isNull,
           !ComposerPickers.sameSelection(ModelRef(raw: model), info.model) || (raw["commitRevert"]?.boolValue == true && info.revert != nil) {
            try await api.send(WriteEndpoints.model(entry.sessionID, model: ModelRef(raw: model)))
        }
    }
    public func stop() async {
        task?.cancel(); _ = try? await task?.value; task = nil
    }
}

public typealias OutboxDrain = OutboxProcessor

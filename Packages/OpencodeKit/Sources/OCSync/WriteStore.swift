import Foundation
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence

public enum WriteStoreError: Error, Sendable {
    case persistenceUnavailable, sessionUnavailable, stagedRevertNeedsConfirmation, requestUnavailable
}

extension ReadStore {
    /// Queue and outbox actions can remove the view that initiated them.
    public func performWrite(_ operation: @escaping @MainActor () async throws -> Void,
                             completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        owned {
            do { try await operation(); completion(.success(())) }
            catch { completion(.failure(error)) }
        }
    }
    /// Returns after the exact admission has reached SQLite, before network completion.
    @discardableResult public func sendPrompt(_ sessionID: String, input: PromptInput, prelude: WritePrelude = .init()) async throws -> String {
        guard cache != nil else { throw WriteStoreError.persistenceUnavailable }
        guard let session = sessions[sessionID] else { throw WriteStoreError.sessionUnavailable }
        if session.info.revert != nil && !prelude.commitRevert { throw WriteStoreError.stagedRevertNeedsConfirmation }
        let id = try await mintMessage(sessionID)
        var prepared = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(prelude))
        if prelude.commitRevert, let revert = session.info.revert { prepared.set("revertMessageID", .string(revert.messageID)) }
        else { prepared.set("commitRevert", .bool(false)) }
        let entry = OutboxEntry(id: id, serverID: serverID, sessionID: sessionID,
            prelude: try JSONEncoder().encode(prepared), body: try input.body(id: id), createdAt: clock.date())
        try await submit(entry)
        return id
    }
    @discardableResult public func createSession(location: Location, title: String? = nil, agent: String? = nil,
                                                 model: ModelRef? = nil, projectID: String = "") async throws -> String {
        guard cache != nil else { throw WriteStoreError.persistenceUnavailable }
        let id = try await minter.mintSession()
        let endpoint = try WriteEndpoints.create(id: id, location: location, title: title, agent: agent, model: model)
        guard let body = endpoint.body else { throw WriteStoreError.persistenceUnavailable }
        try await submit(.init(id: id, serverID: serverID, sessionID: id, body: body, createdAt: clock.date(), operation: "create"))
        if sessions[id]?.info.projectID.isEmpty == true { sessions[id]?.info["projectID"] = .string(projectID) }
        return id
    }
    func mintMessage(_ sessionID: String) async throws -> String {
        let known = (sessions[sessionID]?.transcript?.order ?? []) + (sessions[sessionID]?.pending.map(\.id) ?? []) +
            outboxEntries.values.filter { $0.sessionID == sessionID && $0.operation != "create" }.map(\.id)
        return try await minter.mintMessage(sessionID: sessionID, newestKnownMessageID: known.filter { OpencodeID.components(of: $0)?.kind == .message }.max())
    }
    func submit(_ entry: OutboxEntry) async throws {
        guard let cache else { throw WriteStoreError.persistenceUnavailable }
        let previous = submissionTask
        let task = Task { [weak self] in
            _ = try? await previous?.value
            try await OutboxStore(writer: cache.writer).save(entry)
            guard let self else { return }
            self.outboxEntries[entry.id] = entry
            self.materializeOutbox(entry)
            self.startWrites()
        }
        submissionTask = task
        try await task.value
    }
    func materializeOutbox(_ entry: OutboxEntry) {
        guard let raw = try? JSONDecoder().decode(JSONValue.self, from: entry.body) else { return }
        if entry.operation == "create" {
            guard sessions[entry.id] == nil, entry.state != "failed" else { return }
            var info = raw
            let now = entry.createdAt.timeIntervalSince1970 * 1_000
            info.set("time", .object(["created": .number(now), "updated": .number(now)]))
            sessions[entry.id] = SessionModel(info: .init(raw: info), transcript: TranscriptModel())
            return
        }
        guard !admittedInputs.contains(entry.id), !consumedInputs.contains(entry.id), let session = sessions[entry.sessionID] else { return }
        if session.transcript == nil { session.transcript = TranscriptModel() }
        var payload = raw
        for key in ["id", "delivery", "resume"] { payload.set(key, nil) }
        let files = (raw["files"]?.arrayValue ?? []).compactMap { file -> JSONValue? in
            guard let uri = file["uri"]?.stringValue else { return nil }
            var file = file
            if uri.hasPrefix("file://") {
                file.set("uri", nil); file.set("source", .object(["type": .string("uri"), "uri": .string(uri)]))
                return file
            }
            guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ","), uri[..<comma].hasSuffix(";base64") else { return nil }
            file.set("uri", nil); file.set("source", .object(["type": .string("inline")]))
            file.set("mime", .string(String(uri.dropFirst(5).prefix(upTo: comma).dropLast(7))))
            file.set("data", .string(String(uri[uri.index(after: comma)...])))
            return file
        }
        payload.set("files", files.isEmpty ? nil : .array(files))
        let item = InboxItem(raw: .object(["id": .string(entry.id), "sessionID": .string(entry.sessionID),
            "type": .string(entry.operation == "compact" ? "compaction" : "user"), "delivery": raw["delivery"] ?? .string("steer"),
            "time": .object(["created": .number(entry.createdAt.timeIntervalSince1970 * 1_000)]), "payload": payload]))
        if !session.pending.contains(where: { $0.id == item.id }) { session.pending.append(item) }
        if session.transcript?.messages[item.id]?.acknowledged != true {
            materialize(item, session: session, acknowledged: false)
        }
    }
    public func setWritesConnected(_ connected: Bool) {
        writesConnected = connected
        if connected { startWrites() }
        else {
            writeTask?.cancel()
            for session in sessions.values { session.executionID = nil }
        }
    }
    func startWrites() {
        guard writesConnected, !stopped, writeTask == nil, outboxDrain != nil, client != nil,
              hasSendableOutbox else { return }
        writeTask = Task { [weak self, clock] in
            guard let self else { return }
            defer { self.writeTask = nil; self.startWrites() }
            var attempts = 0
            while !Task.isCancelled && self.writesConnected && !self.stopped {
                await self.flushWrites()
                guard self.hasSendableOutbox else { return }
                attempts += 1
                do { try await clock.sleep(.seconds(min(30, 1 << min(attempts - 1, 5)))) }
                catch { return }
            }
        }
    }
    public func flushWrites() async {
        guard let client, let outboxDrain, !stopped else { return }
        let lease = BackgroundLease(provider: background)
        lease.begin { [weak self] in self?.writesConnected = false; self?.writeTask?.cancel() }
        defer { lease.end() }
        do {
            let api = try await client()
            try await outboxDrain.drain(using: api) { [weak self] id, result in
                await self?.acknowledgeResponse(id, result: result)
            }
            writeError = nil
        } catch is CancellationError {} catch APIError.cancelled {} catch { writeError = "Waiting to send. Your prompt is saved on this device." }
        do { try await reloadOutbox() } catch { writeError = "Could not read the saved outbox." }
    }
    func acknowledgeResponse(_ id: String, result: OutboxAcknowledgement) {
        switch result {
        case .session(let info):
            acknowledgedSessions.insert(id)
            let session = sessions[info.id] ?? SessionModel(info: info, transcript: TranscriptModel())
            session.info = info; sessions[info.id] = session; dirty.insert(info.id)
        case .prompt(let item):
            guard let session = sessions[item.sessionID] else { break }
            if id != item.id { session.pending.removeAll { $0.id == id }; session.transcript?.remove(id) }
            guard !admittedInputs.contains(id), !consumedInputs.contains(item.id) else { break }
            admittedInputs.insert(id)
            session.pending.removeAll { $0.id == item.id }; session.pending.append(item)
            materialize(item, session: session)
        }
        outboxEntries.removeValue(forKey: id)
        clearOutboxEditing(id)
        schedulePersistence()
    }
    func acknowledgeEvent(_ id: String) {
        outboxEntries.removeValue(forKey: id)
        clearOutboxEditing(id)
        if let outboxDrain { owned { try await outboxDrain.acknowledge(id) } }
    }
    func reloadOutbox() async throws {
        guard let cache else { return }
        var entries: [OutboxEntry]
        // A submission can complete while the SQLite read is suspended. Do not
        // replace that newer local admission with an older query result.
        while true {
            let before = outboxEntries
            entries = try await OutboxStore(writer: cache.writer).entries(serverID: serverID)
            if before == outboxEntries { break }
            try Task.checkCancellation()
        }
        outboxEntries = Dictionary(entries.filter { !admittedInputs.contains($0.id) && !acknowledgedSessions.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for composer in composers.values {
            if let id = composer.options.editingOutboxID, outboxEntries[id]?.state != "failed" { composer.cancelEditingOutbox() }
        }
        for entry in entries {
            if entry.operation == "create", entry.state == "failed", !acknowledgedSessions.contains(entry.id) {
                try await recoverFailedCreation(entry, entries: entries)
                sessions.removeValue(forKey: entry.id)
            }
            else { materializeOutbox(entry) }
        }
    }
    private var hasSendableOutbox: Bool {
        let awaitingConfirmation = Set(outboxEntries.values.filter { $0.state == "needsConfirmation" }.map(\.sessionID))
        return outboxEntries.values.contains { entry in
            guard entry.state == "pending", !awaitingConfirmation.contains(entry.sessionID) else { return false }
            if let create = outboxEntries[entry.sessionID], create.operation == "create" { return create.state == "pending" }
            return true
        }
    }
    /// Explicit confirmation of an old admission preserves its original ID and bytes.
    public func confirmOutbox(_ id: String) async throws {
        guard let cache, outboxEntries[id]?.state == "needsConfirmation" else { return }
        try await OutboxStore(writer: cache.writer).update(id: id, state: "pending")
        outboxEntries[id]?.state = "pending"; clearOutboxEditing(id); startWrites()
    }
    public func discardOutbox(_ id: String) async throws {
        guard let cache, let entry = outboxEntries[id], entry.state != "pending" else { return }
        if entry.operation == "create" {
            try await OutboxStore(writer: cache.writer).removeSession(serverID: serverID, sessionID: entry.sessionID)
            for other in outboxEntries.values where other.sessionID == entry.sessionID { clearOutboxEditing(other.id) }
            outboxEntries = outboxEntries.filter { $0.value.sessionID != entry.sessionID }
            sessions.removeValue(forKey: entry.sessionID)
            failedCreationDirectories.removeValue(forKey: entry.sessionID)
            startWrites()
            return
        }
        try await OutboxStore(writer: cache.writer).remove(id: id)
        outboxEntries.removeValue(forKey: id)
        clearOutboxEditing(id)
        sessions[entry.sessionID]?.pending.removeAll { $0.id == id }
        if sessions[entry.sessionID]?.transcript?.messages[id]?.acknowledged == false { sessions[entry.sessionID]?.transcript?.remove(id) }
        startWrites()
    }
    public func editAndResend(_ id: String, input: PromptInput, prelude: WritePrelude = .init()) async throws -> String {
        guard let entry = outboxEntries[id], entry.state == "failed" else { throw WriteStoreError.requestUnavailable }
        let next = try await sendPrompt(entry.sessionID, input: input, prelude: prelude)
        try await discardOutbox(id)
        return next
    }
    private func clearOutboxEditing(_ id: String) {
        for composer in composers.values where composer.options.editingOutboxID == id { composer.cancelEditingOutbox() }
    }
    func writeAPI() async throws -> APIClient {
        guard let client else { throw WriteStoreError.sessionUnavailable }
        return try await client()
    }
}

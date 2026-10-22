import Foundation
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence

extension ReadStore {
    public func interrupt(_ session: String, resume: Bool = false) async throws -> Bool {
        try await writeAPI().send(WriteEndpoints.interrupt(session, resume: resume)).interrupted
    }
    public func setAgent(_ session: String, agent: String) async throws {
        try await waitForCreate(session)
        try await writeAPI().send(WriteEndpoints.agent(session, agent: agent))
    }
    public func setModel(_ session: String, model: ModelRef) async throws {
        try await waitForCreate(session)
        try await writeAPI().send(WriteEndpoints.model(session, model: model))
    }
    public func command(_ session: String, name: String, input: PromptInput) async throws {
        try await waitForCreate(session)
        try await writeAPI().send(WriteEndpoints.command(session, name: name, input: input))
    }
    @discardableResult public func shell(_ session: String, command: String) async throws -> String {
        try await waitForCreate(session)
        let id = try await mintMessage(session)
        try await writeAPI().send(WriteEndpoints.shell(session, id: id, command: command))
        return id
    }
    public func renameSession(_ id: String, title: String) async throws {
        guard let session = sessions[id] else { throw WriteStoreError.sessionUnavailable }
        try await waitForCreate(id)
        let previous = session.info["title"]
        session.info["title"] = .string(title); pendingTitles[id] = title
        defer { pendingTitles.removeValue(forKey: id) }
        do { try await writeAPI().send(WriteEndpoints.rename(id, title: title)); dirty.insert(id); schedulePersistence() }
        catch {
            if session.info.title == title { session.info["title"] = previous }
            scheduleRefresh(id); throw error
        }
    }
    public func deleteSession(_ id: String) async throws {
        try await waitForCreate(id)
        let removed = family(id), ids = Set(removed.map(\.id))
        hiddenSessions.formUnion(ids)
        for id in ids { sessions.removeValue(forKey: id) }
        do {
            try await writeAPI().send(WriteEndpoints.delete(id))
            for id in ids { try await cache?.writer.deleteSession(serverID: serverID, sessionID: id) }
        } catch {
            hiddenSessions.subtract(ids.subtracting(deletedSessions))
            for session in removed where !deletedSessions.contains(session.id) { sessions[session.id] = session }
            throw error
        }
    }
    /// Optimistic removal dismisses the requesting view, so the store owns this task.
    public func deleteSession(_ id: String, completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        owned { [weak self] in
            guard let self else { return }
            do { try await self.deleteSession(id); completion(.success(())) }
            catch { self.writeError = WriteErrorMessage.message(error); completion(.failure(error)) }
        }
    }
    public func fork(_ session: String, before: String? = nil) async throws -> SessionInfo {
        let info = try await writeAPI().send(WriteEndpoints.fork(session, before: before)).data
        sessions[info.id] = SessionModel(info: info); dirty.insert(info.id); schedulePersistence()
        return info
    }
    @discardableResult public func compact(_ session: String, model: ModelRef? = nil) async throws -> String {
        if let existing = outboxEntries.values.first(where: { $0.sessionID == session && $0.operation == "compact" && $0.state == "pending" }) { return existing.id }
        let id = try await mintMessage(session)
        let endpoint = try WriteEndpoints.compact(session, id: id)
        guard let body = endpoint.body else { throw WriteStoreError.persistenceUnavailable }
        try await submit(.init(id: id, serverID: serverID, sessionID: session,
            prelude: JSONEncoder().encode(WritePrelude(model: model)), body: body, createdAt: clock.date(), operation: "compact"))
        return id
    }
    public func stageRevert(_ session: String, message: String, files: Bool = true) async throws {
        let revert = try await writeAPI().send(WriteEndpoints.stageRevert(session, message: message, files: files)).data
        sessions[session]?.info["revert"] = revert.raw; dirty.insert(session); schedulePersistence()
    }
    public func commitRevert(_ session: String) async throws {
        try await writeAPI().send(WriteEndpoints.commitRevert(session))
        try await refreshSession(session)
    }
    public func redo(_ session: String) async throws {
        try await writeAPI().send(WriteEndpoints.redo(session))
        sessions[session]?.info["revert"] = nil; dirty.insert(session); schedulePersistence()
    }
    public func changeDelivery(_ sessionID: String, itemID: String, delivery: Delivery) async throws {
        guard let session = sessions[sessionID], let index = session.pending.firstIndex(where: { $0.id == itemID }), outboxEntries[itemID] == nil, pendingDeliveries[itemID] == nil else { throw WriteStoreError.requestUnavailable }
        let previous = session.pending[index]
        var raw = previous.raw; raw.set("delivery", try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(delivery)))
        pendingDeliveries[itemID] = raw["delivery"]
        session.pending[index] = .init(raw: raw)
        do { try await writeAPI().send(WriteEndpoints.delivery(sessionID, item: itemID, delivery: delivery)) }
        catch {
            let unacknowledged = pendingDeliveries.removeValue(forKey: itemID) != nil
            if unacknowledged, let index = session.pending.firstIndex(where: { $0.id == itemID }), session.pending[index].raw == raw { session.pending[index] = previous }
            scheduleRefresh(sessionID); throw error
        }
    }
    public func cancelPending(_ sessionID: String, itemID: String, restore: Bool = true) async throws {
        guard let session = sessions[sessionID], let item = session.pending.first(where: { $0.id == itemID }), outboxEntries[itemID] == nil else { throw WriteStoreError.requestUnavailable }
        // Persist the recovered input before asking the server to discard it.
        if restore && item.type == "user" { _ = try await restoreInput(item.fields.payload, sessionID: sessionID) }
        cancelledInputs.insert(itemID)
        session.pending.removeAll { $0.id == itemID }; session.transcript?.remove(itemID)
        do {
            try await writeAPI().send(WriteEndpoints.cancelInbox(sessionID, item: itemID))
            consumedInputs.insert(itemID)
        }
        catch {
            if !consumedInputs.contains(itemID) {
                cancelledInputs.remove(itemID); session.pending.append(item); materialize(item, session: session)
            }
            scheduleRefresh(sessionID); throw error
        }
    }
    func waitForCreate(_ id: String) async throws {
        if outboxEntries[id]?.operation == "create" { await flushWrites() }
        guard sessions[id] != nil, outboxEntries[id]?.operation != "create" else { throw WriteStoreError.sessionUnavailable }
    }
    @discardableResult public func restoreInput(_ input: MessageFields, sessionID: String, append: Bool = true,
                                                editingOutboxID: String? = nil) async throws -> Draft {
        if !append {
            return try await replacingDraft(sessionID) {
                try await writeRestoredInput(input, sessionID: sessionID, append: false, editingOutboxID: editingOutboxID)
            }
        }
        guard let session = sessions[sessionID] else { throw WriteStoreError.sessionUnavailable }
        let composer = composer(sessionID: sessionID, directory: session.info.location.directory)
        if !composer.loaded { try await composer.reload() }
        try composer.lockEditing(); defer { composer.unlockEditing() }
        return try await writeRestoredInput(input, sessionID: sessionID, append: true, editingOutboxID: editingOutboxID)
    }
    private func writeRestoredInput(_ input: MessageFields, sessionID: String, append: Bool,
                                    editingOutboxID: String? = nil) async throws -> Draft {
        guard let drafts else { throw WriteStoreError.persistenceUnavailable }
        try await composers["session:" + sessionID]?.flush()
        let old = try await drafts.load(serverID: serverID, sessionID: sessionID)
        if append && old?.options.shell == true { throw ComposerError.shellRestore }
        let id = old?.id ?? UUID().uuidString
        var text = append ? try old?.attributedText ?? AttributedString() : AttributedString()
        if !text.characters.isEmpty { text.append(AttributedString("\n\n")) }
        let references = sessions[sessionID].flatMap { catalogs[$0.info.location.key]?.references.value }
        text.append(ComposerInput.restoreText(input.raw, references: references))
        var attachments = append ? try old?.attachmentFiles ?? [] : []
        for file in input["files"]?.arrayValue ?? [] {
            let uri = file["uri"]?.stringValue ?? ""
            let encoded = file["data"]?.stringValue ?? (uri.hasPrefix("data:") ? uri.split(separator: ",", maxSplits: 1).last.map(String.init) : nil)
            // File mentions are server paths, never duplicated as inline chips.
            guard file["mention"] == nil, file["source"]?["uri"]?.stringValue?.hasPrefix("file://") != true, !uri.hasPrefix("file://"), let encoded, let data = Data(base64Encoded: encoded) else { continue }
            let mime = file["mime"]?.stringValue ?? String(uri.dropFirst(5).prefix { $0 != ";" })
            attachments.append(try await drafts.storeAttachment(data, draftID: id, mime: mime,
                name: file["name"]?.stringValue ?? "Attachment"))
        }
        var options = old?.options ?? .init()
        if !append { options.shell = false }
        options.editingOutboxID = editingOutboxID
        options.agent = input["metadata"]?["agent"]?.stringValue ?? options.agent
        options.model = ComposerInput.restoreModel(input["metadata"]) ?? options.model
        let draft = try Draft(id: id, serverID: serverID, sessionID: sessionID, attributedText: text, attachments: attachments, options: options, comments: (append ? old?.comments ?? [] : []) + LineComment.restore(input.raw))
        await drafts.save(draft); try await drafts.flush()
        if let session = sessions[sessionID] {
            let composer = composer(sessionID: sessionID, directory: session.info.location.directory)
            try await composer.reload(); if !append { composer.markRestored() }; composer.requestFocus()
        }
        return draft
    }
    public func undo(_ sessionID: String, messageID: String? = nil) async throws {
        guard let session = sessions[sessionID], let transcript = session.transcript else { throw WriteStoreError.sessionUnavailable }
        let users = transcript.snapshot.filter { $0.type == "user" }
        let boundary = session.info.revert.flatMap { revert in users.firstIndex { $0.id == revert.messageID } } ?? users.count
        let target = messageID.flatMap { id in users.first { $0.id == id } } ?? users.prefix(boundary).last
        guard let target else { return }
        try await replacingDraft(sessionID) {
            if session.pending.contains(where: { $0.id == target.id }) {
                _ = try await writeRestoredInput(MessageFields(raw: target.raw), sessionID: sessionID, append: false)
                try await cancelPending(sessionID, itemID: target.id, restore: false)
            } else {
                _ = try await interrupt(sessionID, resume: false)
                try await waitForIdle(sessionID)
                try await stageRevert(sessionID, message: target.id)
                _ = try await writeRestoredInput(MessageFields(raw: target.raw), sessionID: sessionID, append: false)
            }
        }
    }

    public func forkFromMessage(_ sessionID: String, messageID: String) async throws -> SessionInfo {
        guard let message = sessions[sessionID]?.transcript?.messages[messageID]?.fields else { throw WriteStoreError.requestUnavailable }
        let info = try await fork(sessionID, before: messageID)
        try await restoreInput(message, sessionID: info.id, append: false)
        return info
    }
    public func restoreFailedPrompt(_ id: String) async throws {
        guard let entry = outboxEntries[id], entry.state == "failed", entry.operation == "prompt" else { throw WriteStoreError.requestUnavailable }
        let raw = try JSONDecoder().decode(JSONValue.self, from: entry.body)
        try await restoreInput(.init(raw: raw), sessionID: entry.sessionID, append: false, editingOutboxID: id)
    }
}

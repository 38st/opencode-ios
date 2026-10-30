import Foundation
import Observation
import OCFoundation
import OCModels
import OCPersistence
import OCNetworking

public typealias ComposerAttachment = DraftAttachment

public enum ComposerError: Error, LocalizedError, Equatable {
    case shellRestore, cannotQueue, childSession, storeUnavailable, operationInProgress, directoryDraftConflict
    public var errorDescription: String? {
        switch self {
        case .storeUnavailable: "This server is no longer available. Your draft has been kept."
        case .operationInProgress: "Wait for the current action to finish, then try again."
        case .directoryDraftConflict: "This project already has a saved draft. Choose which draft to use."
        case .shellRestore: "Leave shell mode before undoing a queued prompt"
        case .cannotQueue: "This prompt cannot be queued"
        case .childSession: "Subagent sessions are read only. Send prompts to the parent session."
        }
    }
}

/// This object's editing graph is deliberately separate from SessionModel and TranscriptModel.
@MainActor @Observable public final class ComposerModel {
    public private(set) var text = AttributedString()
    public private(set) var options = ComposerOptions()
    public private(set) var comments: [LineComment] = []
    public var focusedComment: LineComment?
    public private(set) var attachments: [ComposerAttachment] = []
    public private(set) var loaded = false
    public private(set) var busy = false
    public var error: String?
    public var confirmRevert = false
    public private(set) var focusRequest: UUID?
    public let sessionID: String?
    /// Changes only when the session moves to another directory; the draft stays keyed by the session.
    public private(set) var directory: String
    public private(set) var draftID = UUID().uuidString
    @ObservationIgnored private weak var store: ReadStore?
    private let serverID: String
    public private(set) var catalog: LocationCatalog
    @ObservationIgnored private var editRevision = 0
    @ObservationIgnored private var restoredRevision: Int?
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var sending: Task<Void, Never>?
    @ObservationIgnored private var pendingSend: (Bool, Bool, Delivery)?
    public init(store: ReadStore, sessionID: String?, directory: String) {
        self.store = store; self.serverID = store.serverID; self.sessionID = sessionID; self.directory = directory
        self.catalog = store.catalog(for: .init(directory: directory))
    }
    deinit { saving?.cancel(); sending?.cancel() }
    public var blank: Bool { String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty && (options.shell || comments.isEmpty) }
    public var session: SessionModel? { sessionID.flatMap { store?.sessions[$0] } }
    public var effectiveAgent: String { options.agent ?? session?.info.agent ?? "build" }
    public var effectiveModel: ModelRef? { options.model ?? session?.info.model ?? catalog.defaultModel.value.flatMap { $0 }.map { ModelRef(raw: .object(["id": .string($0.id), "providerID": .string($0.providerID)])) } }
    public var selectedModel: ModelInfo? { catalog.models.value?.first { $0.id == effectiveModel?.id && $0.providerID == effectiveModel?.providerID } }
    public var pendingSelection: Bool { session != nil && ((options.agent != nil && options.agent != session?.info.agent) || (options.model != nil && !ComposerPickers.sameSelection(options.model, session?.info.model))) }
    public func load() async {
        guard !loaded else { return }
        do {
            try await reload()
            if error == Self.loadFailed { error = nil }
        } catch { self.error = Self.loadFailed }
    }
    static let loadFailed = "Could not load your saved draft."
    public func reload() async throws {
        let store = try availableStore()
        await saving?.value
        if let draft = try await store.drafts?.load(serverID: store.serverID, sessionID: sessionID, directory: sessionID == nil ? directory : nil) {
            let next = try draft.attributedText, files = try draft.attachmentFiles
            if text != next || attachments != files || options != draft.options || comments != draft.comments { editRevision += 1 }
            text = next; attachments = files; comments = draft.comments; options = draft.options; draftID = draft.id
        } else { resetInput() }
        loaded = true
        if store.cacheLoaded, let id = options.editingOutboxID, store.outboxEntries[id]?.state != "failed" {
            cancelEditingOutbox()
        }
    }
    public func setText(_ value: AttributedString) {
        guard !busy, value != text else { return }
        editRevision += 1; clearSearchError()
        if !options.shell && String(value.characters) == "!" { options.shell = true; text = AttributedString() }
        else { text = value }
        save()
    }
    public func setOptions(_ value: ComposerOptions) { guard !busy, options != value else { return }; editRevision += 1; options = value; save() }
    public func shellMode(_ value: Bool) { var next = options; next.shell = value; setOptions(next) }
    public func cancelEditingOutbox() {
        guard options.editingOutboxID != nil else { return }
        options.editingOutboxID = nil; save()
    }
    public func selectAgent(_ agent: String) { var next = options; next.agent = agent; setOptions(next) }
    public func selectModel(_ model: ModelRef) { var next = options; next.model = model; setOptions(next) }
    public func requestFocus() { focusRequest = UUID() }
    /// A prompt the app wrote (a git quick action), sent with the composer's agent and model; the draft is untouched.
    @discardableResult public func sendAgentPrompt(_ text: String) async throws -> String {
        let store = try availableStore()
        guard let sessionID else { throw WriteStoreError.sessionUnavailable }
        guard session?.info.parentID == nil else { throw ComposerError.childSession }
        // While the agent works, the prompt waits for the turn to end rather than steering it mid-change.
        let delivery: Delivery = session?.status.isRunning == true ? .queue : .steer
        return try await store.sendPrompt(sessionID, input: PromptInput(text: text, delivery: delivery), prelude: WritePrelude(agent: options.agent, model: options.model))
    }
    func relocate(to directory: String) {
        guard sessionID != nil, directory != self.directory, let store else { return }
        self.directory = directory; catalog = store.catalog(for: .init(directory: directory))
    }
    func reconcileSelection(persist: Bool = true) {
        guard let session else { return }
        var changed = false
        if options.agent != nil && options.agent == session.info.agent { options.agent = nil; changed = true }
        if options.model != nil && ComposerPickers.sameSelection(options.model, session.info.model) { options.model = nil; changed = true }
        if changed && persist { save() }
    }
    public func addComment(_ comment: LineComment) { guard !busy else { return }; editRevision += 1; comments.append(comment); save() }
    public func updateComment(_ comment: LineComment) {
        guard !busy, let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        editRevision += 1; comments[index] = comment; save()
    }
    public func removeComment(_ id: String) { guard !busy else { return }; editRevision += 1; comments.removeAll { $0.id == id }; save() }
    public func focusComment(_ id: String) {
        focusedComment = comments.first { $0.id == id }
        guard let comment = focusedComment, let store, let sessionID else { return }
        let review = store.review(sessionID: sessionID, directory: directory)
        if comment.origin == "file" {
            review.selectTab("Files")
            let files = store.files(sessionID: sessionID, directory: directory)
            store.owned { await files.openLink(comment.file, present: true); files.selection = comment.selection }
        } else {
            let path = review.files.first { review.path($0.file)?.absolute == comment.file }?.file ?? comment.file
            review.selection = comment.selection
            review.choose(review.source, file: path, present: true)
        }
    }
    /// Inserts an @file mention at a UTF-16 offset, or at the end; returns the offset after it.
    @discardableResult public func mentionFile(_ path: String, atUTF16 offset: Int? = nil, focus: Bool = true) -> Int {
        var token = AttributedString("@" + (path.split(separator: "/").last.map(String.init) ?? path))
        token[MentionAttribute.self] = .init(kind: "file", value: ComposerInput.absolute(path, directory: directory))
        let caret = insert(token, atUTF16: offset ?? String(text.characters).utf16.count, spaced: true)
        if focus { requestFocus() }
        return caret
    }
    /// Inserts dropped text at a UTF-16 offset; returns the offset after it.
    @discardableResult public func insertText(_ value: String, atUTF16 offset: Int) -> Int {
        insert(AttributedString(value), atUTF16: offset, spaced: false)
    }
    /// The offset moves out of a mention and onto a character boundary, so neither a token nor an emoji is split.
    private func insert(_ value: AttributedString, atUTF16 offset: Int, spaced: Bool) -> Int {
        guard !busy, !value.characters.isEmpty else { return offset }
        let plain = String(text.characters)
        var target = min(max(0, offset), plain.utf16.count)
        for run in text.runs where run[MentionAttribute.self] != nil {
            let start = String(text[..<run.range.lowerBound].characters).utf16.count
            let end = start + String(text[run.range].characters).utf16.count
            if target > start && target < end { target = end }
        }
        var boundary = plain.startIndex, consumed = 0
        while boundary < plain.endIndex, consumed < target {
            consumed += plain[boundary].utf16.count; boundary = plain.index(after: boundary)
        }
        var inserted = value
        if spaced {
            if boundary > plain.startIndex, !plain[plain.index(before: boundary)].isWhitespace { inserted = AttributedString(" ") + inserted }
            inserted.append(AttributedString(" "))
        }
        var next = text
        guard let index = AttributedString.Index(boundary, within: next) else { return offset }
        next.insert(inserted, at: index)
        setText(next)
        return consumed + String(inserted.characters).utf16.count
    }
    public func removeAttachment(_ id: String) { guard !busy else { return }; editRevision += 1; attachments.removeAll { $0.id == id }; save() }
    public func addAttachment(_ data: Data, mime: String, name: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let drafts = try availableStore().drafts else { throw WriteStoreError.persistenceUnavailable }
            let prepared = try await AttachmentProcessing.prepare(data, mime: mime, name: name)
            let attachment = try await drafts.storeAttachment(prepared.data, draftID: draftID, mime: prepared.mime, name: prepared.name)
            editRevision += 1; attachments.append(attachment); save()
        } catch { self.error = WriteErrorMessage.message(error) }
    }
    /// An item dropped on the composer that it cannot attach: audio, video and other types the server drops.
    public func refuseDrop() { error = AttachmentError.unsupported.localizedDescription }
    public func attachmentURL(_ attachment: ComposerAttachment) async -> URL? { try? await store?.drafts?.attachmentURL(attachment, draftID: draftID) }
    private func snapshot() throws -> Draft {
        try Draft(id: draftID, serverID: serverID, sessionID: sessionID, directory: sessionID == nil ? directory : nil,
                  attributedText: text, attachments: attachments, options: options, comments: comments)
    }
    private func save() {
        guard loaded else { return }
        do {
            let draft = try snapshot(), previous = saving, drafts = try availableStore().drafts
            saving = Task { await previous?.value; await drafts?.save(draft) }
        } catch { self.error = "Could not save your draft." }
    }
    public func flush() async throws {
        guard let store else { throw ComposerError.storeUnavailable }
        await saving?.value; try await store.drafts?.flush()
    }
    public func submit(preference: Delivery, alternate: Bool = false, interrupt: Bool = false, confirmed: Bool = false,
                       start: (@MainActor (String, ModelRef?) async throws -> String)? = nil,
                       opened: @escaping @MainActor (String) -> Void = { _ in }) {
        guard !busy, loaded else { return }
        let store: ReadStore
        do { store = try availableStore() } catch { self.error = WriteErrorMessage.message(error); return }
        let action = ComposerDelivery.action(running: session?.status.isRunning == true, blank: blank, shell: options.shell,
                                             preference: preference, alternate: alternate, interrupt: interrupt)
        if action == .empty { return }
        if action == .unqueueable { error = "This prompt cannot be queued"; return }
        if session?.info.parentID != nil { error = ComposerError.childSession.localizedDescription; return }
        if session?.info.revert != nil && !confirmed && action != .stop {
            pendingSend = (alternate, interrupt, preference); confirmRevert = true; return
        }
        let activeRun = session?.executionID
        busy = true; error = nil
        sending = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.sending = nil }
            do {
                if action == .stop {
                    if let id = self.sessionID { _ = try await store.interrupt(id, resume: true) }
                    return
                }
                guard case .send(let delivery, let interrupt) = action else { return }
                try await self.flush()
                let draft = try self.snapshot(), agent = self.effectiveAgent, model = self.effectiveModel
                let id: String
                if let existing = self.sessionID { id = existing }
                else if let creating = self.options.creatingSessionID, store.sessions[creating] != nil { id = creating }
                else if let start { id = try await start(agent, model) }
                else { id = try await store.createSession(location: .init(directory: self.directory), agent: agent, model: model) }
                if self.sessionID == nil { self.options.creatingSessionID = id; self.save(); try await self.flush() }
                let sendsComments = !self.options.shell && self.serverCommand(String(self.text.characters)) == nil
                var input = ComposerInput.encode(self.text, directory: store.sessions[id]?.info.location.directory ?? self.directory,
                    files: try await store.drafts?.promptFiles(draft) ?? [], comments: sendsComments ? self.comments : [], agent: agent, model: model, delivery: delivery)
                let prelude = WritePrelude(agent: delivery == .steer ? agent : nil, model: delivery == .steer ? model : nil, commitRevert: confirmed)
                if self.options.shell {
                    _ = try await store.shell(id, command: input.text)
                } else if let command = self.serverCommand(input.text) {
                    if delivery == .steer {
                        if agent != store.sessions[id]?.info.agent { try await store.setAgent(id, agent: agent) }
                        if confirmed { try await store.commitRevert(id) }
                        if let model { try await store.setModel(id, model: model) }
                    }
                    input.text = command.arguments
                    try await store.command(id, name: command.name, input: input)
                } else {
                    let admitted: String
                    if let failed = self.options.editingOutboxID, store.outboxEntries[failed]?.state == "failed",
                       store.outboxEntries[failed]?.sessionID == id {
                        admitted = try await store.editAndResend(failed, input: input, prelude: prelude)
                    }
                    else { admitted = try await store.sendPrompt(id, input: input, prelude: prelude) }
                    if interrupt { store.interruptAfterAdmission(admitted, sessionID: id, executionID: activeRun) }
                }
                // Inline bytes now belong to the outbox. Never remove the draft earlier.
                if self.sessionID == nil, !sendsComments, !self.comments.isEmpty {
                    let target = store.composer(sessionID: id, directory: store.sessions[id]?.info.location.directory ?? self.directory)
                    await target.load()
                    guard target.loaded else { throw ComposerError.storeUnavailable }
                    for comment in self.comments where !target.comments.contains(where: { $0.id == comment.id }) { target.addComment(comment) }
                    try await target.flush()
                    self.comments = []
                }
                if let recovery = self.options.recoveringCreateID { try? await store.discardOutbox(recovery) }
                do { try await store.drafts?.delete(draft) }
                catch { self.error = "Your prompt is saved to send. Could not clean up the previous draft." }
                self.text = AttributedString(); self.attachments = []; self.options = .init(agent: agent, model: model); self.draftID = UUID().uuidString
                if sendsComments { self.comments = [] }
                self.reconcileSelection(persist: false)
                if !self.comments.isEmpty { self.save(); try await self.flush() }
                if self.sessionID == nil {
                    store.composer(sessionID: id, directory: store.sessions[id]?.info.location.directory ?? self.directory).requestFocus()
                }
                opened(id)
            } catch WriteStoreError.stagedRevertNeedsConfirmation {
                self.pendingSend = (alternate, interrupt, preference); self.confirmRevert = true
            } catch {
                let message = WriteErrorMessage.message(error)
                self.error = self.options.shell ? "Failed to send shell command. " + message : self.serverCommand(String(self.text.characters)) != nil ? "Failed to send command. " + message : message
            }
        }
    }
    public func confirmSend() {
        guard let (alternate, interrupt, preference) = pendingSend else { return }
        pendingSend = nil; confirmRevert = false
        submit(preference: preference, alternate: alternate, interrupt: interrupt, confirmed: true)
    }
    func availableStore() throws -> ReadStore {
        guard let store, !store.stopped else { throw ComposerError.storeUnavailable }
        return store
    }
    public func clearSearchError() { if error == "Could not search files." { error = nil } }
    var canReplaceWithoutConfirmation: Bool { text.characters.isEmpty && attachments.isEmpty && comments.isEmpty || restoredRevision == editRevision }
    var hasDraftContent: Bool { !text.characters.isEmpty || !attachments.isEmpty || !comments.isEmpty || options != ComposerOptions() }
    func markRestored() { restoredRevision = editRevision }
    func lockEditing() throws { guard !busy else { throw ComposerError.operationInProgress }; busy = true }
    func unlockEditing() { busy = false }
    func resetInput() {
        text = AttributedString(); attachments = []; comments = []; options = .init(); draftID = UUID().uuidString
        editRevision += 1; restoredRevision = nil
    }
    private func serverCommand(_ text: String) -> (name: String, arguments: String)? {
        guard text.hasPrefix("/") else { return nil }
        let parts = text.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = parts.first.map(String.init), catalog.commands.value?.arrayValue?.contains(where: { $0["name"]?.stringValue == name }) == true else { return nil }
        return (name, parts.count > 1 ? String(parts[1]) : "")
    }
}

extension ReadStore {
    public func composer(sessionID: String? = nil, directory: String) -> ComposerModel {
        let key = sessionID.map { "session:" + $0 } ?? "directory:" + directory
        if let existing = composers[key] { return existing }
        let value = ComposerModel(store: self, sessionID: sessionID, directory: directory); composers[key] = value; return value
    }
    public func flushComposers() async throws {
        for composer in composers.values { try await composer.flush() }
    }
    func interruptAfterAdmission(_ id: String, sessionID: String, executionID: String?) {
        guard let executionID else { return }
        owned { [weak self] in
            guard let self else { return }
            var delay = 100
            while let entry = self.outboxEntries[id] {
                guard entry.state == "pending", self.sessions[sessionID]?.executionID == executionID else { return }
                try await self.clock.sleep(.milliseconds(delay)); try Task.checkCancellation()
                delay = min(delay * 2, 5_000)
            }
            guard self.sessions[sessionID]?.executionID == executionID,
                  self.admittedInputs.contains(id) || self.consumedInputs.contains(id) else { return }
            _ = try await self.interrupt(sessionID, resume: true)
        }
    }
}

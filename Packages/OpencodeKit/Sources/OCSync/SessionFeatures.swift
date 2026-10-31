import Foundation
import OCFoundation
import OCModels
import OCNetworking

/// A `/btw` question and its answer, shown in a card that never enters the history.
public struct SideQuestion: Equatable, Sendable {
    public enum State: Equatable, Sendable { case asking, answered(String), failed(String) }
    public let question: String
    public var state: State
}

/// A place a session can move to: one of its project's worktrees, the project checkout, or a new worktree.
public struct MoveTarget: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case checkout, worktree, newWorktree }
    public let kind: Kind
    public let directory: String
    public let branch: String?
    public var id: String { kind == .newWorktree ? "new" : directory }
    public var title: String {
        switch kind {
        case .newWorktree: localized("New worktree")
        case .checkout: localized("Project checkout")
        case .worktree: (directory as NSString).lastPathComponent
        }
    }
}

extension ReadStore {
    // MARK: Moving a session

    public func moveState(_ sessionID: String) -> SessionMove? {
        guard let session = sessions[sessionID] else { return nil }
        return SessionMove.state(requested: requestedMoves[sessionID], pending: session.pending, location: session.info.location.directory)
    }
    /// The project's worktrees and checkout, without the session's own directory, newest worktree first.
    public func moveTargets(_ sessionID: String) async throws -> [MoveTarget] {
        guard let session = sessions[sessionID] else { throw WriteStoreError.sessionUnavailable }
        let current = session.info.location.directory
        let list = try await writeAPI().send(ComposerEndpoints.worktrees(projectID: session.info.projectID)).values
        let targets = list.filter { $0.directory != current }.map {
            MoveTarget(kind: $0["strategy"] == nil ? .checkout : .worktree, directory: $0.directory, branch: $0.branch)
        }.sorted { ($0.kind == .checkout ? 0 : 1, $0.directory) < ($1.kind == .checkout ? 0 : 1, $1.directory) }
        return [MoveTarget(kind: .newWorktree, directory: "", branch: nil)] + targets
    }
    /// Asks the server to move the session; it moves at the next delivery boundary (`session.moved`).
    public func moveSession(_ sessionID: String, to target: MoveTarget, delivery: Delivery) async throws {
        guard let session = sessions[sessionID] else { throw WriteStoreError.sessionUnavailable }
        try await waitForCreate(sessionID)
        var directory = target.directory
        requestedMoves[sessionID] = .pending(directory: directory, delivery: delivery)
        do {
            if target.kind == .newWorktree {
                directory = try await writeAPI().send(AdminEndpoints.createWorktree(projectID: session.info.projectID)).directory
                requestedMoves[sessionID] = .pending(directory: directory, delivery: delivery)
            }
            try await writeAPI().send(SessionEndpoints.move(sessionID, directory: directory, delivery: delivery))
            if sessions[sessionID]?.info.location.directory == directory { requestedMoves[sessionID] = .applied(directory: directory) }
        } catch {
            var message = WriteErrorMessage.message(error)
            if target.kind == .newWorktree && !directory.isEmpty { message = localized("\(message) The new worktree was kept: \(directory)", comment: "First %@ is the error message, second a directory path") }
            requestedMoves[sessionID] = .failed(directory: directory, message: message)
            throw error
        }
    }
    public func dismissMove(_ sessionID: String) { requestedMoves.removeValue(forKey: sessionID) }
    /// `session.moved`: the draft, read state and Live Activity are keyed by the session and stay; the models that
    /// read files follow the new directory.
    func sessionMoved(_ sessionID: String) {
        guard let directory = sessions[sessionID]?.info.location.directory else { return }
        if case .pending? = requestedMoves[sessionID] { requestedMoves[sessionID] = .applied(directory: directory) }
        composers["session:" + sessionID]?.relocate(to: directory)
        // Open screens take the new models on their next render; the old ones stop reading the old directory now.
        if let review = reviews.removeValue(forKey: sessionID) { owned { await review.stop() } }
        fileModels.removeValue(forKey: sessionID)?.stop()
        turnDiffs = turnDiffs.filter { !$0.key.hasPrefix(sessionID + ":") }
    }

    // MARK: Export and statistics

    public func exportSession(_ sessionID: String, sanitize: Bool) async throws -> JSONValue {
        try await writeAPI().send(SessionEndpoints.export(sessionID, sanitize: sanitize))
    }
    /// The export as a file to share: the server's JSON, or Markdown rendered here.
    public func exportFile(_ sessionID: String, format: ExportFormat, sanitize: Bool) async throws -> URL {
        let transfer: JSONValue
        do { transfer = try await exportSession(sessionID, sanitize: sanitize) }
        catch { throw WriteErrorMessage.isCancellation(error) ? error : UserFacingError(error) }
        let data: Data
        switch format {
        case .json:
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            data = try encoder.encode(transfer)
        case .markdown: data = Data(TranscriptMarkdown.render(transfer).utf8)
        }
        let title = sanitize ? nil : sessions[sessionID]?.info.title
        return try SessionExportFile.write(data, title: title, sessionID: sessionID, extension: format == .json ? "json" : "md")
    }
    public func stats(_ range: StatsRange, projectID: String?) async throws -> SessionStats {
        try await writeAPI().send(SessionEndpoints.stats(range, projectID: projectID)).data
    }

    // MARK: Side questions

    /// The instructions the desktop app sends with every side question (`gui-plugins/src/btw/model.ts`).
    static let sideQuestionInstructions = [
        "The user is asking a quick side question about the conversation so far.",
        "Answer directly and concisely in markdown from what you already know.",
        "Do not call any tools and do not take any actions.",
    ].joined(separator: "\n")

    /// One question per session: a new one replaces the card and cancels the previous request.
    public func askSideQuestion(_ sessionID: String, question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !stopped else { return }
        sideQuestionTasks[sessionID]?.cancel()
        sideQuestions[sessionID] = SideQuestion(question: question, state: .asking)
        sideQuestionTasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            let state: SideQuestion.State
            do {
                try await self.waitForCreate(sessionID)
                let text = try await self.writeAPI().send(SessionEndpoints.generate(sessionID, prompt: Self.sideQuestionInstructions + "\n\n" + question)).data.text
                state = .answered(text)
            } catch {
                if Task.isCancelled || WriteErrorMessage.isCancellation(error) { return }
                state = .failed(WriteErrorMessage.message(error))
            }
            guard !Task.isCancelled, self.sideQuestions[sessionID]?.question == question else { return }
            self.sideQuestions[sessionID]?.state = state
            self.sideQuestionTasks.removeValue(forKey: sessionID)
        }
    }
    public func dismissSideQuestion(_ sessionID: String) {
        sideQuestionTasks.removeValue(forKey: sessionID)?.cancel()
        sideQuestions.removeValue(forKey: sessionID)
    }

    // MARK: Prompt history

    /// This session's prompts, then those of the project's other loaded sessions.
    public func promptHistory(_ sessionID: String?, directory: String) -> [PromptHistory.Entry] {
        func prompts(_ session: SessionModel) -> [PromptHistory.Entry] {
            guard let transcript = session.transcript else { return [] }
            return transcript.order.compactMap { id in
                guard let fields = transcript.messages[id]?.fields, fields.type == "user" else { return nil }
                return .init(text: fields.text, sessionID: session.id, created: fields.time.created)
            }
        }
        let current = sessionID.flatMap { sessions[$0] }
        let project = current?.info.projectID ?? sessions.values.first { $0.info.location.directory == directory }?.info.projectID
        let others = sessions.values.filter { $0.id != sessionID && $0.info.parentID == nil && project != nil && $0.info.projectID == project }
        return PromptHistory.entries(session: current.map(prompts) ?? [], project: others.flatMap(prompts))
    }

    // MARK: Hands-free replies

    /// Waits until the turn that delivered prompt `id` goes idle and returns its reply as plain text, without
    /// Markdown; nil when the turn produced none or failed, or after 15 minutes.
    public func reply(to id: String, sessionID: String, timeout: Duration = .seconds(900)) async throws -> String? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(400))
            guard let session = sessions[sessionID] else { return nil }
            guard let transcript = session.transcript, let start = transcript.order.firstIndex(of: id),
                  transcript.messages[id]?.acknowledged == true else { continue }
            let after = transcript.order[(start + 1)...].compactMap { transcript.messages[$0] }
            guard let idle = after.firstIndex(where: { $0.fields.type == "idle" }) else { continue }
            let text = after[..<idle].filter { $0.fields.type == "assistant" }.flatMap { $0.items.filter { $0.fields.type == "text" }.map(\.text) }
                .joined(separator: "\n\n")
            let plain = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))).map { String($0.characters) } ?? text
            return plain.isEmpty ? nil : plain
        }
        return nil
    }
}

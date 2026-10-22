import Foundation
import OCModels
import OCPersistence

public enum DirectoryDraftChoice: Sendable { case current, saved }

extension ReadStore {
    /// Keeps the current input with the project selection. A conflict is resolved
    /// before mutating either draft; choosing the saved draft preserves the old one.
    public func moveDirectoryDraft(from source: String, to destination: String, keeping choice: DirectoryDraftChoice? = nil) async throws {
        guard source != destination else { return }
        guard let drafts else { throw WriteStoreError.persistenceUnavailable }
        let current = composer(directory: source), target = composer(directory: destination)
        if !current.loaded { try await current.reload() }
        if !target.loaded { try await target.reload() }
        try current.lockEditing(); defer { current.unlockEditing() }
        try target.lockEditing(); defer { target.unlockEditing() }
        try await current.flush(); try await target.flush()
        guard current.hasDraftContent else { return }
        if target.hasDraftContent {
            guard let choice else { throw ComposerError.directoryDraftConflict }
            if choice == .saved { return }
        }
        guard var draft = try await drafts.load(serverID: serverID, directory: source) else { return }
        let previous = try await drafts.load(serverID: serverID, directory: destination)
        var text = try draft.attributedText
        for run in text.runs {
            guard var mention = run[MentionAttribute.self], ["file", "reference"].contains(mention.kind) else { continue }
            mention.value = ComposerInput.absolute(mention.value, directory: source)
            text[run.range][MentionAttribute.self] = mention
        }
        draft.text = try JSONEncoder().encode(text, configuration: DraftAttributes.self)
        draft.directory = destination
        draft.updatedAt = Date()
        // A partially admitted create belongs to its original directory.
        draft.options.creatingSessionID = nil
        try await drafts.relocate(draft, replacing: previous)
        current.resetInput()
        try await target.reload()
    }
}

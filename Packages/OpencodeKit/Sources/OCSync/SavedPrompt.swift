import Foundation
import OCFoundation
import OCModels
import OCPersistence

public struct SavedPrompt: Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let text: String
    public let state: String
    public let operation: String
}
extension ReadStore {
    public var savedPrompts: [SavedPrompt] {
        outboxEntries.values.sorted { $0.createdAt < $1.createdAt }.map { entry in
            let input = try? JSONDecoder().decode(PromptInput.self, from: entry.body)
            return SavedPrompt(id: entry.id, sessionID: entry.sessionID, text: input?.text ?? "", state: entry.state, operation: entry.operation)
        }
    }
    public func editSavedPrompt(_ id: String, text: String) async throws {
        guard let entry = outboxEntries[id], entry.operation == "prompt" else { throw WriteStoreError.requestUnavailable }
        var input = try JSONDecoder().decode(PromptInput.self, from: entry.body)
        input.text = text
        var prelude = try JSONDecoder().decode(WritePrelude.self, from: entry.prelude)
        if prelude.commitRevert {
            let original = try JSONDecoder().decode(JSONValue.self, from: entry.prelude)
            let current = sessions[entry.sessionID]?.info.revert?.messageID
            if let current, current != original["revertMessageID"]?.stringValue { throw WriteStoreError.stagedRevertNeedsConfirmation }
            prelude.commitRevert = current != nil
        }
        _ = try await editAndResend(id, input: input, prelude: prelude)
    }
}

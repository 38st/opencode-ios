import Foundation
import OCModels

extension ReadStore {
    public func resolveDraftReplacement(_ replace: Bool) {
        let reply = draftReplacementReply
        draftReplacementReply = nil; replacingDraftSessionID = nil
        reply?.resume(returning: replace)
    }
    func replacingDraft<Value>(_ sessionID: String, operation: () async throws -> Value) async throws -> Value {
        guard let session = sessions[sessionID] else { throw WriteStoreError.sessionUnavailable }
        let composer = composer(sessionID: sessionID, directory: session.info.location.directory)
        if !composer.loaded { try await composer.reload() }
        try composer.lockEditing()
        defer { composer.unlockEditing() }
        try await composer.flush()
        if !composer.canReplaceWithoutConfirmation {
            guard draftReplacementReply == nil else { throw ComposerError.operationInProgress }
            let confirmed = await withCheckedContinuation { reply in
                draftReplacementReply = reply; replacingDraftSessionID = sessionID
            }
            guard confirmed else { throw CancellationError() }
        }
        try Task.checkCancellation()
        return try await operation()
    }
}

import Foundation
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence

public enum WriteErrorMessage {
    nonisolated public static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if case APIError.cancelled = error { return true }
        return (error as? URLError)?.code == .cancelled
    }
    nonisolated public static func message(_ error: any Error) -> String {
        switch error {
        case WriteStoreError.persistenceUnavailable: return "Your prompt could not be saved on this device. Try again."
        case WriteStoreError.sessionUnavailable: return "This session is no longer available. Your draft has been kept."
        case WriteStoreError.requestUnavailable: return "This input is no longer available. It may already have been handled."
        case WriteStoreError.stagedRevertNeedsConfirmation: return "Confirm discarding the reverted messages before sending."
        case APIError.unauthorized: return ConnectionFailure.unauthorized.message
        case APIError.serviceStarting: return "The server is starting. Try again when it is ready."
        case APIError.server(_, let status, let body):
            if let message = body["message"]?.stringValue ?? body["error"]?["message"]?.stringValue ?? body["data"]?["message"]?.stringValue,
               !message.isEmpty { return message }
            if status == 409 { return "This input conflicts with an existing request. Edit it and send again." }
            if status == 404 { return "This item is no longer available on the server." }
            return "The server could not complete this action (HTTP \(status)). Try again."
        case APIError.notOpencode: return ConnectionFailure.notOpencode.message
        case APIError.transport(let failure): return networkMessage(failure)
        case APIError.decoding: return "The server returned an unreadable response. Try again."
        case APIError.refused(let failure): return failure.message
        case let failure as ConnectionFailure: return failure.message
        case let failure as URLError: return networkMessage(failure)
        case DraftError.attachmentTooLarge: return "This file is larger than the 20 MiB attachment limit."
        case DraftError.invalidPath: return "This attachment could not be opened. Remove it and attach it again."
        case OutboxError.changedAdmission: return "This saved prompt has changed. Use Edit and resend to send a new copy."
        default:
            if isCancellation(error) { return "The action was cancelled." }
            return (error as? any LocalizedError)?.errorDescription ?? "Could not complete this action. Please try again."
        }
    }
    nonisolated private static func networkMessage(_ error: URLError) -> String {
        error.code == .timedOut ? "The server did not respond in time. Check your connection and try again."
            : "The server could not be reached. Check your connection and try again."
    }
}

// The OAuth and command sign-in attempts of packages/core/src/integration.ts at v2.2.1, as the desktop drives them
// (packages/app/src/providers/connect/controller.ts): start, show the URL and instructions, then either take the
// pasted code (`mode: code`) or poll until the server finishes (`mode: auto`, device codes and login commands).
import Foundation
import Observation
import OCFoundation
import OCModels
import OCNetworking

@MainActor @Observable public final class ConnectFlow: Identifiable {
    public enum Phase: Equatable, Sendable {
        case starting
        /// Open `url`, then paste the code it shows.
        case code(OAuthAttempt)
        /// Finish on the computer running opencode (or any browser for a device code); the server reports back.
        case waiting(OAuthAttempt)
        /// The login command runs on the server; `message` is its latest output or instructions.
        case command(message: String?)
        case completing
        case complete
        case failed(String)
        case expired
        case cancelled
        public var isFinished: Bool {
            switch self { case .complete, .failed, .expired, .cancelled: true; default: false }
        }
    }
    public enum Kind: Sendable { case oauth, command }
    public let id = UUID()
    public let integrationID: String
    public let integrationName: String
    public let method: IntegrationMethod
    public let kind: Kind
    public private(set) var phase: Phase = .starting
    @ObservationIgnored private let directory: String
    @ObservationIgnored private let client: @MainActor () async throws -> APIClient
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var attemptID: String?
    @ObservationIgnored private var expires: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let finished: @MainActor (Phase) -> Void

    init(integration: IntegrationInfo, method: IntegrationMethod, directory: String, answers: JSONValue?,
         client: @escaping @MainActor () async throws -> APIClient, clock: any Clock<Duration>, now: @escaping @Sendable () -> Date,
         interval: Duration = .seconds(2), finished: @escaping @MainActor (Phase) -> Void) {
        integrationID = integration.id; integrationName = integration.name; self.method = method
        kind = method.type == "command" ? .command : .oauth
        self.directory = directory; self.client = client; self.clock = clock; self.now = now; self.interval = interval
        self.finished = finished
        task = Task { [weak self] in await self?.start(answers: answers) }
    }
    deinit { task?.cancel() }

    /// `mode: code`: sends the pasted code. A wrong code fails the attempt, as on the desktop.
    public func submit(code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .code = phase, let attemptID, !code.isEmpty else { return }
        phase = .completing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let api = try await client()
                try await api.send(AdminEndpoints.completeOAuth(integrationID, attempt: attemptID, directory: directory, code: code))
                await poll()
            } catch { finish(failure(error)) }
        }
    }
    /// Stops polling while the app is in the background; the attempt stays open on the server.
    func pause() { if !phase.isFinished { task?.cancel(); task = nil } }
    func resume() {
        guard task == nil, attemptID != nil else { return }
        switch phase {
        case .waiting, .command, .completing: task = Task { [weak self] in await self?.poll() }
        default: break
        }
    }
    /// Cancels on the server too (idempotent there), so a loopback listener does not linger.
    public func cancel() {
        guard !phase.isFinished else { return }
        task?.cancel(); task = nil
        let attemptID = attemptID, kind = kind, integrationID = integrationID, directory = directory, client = client
        finish(.cancelled)
        guard let attemptID else { return }
        Task {
            guard let api = try? await client() else { return }
            _ = try? await api.send(kind == .oauth ? AdminEndpoints.cancelOAuth(integrationID, attempt: attemptID, directory: directory)
                                                    : AdminEndpoints.cancelCommand(integrationID, attempt: attemptID, directory: directory))
        }
    }

    private func start(answers: JSONValue?) async {
        do {
            let api = try await client()
            guard let methodID = method.methodID else { throw APIError.decoding("Sign-in method has no ID") }
            switch kind {
            case .oauth:
                let attempt = try await api.send(AdminEndpoints.startOAuth(integrationID, directory: directory, methodID: methodID, answers: answers)).data
                attemptID = attempt.attemptID; expires = attempt.expires.map { Date(timeIntervalSince1970: $0 / 1000) }
                OCLog.sync.info("Started sign-in \(attempt.mode)")
                if attempt.mode == "code" { phase = .code(attempt); return }
                phase = .waiting(attempt)
            case .command:
                let attempt = try await api.send(AdminEndpoints.startCommand(integrationID, directory: directory, methodID: methodID)).data
                attemptID = attempt.attemptID; expires = attempt.expires.map { Date(timeIntervalSince1970: $0 / 1000) }
                phase = .command(message: nil)
            }
            await poll()
        } catch { finish(failure(error)) }
    }
    private func poll() async {
        guard let attemptID else { return }
        do {
            let api = try await client()
            while !Task.isCancelled {
                let status = try await api.send(kind == .oauth ? AdminEndpoints.oauthStatus(integrationID, attempt: attemptID, directory: directory)
                                                               : AdminEndpoints.commandStatus(integrationID, attempt: attemptID, directory: directory))
                switch status {
                case .complete: finish(.complete); return
                case .failed(let message): finish(.failed(message)); return
                case .expired: finish(.expired); return
                case .pending(let message):
                    if kind == .command { phase = .command(message: message) }
                case .unknown: break
                }
                if let expires, now() >= expires { finish(.expired); return }
                // A code attempt waits for the pasted code before polling.
                if case .code = phase { return }
                try await clock.sleep(for: interval)
            }
        } catch {
            guard !WriteErrorMessage.isCancellation(error) else { return }
            // A dropped connection or a restarting server is retried until the attempt expires.
            if Self.isTransient(error), !Task.isCancelled, expires.map({ now() < $0 }) ?? true {
                try? await clock.sleep(for: interval)
                if !Task.isCancelled { await poll() }
                return
            }
            finish(failure(error))
        }
    }
    static func isTransient(_ error: any Error) -> Bool {
        switch error {
        case APIError.transport, APIError.serviceStarting: true
        default: false
        }
    }
    private func finish(_ phase: Phase) {
        guard !self.phase.isFinished else { return }
        self.phase = phase
        finished(phase)
    }
    private func failure(_ error: any Error) -> Phase {
        WriteErrorMessage.isCancellation(error) ? .cancelled : .failed(WriteErrorMessage.message(error))
    }
}

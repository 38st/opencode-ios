import Foundation
import Observation

/// What the recognizer heard so far. `isFinal` text never changes again; volatile text is replaced by the next result.
public struct VoiceTranscript: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public init(text: String, isFinal: Bool) { self.text = text; self.isFinal = isFinal }
}

public enum VoiceAuthorization: Equatable, Sendable { case granted, denied(String) }

/// The device's recognizer. Audio never leaves it: only the transcript text does, as the prompt the user sends.
@MainActor public protocol SpeechRecognizing: AnyObject {
    /// Asks for microphone and speech access the first time; later calls return the stored answer.
    func authorize() async -> VoiceAuthorization
    /// - Parameter contextualStrings: words to favour (file names, symbols, agent names).
    func start(contextualStrings: [String]) async throws -> AsyncThrowingStream<VoiceTranscript, any Error>
    /// Stops listening; the stream finishes after the last final result.
    func stop() async
}

@MainActor public protocol SpeechSpeaking: AnyObject {
    func speak(_ text: String) async
    func stopSpeaking()
}

/// Dictation and hands-free conversation. Nothing is sent without a visible transcript: hands-free waits for a
/// pause, then counts down, and the user can cancel at any point.
@MainActor @Observable public final class VoiceModel {
    public enum Mode: Equatable, Sendable { case dictation, handsFree }
    public enum State: Equatable, Sendable {
        case idle, starting
        case denied(String)
        case listening
        /// Hands-free: sends when the count reaches zero.
        case countdown(Int)
        case waitingForReply
        case speaking
        case failed(String)
    }
    public private(set) var state = State.idle
    public private(set) var mode = Mode.dictation
    /// Final text so far, then the volatile tail.
    public private(set) var final = ""
    public private(set) var volatile = ""
    public var transcript: String { [final, volatile].filter { !$0.isEmpty }.joined(separator: final.isEmpty || volatile.isEmpty ? "" : " ") }
    public var active: Bool { state != .idle && !isTerminal }
    private var isTerminal: Bool { if case .denied = state { return true }; if case .failed = state { return true }; return false }

    @ObservationIgnored private let recognizer: any SpeechRecognizing
    @ObservationIgnored private let speaker: any SpeechSpeaking
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private let countdownSeconds: Int
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var turn: Task<Void, Never>?
    @ObservationIgnored private var stopping: Task<Void, Never>?
    @ObservationIgnored private var contextualStrings: [String] = []
    /// Hands-free sends the transcript and waits for the reply text to read aloud (nil: nothing to read).
    @ObservationIgnored public var send: @MainActor (String) async -> String? = { _ in nil }

    public init(recognizer: any SpeechRecognizing, speaker: any SpeechSpeaking, clock: any Clock<Duration> = ContinuousClock(),
                pause: Duration = .seconds(2), countdown: Int = 3) {
        self.recognizer = recognizer; self.speaker = speaker; self.clock = clock; self.pause = pause; self.countdownSeconds = countdown
    }
    deinit { listening?.cancel(); timer?.cancel(); turn?.cancel(); stopping?.cancel() }

    public func start(_ mode: Mode, contextualStrings: [String] = []) {
        guard !active else { return }
        self.mode = mode; final = ""; volatile = ""; state = .starting; self.contextualStrings = contextualStrings
        listening = Task { [weak self] in
            guard let self else { return }
            switch await self.recognizer.authorize() {
            case .denied(let reason): self.state = .denied(reason); return
            case .granted: break
            }
            guard !Task.isCancelled, self.state == .starting else { return }
            await self.listen()
        }
    }
    private func listen() async {
        do {
            await stopping?.value
            let stream = try await recognizer.start(contextualStrings: contextualStrings)
            state = .listening
            for try await result in stream {
                if result.isFinal { final = [final, result.text].filter { !$0.isEmpty }.joined(separator: " "); volatile = "" }
                else { volatile = result.text }
                if mode == .handsFree, case .listening = state { schedulePause() }
                else if mode == .handsFree, case .countdown = state { schedulePause() }
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            timer?.cancel()
            // The microphone stays off after a failure.
            await recognizer.stop()
            state = .failed("Voice input stopped: " + error.localizedDescription)
        }
    }
    /// Silence after speech starts the countdown; more speech restarts the wait.
    private func schedulePause() {
        timer?.cancel()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state = .listening
        timer = Task { [weak self, clock, pause, countdownSeconds] in
            do {
                try await clock.sleep(for: pause)
                for remaining in stride(from: countdownSeconds, to: 0, by: -1) {
                    self?.state = .countdown(remaining)
                    try await clock.sleep(for: .seconds(1))
                }
                self?.sendTurn()
            } catch {}
        }
    }
    /// Cancels a hands-free countdown and keeps listening; the transcript stays for editing.
    public func cancelCountdown() {
        guard case .countdown = state else { return }
        timer?.cancel(); state = .listening
    }
    /// Sends now (hands-free), without waiting for the countdown.
    public func sendNow() { if mode == .handsFree, !transcript.isEmpty { timer?.cancel(); sendTurn() } }
    private func sendTurn() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { state = .listening; return }
        listening?.cancel(); listening = nil
        state = .waitingForReply
        turn = Task { [weak self] in
            guard let self else { return }
            await self.recognizer.stop()
            self.final = ""; self.volatile = ""
            let reply = await self.send(text)
            guard !Task.isCancelled, self.state == .waitingForReply else { return }
            if let reply, !reply.isEmpty {
                self.state = .speaking
                await self.speaker.speak(reply)
                guard !Task.isCancelled, self.state == .speaking else { return }
            }
            self.state = .starting
            await self.listen()
        }
    }
    /// Dictation: stops and returns the transcript for the composer. Hands-free: ends the conversation.
    @discardableResult public func stop() -> String {
        let text = transcript
        listening?.cancel(); timer?.cancel(); turn?.cancel()
        listening = nil; timer = nil; turn = nil
        speaker.stopSpeaking()
        stopping = Task { [recognizer] in await recognizer.stop() }
        state = .idle; final = ""; volatile = ""
        return text
    }
    public func dismissError() {
        guard isTerminal else { return }
        state = .idle
        stopping = Task { [recognizer] in await recognizer.stop() }
    }
}

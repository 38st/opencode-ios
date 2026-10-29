// The PTY socket's lifecycle, ported from the reference terminal (packages/gui-plugins/src/terminal/terminal.tsx at
// v2.2.0), with the gap measured by the server's buffer rules (core/src/pty.ts): a connection from `cursor` replays
// `buffer.slice(max(0, cursor - bufferStart))`, then a control frame carries the cursor after the replay.
import Foundation

/// Output a resumed screen cannot show, in UTF-16 code units where the server's frames say how much.
public enum TerminalGap: Equatable, Sendable {
    /// Resuming from the saved cursor, the server's retained buffer began `units` later.
    case lost(units: Int)
    /// On a first connection the server had already dropped `units` from the start of the output.
    case trimmed(units: Int)
    /// The server's output position is behind ours, so it cannot say what differs.
    case positionReset
    /// A screen was restored without a cursor, so the connection showed only output from now on (cursor -1).
    case skipped
    /// The process exited while no socket was attached; an exited PTY cannot replay its output.
    case exitedWhileAway
}

public enum TerminalStatus: Equatable, Sendable { case running, exited(code: Int?), gone, unknown }

/// A reducer: each event returns the effects the session performs, so every transition is testable without a socket.
public struct TerminalLink: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, connecting, replaying, live, waiting, checking, exited(code: Int?), gone, suspended }
    public enum Effect: Equatable, Sendable {
        case connect(seek: Int)
        case close
        case checkStatus
        case wait(Duration)
        case feed(String)
        /// Output the server kept, fed at once; the terminal's replies to queries in it belong to the past.
        case replay(String)
        /// Clears the screen before a replay that does not continue it.
        case reset
        case gap(TerminalGap)
        /// Sends the terminal's size: after each (re)connection, so a size another client set is corrected.
        case pushSize
        /// Saves the cursor with the screen; only emitted where the two agree.
        case persist
        /// The PTY no longer exists: drop what is saved for it.
        case forget
    }

    public private(set) var phase: Phase = .idle
    /// The output position the screen shows, in UTF-16 code units.
    public private(set) var cursor: Int?
    public private(set) var seek = 0
    public private(set) var tries = 0
    private var replay: [String] = []
    private var replayUnits = 0
    private var restoredWithoutCursor = false
    /// The last socket ended normally while live, so the process ended with every byte received.
    private var endedLive = false

    public init() {}

    /// The reference client's backoff: 250 ms doubling to at most 4 s.
    public static func delay(tries: Int) -> Duration { .milliseconds(min(250 << min(tries, 4), 4_000)) }

    /// `cursor -1` tails from now; it is only used for a restored screen without a cursor, as the reference does.
    public mutating func start(cursor saved: Int?, restoredScreen: Bool) -> [Effect] {
        guard phase == .idle else { return [] }
        cursor = saved.flatMap { $0 >= 0 ? $0 : nil }
        restoredWithoutCursor = restoredScreen && cursor == nil
        seek = cursor ?? (restoredScreen ? -1 : 0)
        return open()
    }
    public mutating func opened() -> [Effect] {
        guard phase == .connecting else { return [] }
        tries = 0; phase = .replaying; replay = []; replayUnits = 0; endedLive = false
        return [.pushSize]
    }
    /// A text frame. Replayed output waits for the control frame, so a socket lost mid-replay leaves the screen and the
    /// cursor as they were.
    public mutating func text(_ text: String) -> [Effect] {
        switch phase {
        case .replaying:
            replay.append(text); replayUnits += text.utf16.count
            return []
        case .live:
            cursor = (cursor ?? 0) + text.utf16.count; seek = cursor ?? seek
            return [.feed(text)]
        default: return []
        }
    }
    public mutating func control(cursor end: Int) -> [Effect] {
        guard phase == .replaying, end >= 0 else { return [] }
        let from = seek, output = replay.joined(), units = replayUnits
        let restored = restoredWithoutCursor
        replay = []; replayUnits = 0; restoredWithoutCursor = false
        phase = .live; cursor = end; seek = end
        let feed: [Effect] = output.isEmpty ? [] : [.replay(output)]
        if from == -1 { return (restored ? [.gap(.skipped)] : []) + feed + [.persist] }
        let missing = end - from - units
        if missing == 0 { return feed + [.persist] }
        let gap: TerminalGap = missing < 0 ? .positionReset : from == 0 ? .trimmed(units: missing) : .lost(units: missing)
        return [.reset] + feed + [.gap(gap), .persist]
    }
    /// The socket ended with a close `code` (nil when it failed without one), or its upgrade answered `httpStatus`.
    public mutating func closed(code: Int?, httpStatus: Int? = nil) -> [Effect] {
        guard [.connecting, .replaying, .live].contains(phase) else { return [] }
        endedLive = phase == .live && code == 1000
        replay = []; replayUnits = 0
        if httpStatus == 404 { phase = .gone; return [.forget] }
        // 1000 is an exit, a removal or a stopping server, so look before reconnecting; anything else (4404 among them)
        // waits first, as the reference does.
        if code == 1000 { phase = .checking; return [.checkStatus] }
        phase = .waiting
        return [.wait(Self.delay(tries: tries))]
    }
    public mutating func waited() -> [Effect] {
        guard phase == .waiting else { return [] }
        phase = .checking
        return [.checkStatus]
    }
    /// Skips a pending wait, for example when the server's connection is back.
    public mutating func retryNow() -> [Effect] { phase == .waiting ? waited() : [] }
    public mutating func status(_ status: TerminalStatus) -> [Effect] {
        guard phase == .checking else { return [] }
        switch status {
        case .gone:
            phase = .gone
            return [.forget]
        case .exited(let code):
            phase = .exited(code: code)
            return endedLive ? [.persist] : [.gap(.exitedWhileAway), .persist]
        case .running, .unknown:
            tries += 1
            return open()
        }
    }
    /// The list already shows the PTY as exited: there is nothing to connect to, and an exited PTY cannot replay
    /// what it printed after the saved cursor.
    public mutating func exited(code: Int?, cursor saved: Int?) -> [Effect] {
        guard phase == .idle else { return [] }
        cursor = saved.flatMap { $0 >= 0 ? $0 : nil }; phase = .exited(code: code)
        return [.gap(.exitedWhileAway)]
    }
    /// The PTY was closed or deleted: stop and drop what is saved for it.
    public mutating func removed() -> [Effect] {
        guard phase != .gone else { return [] }
        phase = .gone; replay = []; replayUnits = 0
        return [.close, .forget]
    }
    /// Backgrounding or hiding: save, then close without looking at the PTY.
    public mutating func suspend() -> [Effect] {
        switch phase {
        case .idle, .exited, .gone, .suspended: return []
        default:
            phase = .suspended; replay = []; replayUnits = 0
            return [.persist, .close]
        }
    }
    public mutating func resume() -> [Effect] {
        guard phase == .suspended else { return [] }
        tries = 0
        return open()
    }
    private mutating func open() -> [Effect] { phase = .connecting; return [.connect(seek: seek)] }
}

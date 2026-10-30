import Foundation
import Observation
import OCFoundation
import OCModels

public enum RunStatus: Equatable, Sendable {
    case idle, running(since: Double), retrying(attempt: Double, at: Double)
    public var isRunning: Bool { self != .idle }
}
public enum PendingStatus: Equatable, Sendable { case queued, stranded, steering, starting }
public enum FormOwner: Hashable, Sendable { case session(String), global(location: String) }
@MainActor @Observable public final class SessionModel: Identifiable {
    public var id: String { info.id }
    public var info: SessionInfo
    /// When the running turn began (`session.execution.started`), for the working timer; steps do not reset it.
    public var turnStartedAt: Double?
    public var status: RunStatus = .idle {
        didSet {
            if !status.isRunning { executionID = nil; turnStartedAt = nil }
            else if executionID == nil { executionID = UUID().uuidString }
        }
    }
    /// Stable across steps and retries, invalidated across an unobserved stream gap.
    public internal(set) var executionID: String?
    public var pending: [InboxItem] = []
    public var transcript: TranscriptModel?
    public var attention = 0
    public var lastSeq: Int?
    @ObservationIgnored var seenSequences: Set<Int> = []
    @ObservationIgnored var pendingSequences: [String: Int] = [:]
    @ObservationIgnored var rowSequences: [String: Int] = [:]
    public init(info: SessionInfo, transcript: TranscriptModel? = nil) { self.info = info; self.transcript = transcript }
    public var unread: Bool { (info.time.idle ?? 0) > (info.time.viewed ?? 0) }
    public func resetSequence() { lastSeq = nil; seenSequences = [] }
    public func pendingStatus(_ id: String) -> PendingStatus? {
        guard let item = pending.first(where: { $0.id == id && $0.type == "user" }) else { return nil }
        if item.delivery == .queue { return .queued }
        let messages = transcript?.snapshot ?? []
        let boundary = messages.lastIndex { $0.type == "idle" }
        if !status.isRunning {
            return boundary.map { item.fields.time.created <= messages[$0].time.created } == true ? .stranded : .starting
        }
        let after = boundary.map { Array(messages.dropFirst($0 + 1)) } ?? messages
        return after.contains { row in row.type == "user" && !pending.contains(where: { $0.id == row.id }) } ? .steering : .starting
    }
}

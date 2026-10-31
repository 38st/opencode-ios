import Foundation
import Observation
import OCModels

public struct ServerCapabilities: Sendable, Equatable {
    public var pairing: Bool
    public var persistentPty: Bool
    public static var pairingRequirement: String { localized("Pairing needs opencode \(ServerInfo.minimumVersion) or later.") }
    public init(info: ServerInfo? = nil) {
        pairing = info?.supportsPairing ?? false
        persistentPty = info?.capabilities.persistentPty ?? false
    }
}

public struct ResyncRecord: Sendable {
    public let reason: ResyncReason
    public let date: Date
    public let succeeded: Bool
}

/// The read projection supplies session and transcript refresh work here, after the server info refresh.
@MainActor public protocol ResyncExtension {
    func resync(reason: ResyncReason) async throws
}

@MainActor public protocol ServerEventSink {
    func receive(_ batch: EventBatch)
}

@MainActor @Observable public final class PendingServerEventSink: ServerEventSink {
    public private(set) var batchCount = 0
    public private(set) var eventCount = 0
    public init() {}
    public func receive(_ batch: EventBatch) {
        batchCount += 1; eventCount += batch.events.count
    }
}

@MainActor @Observable public final class ResyncCoordinator {
    public private(set) var records: [ResyncRecord] = []
    public private(set) var isRunning = false
    @ObservationIgnored private var pending: [ResyncReason] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let date: @Sendable () -> Date
    @ObservationIgnored private let refresh: @MainActor (ResyncReason) async throws -> Void
    @ObservationIgnored private let extensionWork: (any ResyncExtension)?
    public init(date: @escaping @Sendable () -> Date = { Date() }, extensionWork: (any ResyncExtension)? = nil,
                refresh: @escaping @MainActor (ResyncReason) async throws -> Void) {
        self.date = date; self.refresh = refresh; self.extensionWork = extensionWork
    }
    deinit { task?.cancel() }
    public func enqueue(_ reason: ResyncReason) {
        pending.append(reason)
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !self.pending.isEmpty, !Task.isCancelled {
                let reason = self.pending.removeFirst()
                self.isRunning = true
                var succeeded = false
                do {
                    try await self.refresh(reason)
                    try Task.checkCancellation()
                    try await self.extensionWork?.resync(reason: reason)
                    succeeded = true
                } catch {}
                guard !Task.isCancelled else { break }
                self.records.append(.init(reason: reason, date: self.date(), succeeded: succeeded))
                if self.records.count > 50 { self.records.removeFirst(self.records.count - 50) }
            }
            self?.isRunning = false; self?.task = nil
        }
    }
    public func stop() async {
        pending = []
        task?.cancel()
        await task?.value
        task = nil; isRunning = false
    }
}

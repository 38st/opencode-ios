import Foundation
import OCNetworking
import OCPushCore

@MainActor public final class PresenceCoordinator {
    private let clock: NetworkClock
    private let send: @MainActor @Sendable (Bool) async -> Void
    private var heartbeat: Task<Void, Never>?
    public init(clock: NetworkClock = .init(), send: @escaping @MainActor @Sendable (Bool) async -> Void) { self.clock = clock; self.send = send }
    deinit { heartbeat?.cancel() }
    public func setForeground(_ foreground: Bool) async {
        heartbeat?.cancel(); heartbeat = nil
        await send(foreground)
        guard foreground else { return }
        heartbeat = Task { [clock, send] in
            while !Task.isCancelled {
                do { try await clock.sleep(.seconds(PushContract.shared.presence.heartbeatSeconds)); try Task.checkCancellation() }
                catch { return }
                await send(true)
            }
        }
    }
    public func stop() { heartbeat?.cancel(); heartbeat = nil }
}

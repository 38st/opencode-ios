import Synchronization
import OCModels

/// Pull-based AsyncStream storage bounds the *consumer's* backlog as well as the producer's batch.
/// A slow MainActor never blocks reads from URLSession.
final class ConnectionMailbox: Sendable {
    private struct Storage: Sendable {
        var queue: [ConnectionOutput] = []
        var eventCount = 0
        var waiter: CheckedContinuation<ConnectionOutput?, Never>?
        var finished = false
    }
    private let storage = Mutex(Storage())
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func next() async -> ConnectionOutput? {
        await withCheckedContinuation { waiter in
            storage.withLock { state in
                if !state.queue.isEmpty {
                    let value = state.queue.removeFirst()
                    if case .events(let batch) = value { state.eventCount -= batch.events.count }
                    waiter.resume(returning: value)
                } else if state.finished { waiter.resume(returning: nil) }
                else { state.waiter = waiter }
            }
        }
    }
    /// Returns false when pending event batches were discarded.
    @discardableResult func yield(_ output: ConnectionOutput) -> Bool {
        storage.withLock { state in
            guard !state.finished else { return true }
            if let waiter = state.waiter {
                state.waiter = nil; waiter.resume(returning: output); return true
            }
            if case .events(let batch) = output {
                if state.eventCount + batch.events.count > limit {
                    state.queue.removeAll { if case .events = $0 { true } else { false } }
                    state.eventCount = 0
                    if !state.queue.contains(.resyncNeeded(.backlogOverflow)) { state.queue.append(.resyncNeeded(.backlogOverflow)) }
                    return false
                }
                state.eventCount += batch.events.count
            }
            if case .state = output {
                let states = state.queue.indices.filter { if case .state = state.queue[$0] { true } else { false } }
                if states.count >= 50, let oldest = states.first { state.queue.remove(at: oldest) }
            }
            state.queue.append(output)
            return true
        }
    }
    func discardEvents() {
        storage.withLock { state in
            state.queue.removeAll { if case .events = $0 { true } else { false } }
            state.eventCount = 0
        }
    }
    func finish() {
        storage.withLock { state in
            state.finished = true; state.queue = []; state.eventCount = 0
            state.waiter?.resume(returning: nil); state.waiter = nil
        }
    }
}

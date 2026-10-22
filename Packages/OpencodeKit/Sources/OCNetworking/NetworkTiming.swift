import Foundation

/// A monotonic clock and wall clock with independently injectable implementations.
public struct NetworkClock: Sendable {
    public var now: @Sendable () -> ContinuousClock.Instant
    public var date: @Sendable () -> Date
    public var sleep: @Sendable (Duration) async throws -> Void
    public init(now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
                date: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.now = now; self.date = date; self.sleep = sleep
    }
}

public struct ReconnectBackoff: Sendable {
    private var failures = 0
    private var random: @Sendable () -> Double
    public init(random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) { self.random = random }
    public mutating func reset() { failures = 0 }
    public mutating func next() -> Duration {
        let ceiling = min(30.0, pow(2, Double(min(failures, 5))))
        failures += 1
        return .seconds(ceiling * min(1, max(0, random())))
    }
}

func withTimeout<T: Sendable>(_ duration: Duration, clock: NetworkClock,
                              operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await clock.sleep(duration); throw URLError(.timedOut) }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw CancellationError() }
        return value
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

import Foundation
import Testing
import Clocks
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync

struct SyncTime: Sendable {
    let test = TestClock<Duration>()
    let origin = ContinuousClock.now
    var clock: NetworkClock {
        NetworkClock(now: { origin.advanced(by: TestClock<Duration>.Instant().duration(to: test.now)) },
                     date: { Date(timeIntervalSince1970: 1_790_000_000 + Double(TestClock<Duration>.Instant().duration(to: test.now).components.seconds)) },
                     sleep: { try await test.sleep(for: $0) })
    }
}

actor FakeConnection: ConnectionControlling {
    nonisolated let output: AsyncStream<ConnectionOutput>
    let continuation: AsyncStream<ConnectionOutput>.Continuation
    var starts: [Bool] = []
    var reconnects: [(ReconnectReason, Bool)] = []
    var stops = 0
    var value = ConnectionSnapshot()
    init() { (output, continuation) = AsyncStream.makeStream() }
    func start(rerace: Bool) { starts.append(rerace) }
    func stop() { stops += 1; continuation.yield(.state(.suspended)) }
    func forceReconnect(_ reason: ReconnectReason, rerace: Bool) { reconnects.append((reason, rerace)) }
    func snapshot() -> ConnectionSnapshot { value }
    func configure(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String]) {}
    func setNetworkPath(_ path: NetworkPathStatus) {}
    func updateEndpoints(_ endpoints: [EndpointRecord]) {}
    func allowLocalNetwork() {}
    func setSnapshot(_ value: ConnectionSnapshot) { self.value = value }
    func emit(_ output: ConnectionOutput) { continuation.yield(output) }
}

actor MemoryRecords: ServerRecordStore {
    var records: [ServerRecord] = []
    func load() -> [ServerRecord] { records }
    func save(_ records: [ServerRecord]) { self.records = records }
}

@MainActor final class FakeBackground: BackgroundTaskProviding {
    var starts = 0
    var ends: [Int] = []
    var expiration: (@MainActor @Sendable () -> Void)?
    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Int {
        starts += 1; self.expiration = expiration; return starts
    }
    func end(_ identifier: Int) { ends.append(identifier) }
}

actor RefreshCounter {
    var count = 0
    func refresh() -> ServerInfo { count += 1; return ServerInfo(version: "2.0.32") }
}

let syncEndpoint = EndpointRecord(url: URL(string: "http://192.168.1.10:4096")!, kind: .lan)
func syncRecord() -> ServerRecord { ServerRecord(name: "Studio", endpoints: [syncEndpoint]) }

@MainActor func settle(_ predicate: @MainActor () async -> Bool) async {
    for _ in 0..<10_000 {
        if await predicate() { return }
        await Task.yield()
    }
    Issue.record("Expected asynchronous store update")
}

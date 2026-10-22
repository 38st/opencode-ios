import Foundation
import Clocks
import Synchronization
import Testing
import OCModels
@testable import OCNetworking

private func makeConnection(_ transport: FakeTransport, time: TestTime, kind: EndpointKind = .lan,
                            resolver: FakeResolver = FakeResolver(), path: FakePathMonitor? = nil,
                            backlog: Int = 20_000) -> ServerConnection {
    ServerConnection(endpoints: [.init(url: testURL, kind: kind)], credential: .password("fake"), transport: transport,
                     resolver: resolver, clock: time.clock, random: { 1 }, pathMonitor: path, backlogLimit: backlog)
}

extension NetworkingTests {
@Test func seededFullJitterIsBoundedAndResettable() {
    func generator() -> @Sendable () -> Double {
        let state = Mutex<UInt64>(0x12345678)
        return { state.withLock { value in
            value = value &* 6364136223846793005 &+ 1442695040888963407
            return Double(value >> 11) / Double(UInt64(1) << 53)
        } }
    }
    var a = ReconnectBackoff(random: generator()), b = ReconnectBackoff(random: generator())
    for step in 0..<50 {
        let delay = a.next()
        #expect(delay == b.next())
        #expect(delay >= .zero && delay <= .seconds(min(30, pow(2, Double(min(step, 5))))))
    }
    a.reset()
    #expect(a.next() <= .seconds(1))
}

@Test func firstFrameDeadlinesOnLANAndRemote() async {
    for (kind, seconds) in [(EndpointKind.lan, 3), (.https, 8)] {
        let time = TestTime(), transport = FakeTransport()
        let connection = makeConnection(transport, time: time, kind: kind)
        await connection.start()
        await eventually { transport.streamCount == 1 }
        // Comments prove bytes arrived, but cannot satisfy the first-frame contract.
        transport.emit(Data(": heartbeat\n\n".utf8))
        await time.test.advance(by: .seconds(seconds))
        await eventually { await isWaiting(connection, .firstFrameTimeout) }
        #expect(transport.cancellations == 1)
        await connection.stop()
    }
}

@Test func firstFrameMustBeConnected() async {
    let time = TestTime(), transport = FakeTransport()
    let connection = makeConnection(transport, time: time)
    await connection.start()
    await eventually { transport.streamCount == 1 }
    transport.emit(Data("data: {\"id\":\"x\",\"type\":\"future.event\"}\n\n".utf8))
    await eventually { await isWaiting(connection, .invalidFirstFrame) }
    await connection.stop()
}

@Test func heartbeatWatchdogRecoveryAndRepeatedResync() async {
    let time = TestTime(), transport = FakeTransport()
    let connection = makeConnection(transport, time: time)
    let signals = Mutex(0)
    let consumer = Task {
        for await value in connection.output {
            if case .resyncNeeded(.serverConnected) = value { signals.withLock { $0 += 1 } }
        }
    }
    await connection.start()
    await eventually { transport.streamCount == 1 }
    transport.emit(connectedFrame)
    await eventually { await isConnected(connection) }
    for _ in 0..<3 {
        await time.test.advance(by: .seconds(15))
        let before = await connection.lastActivity
        transport.emit(Data(": heartbeat\n\n".utf8))
        await eventually { await connection.lastActivity != before }
    }
    #expect(await isConnected(connection))
    await time.test.advance(by: .seconds(45))
    await eventually { await isWaiting(connection, .watchdog) }
    await time.test.advance(by: .seconds(1))
    await eventually { transport.streamCount == 2 }
    transport.emit(connectedFrame)
    await eventually { await isConnected(connection) }
    transport.emit(connectedFrame)
    await eventually { signals.withLock { $0 } == 3 }
    await connection.stop(); consumer.cancel(); await consumer.value
}

@Test func unauthorizedStopsWithoutRetry() async {
    let time = TestTime(), transport = FakeTransport(streamStatus: 401)
    let connection = makeConnection(transport, time: time)
    await connection.start()
    await eventually { await connection.state == .unauthorized }
    await time.test.advance(by: .seconds(120))
    await connection.forceReconnect(.userRequested)
    #expect(transport.streamCount == 1)
    await connection.stop()
}

@Test func serviceStartingHonorsRetryAfter() async {
    let time = TestTime(), transport = FakeTransport(streamStatus: 503, streamHeaders: ["Retry-After": "7"])
    let connection = makeConnection(transport, time: time)
    await connection.start()
    await eventually { await connection.state == .serviceStarting(.seconds(7)) }
    await time.test.advance(by: .seconds(6))
    #expect(transport.streamCount == 1)
    await time.test.advance(by: .seconds(1))
    await eventually { transport.streamCount == 2 }
    await connection.stop()
}

@Test func overflowCloseReconnectsAndForcedReconnectSkipsBackoff() async {
    let time = TestTime(), transport = FakeTransport()
    let resolver = FakeResolver()
    let connection = makeConnection(transport, time: time, resolver: resolver)
    await connection.start()
    await eventually { transport.streamCount == 1 }
    transport.emit(connectedFrame)
    await eventually { await isConnected(connection) }
    transport.close() // Server's 4096-frame overflow fails/closes the stream without a special SSE frame.
    await eventually { await isWaiting(connection, .streamClosed) }
    await connection.forceReconnect(.userRequested)
    await eventually { transport.streamCount == 2 }
    #expect(await resolver.count == 2)
    #expect(time.test.now == .init())
    await connection.stop()
    #expect(await connection.state == .suspended)
    await connection.start()
    await eventually { transport.streamCount == 3 }
    await connection.stop()
}

@Test func networkPathChangesDebounceAndRerace() async {
    let time = TestTime(), transport = FakeTransport(), path = FakePathMonitor(), resolver = FakeResolver()
    let connection = makeConnection(transport, time: time, resolver: resolver, path: path)
    await connection.start()
    path.continuation.yield(.init(interfaces: ["en0"]))
    await eventually { await connection.networkPath?.interfaces == ["en0"] }
    await eventually { transport.streamCount == 1 }
    transport.emit(connectedFrame)
    await eventually { await isConnected(connection) }
    path.continuation.yield(.init(isExpensive: true, interfaces: ["pdp_ip0"]))
    await eventually { await connection.networkPath?.isExpensive == true }
    await time.test.advance(by: .milliseconds(499))
    #expect(await resolver.count == 1)
    await time.test.advance(by: .milliseconds(1))
    await eventually { await resolver.count == 2 }
    await connection.stop()
}

@Test func slowConsumerBacklogIsBoundedAndRequestsResync() async {
    let time = TestTime(), transport = FakeTransport()
    let connection = makeConnection(transport, time: time, backlog: 3)
    await connection.start()
    await eventually { transport.streamCount == 1 }
    transport.emit(connectedFrame)
    await eventually { await isConnected(connection) }
    let frame = "data: {\"id\":\"x\",\"type\":\"session.text.delta\",\"data\":{}}\n\n"
    transport.emit(Data(String(repeating: frame, count: 10).utf8))
    await time.test.advance(by: .milliseconds(16))
    var iterator = connection.output.makeAsyncIterator()
    var overflow = false
    for _ in 0..<6 {
        if case .resyncNeeded(.backlogOverflow) = await iterator.next() { overflow = true; break }
    }
    #expect(overflow)
    await connection.stop()
}

@Test func queuedConsumerBacklogAlsoHasACap() async {
    let mailbox = ConnectionMailbox(limit: 3)
    let event = ServerEvent.decode(Data(#"{"id":"x","type":"future","data":{}}"#.utf8))
    #expect(mailbox.yield(.events(.init(events: [event, event]))))
    #expect(!mailbox.yield(.events(.init(events: [event, event]))))
    #expect(await mailbox.next() == .resyncNeeded(.backlogOverflow))
    mailbox.finish()
}

@Test func sustainedConnectionResetsBackoffAndHistoryIsBounded() async {
    let time = TestTime(), transport = FakeTransport()
    let connection = makeConnection(transport, time: time)
    await connection.start()
    await eventually { transport.streamCount == 1 }
    transport.close()
    await eventually { await isWaiting(connection, .streamClosed) }
    await time.test.advance(by: .seconds(1))
    await eventually { transport.streamCount == 2 }
    transport.close()
    await eventually { await isWaiting(connection, .streamClosed) }
    if case .waiting(let attempt, let retryAt, _) = await connection.state {
        #expect(attempt == 2)
        #expect(time.clock.now().duration(to: retryAt) == .seconds(2))
    }
    await time.test.advance(by: .seconds(2))
    await eventually { transport.streamCount == 3 }
    transport.emit(connectedFrame)
    await eventually { await isConnected(connection) }
    await time.test.advance(by: .seconds(10))
    transport.close()
    await eventually { await isWaiting(connection, .streamClosed) }
    if case .waiting(let attempt, let retryAt, _) = await connection.state {
        #expect(attempt == 1)
        #expect(time.clock.now().duration(to: retryAt) == .seconds(1))
    }
    for _ in 4...30 {
        let before = transport.streamCount
        await connection.forceReconnect(.userRequested)
        await eventually { transport.streamCount > before }
    }
    #expect(await connection.transitions.count == 50)
    await connection.stop()
}

}

extension NetworkingTests {
    @Test func foregroundCanReuseResolutionButFailureAlwaysReraces() async {
        let time = TestTime(), transport = FakeTransport(), resolver = FakeResolver()
        let connection = makeConnection(transport, time: time, resolver: resolver)
        await connection.start()
        await eventually { transport.streamCount == 1 }
        transport.emit(connectedFrame)
        await eventually { await isConnected(connection) }
        await connection.stop()
        await connection.start(rerace: false)
        await eventually { transport.streamCount == 2 }
        #expect(await resolver.count == 1)
        transport.close()
        await eventually { await isWaiting(connection, .streamClosed) }
        await time.test.advance(by: .seconds(1))
        await eventually { transport.streamCount == 3 }
        #expect(await resolver.count == 2)
        await connection.stop()
    }

    @Test func unrelatedServerStopsWithActionableState() async {
        let time = TestTime(), transport = FakeTransport()
        let endpoint = EndpointRecord(url: testURL, kind: .lan)
        let resolver = FakeResolver(result: .init(selected: nil, diagnoses: [endpoint.id: .failure(.notOpencode)]))
        let connection = makeConnection(transport, time: time, resolver: resolver)
        await connection.start()
        await eventually { await connection.state == .incompatible(.notOpencode) }
        #expect(transport.streamCount == 0)
        await connection.stop()
    }

    @Test func discoveredLANDoesNotBypassLocalNetworkGate() async {
        let time = TestTime(), transport = FakeTransport()
        let local = EndpointRecord(url: testURL, kind: .lan, source: .discovered)
        let connection = ServerConnection(endpoints: [local], credential: nil, transport: transport,
            clock: time.clock, random: { 1 }, pathMonitor: nil, allowsLocalNetwork: false)
        await connection.start()
        await eventually { await isWaiting(connection, .transport) }
        #expect(transport.requests.isEmpty && transport.streamCount == 0)
        await connection.allowLocalNetwork()
        await connection.forceReconnect(.userRequested)
        await eventually { transport.streamCount == 1 }
        #expect(transport.requests.count == 1)
        await connection.stop()
    }
}

import Foundation
import Darwin
import Synchronization
import Testing
import OCFoundation
import OCModels
import OCSecurity
import OCNetworking

private let environment = ProcessInfo.processInfo.environment
private let liveEnabled = ["OPENCODE_LIVE_URL", "OPENCODE_LIVE_PASSWORD", "OPENCODE_LIVE_PID",
                           "OPENCODE_LIVE_V1_URL", "OPENCODE_LIVE_V1_PASSWORD"].allSatisfy { environment[$0] != nil }

private func waitUntil(_ seconds: Double, _ predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw LiveFailure.deadline
}
private enum LiveFailure: Error { case deadline, probe, signal, pairing }
private func connected(_ connection: ServerConnection) async -> Bool {
    if case .connected = await connection.state { true } else { false }
}

@Suite(.serialized) struct LiveContracts {}

extension LiveContracts {
@Test(.enabled(if: liveEnabled, "Requires sandbox environment supplied by Tools/contract"), .timeLimit(.minutes(4)))
func sandboxNetworkingContract() async throws {
    let address = try #require(environment["OPENCODE_LIVE_URL"])
    let url = try #require(URL(string: address))
    let password = try #require(environment["OPENCODE_LIVE_PASSWORD"])
    let processID = try #require(environment["OPENCODE_LIVE_PID"])
    let pid = try #require(Int32(processID))
    let credential = Credential.password(password)
    let clock = ServerClock()
    let probe = ServerProbe(serverClock: clock)
    guard case .v2(let info) = await probe.probe(endpoint: url, credential: credential) else { throw LiveFailure.probe }
    #expect(info.version == environment["OPENCODE_LIVE_VERSION"])
    #expect(abs(clock.offset) < 5)
    // Only signal the loopback sandbox process whose identity the harness and /api/info agree on.
    guard EndpointPolicy.isLoopback(url), pid > 1, info.pid == Int(pid) else { throw LiveFailure.signal }
    print("PASS Swift V2 probe \(info.version), clock offset \(clock.offset)s")

    struct Code: Decodable, Sendable { let code: String }
    let client = APIClient(baseURL: url, credential: credential)
    let code = try await client.send(Endpoint<Code>.json(method: .post, path: "/api/pair"))
    let link = try PairingParser.parse(url.absoluteString + "/auth/connect/" + code.code)
    let paired = try await PairingService().redeem(link)
    guard let token = PairingToken.credential(paired.token) else { throw LiveFailure.pairing }
    guard case .v2 = await probe.probe(endpoint: paired.preferredURL, credential: token) else { throw LiveFailure.pairing }
    #expect(!token.expiresWithinFiveDays())
    do { _ = try await PairingService().redeem(link); Issue.record("Single-use code was redeemed twice") }
    catch PairingError.expired {}
    print("PASS Swift pairing link redemption, token expiry and authenticated probe")

    let connection = ServerConnection(endpoints: paired.server.endpoints, credential: token, pathMonitor: nil)
    let resyncs = Mutex(0)
    let reader = Task {
        for await item in connection.output {
            if case .resyncNeeded(.serverConnected) = item { resyncs.withLock { $0 += 1 } }
        }
    }
    do {
        let start = ContinuousClock.now
        await connection.start()
        try await waitUntil(3) { await connected(connection) }
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .seconds(3))
        print("PASS Swift URLSession first server.connected in \(elapsed); frame is below 512 bytes")
        try await Task.sleep(for: .seconds(40))
        #expect(await connected(connection))
        let beforeStop = await connection.transitions
        #expect(!beforeStop.contains { if case .waiting = $0.state { true } else { false } })
        print("PASS Swift heartbeat comments keep the connection healthy for 40 seconds")

        guard kill(pid, SIGSTOP) == 0 else { throw LiveFailure.signal }
        do {
            defer { _ = kill(pid, SIGCONT) }
            try await Task.sleep(for: .seconds(60))
            let stalled = await connection.transitions.contains { transition in
                if case .waiting(_, _, .watchdog) = transition.state { true } else { false }
            }
            #expect(stalled)
        }
        try await waitUntil(45) { await connected(connection) }
        #expect(resyncs.withLock { $0 } >= 2)
        print("PASS Swift SIGSTOP 60 seconds: watchdog fired; SIGCONT: recovered")
        for transition in await connection.transitions { print("Swift transition: \(transition.state)") }
        await connection.stop()
        reader.cancel(); await reader.value
    } catch {
        _ = kill(pid, SIGCONT)
        await connection.stop(); reader.cancel(); await reader.value
        throw error
    }

    let wrong = ServerConnection(endpoints: paired.server.endpoints, credential: .password("intentionally-wrong"), pathMonitor: nil)
    await wrong.start()
    try await waitUntil(5) { await wrong.state == .unauthorized }
    let count = await wrong.transitions.count
    try await Task.sleep(for: .seconds(2))
    #expect(await wrong.state == .unauthorized)
    #expect(await wrong.transitions.count == count)
    await wrong.stop()
    print("PASS Swift wrong password stops without retrying")

    let v1Address = try #require(environment["OPENCODE_LIVE_V1_URL"])
    let v1URL = try #require(URL(string: v1Address))
    let v1Password = try #require(environment["OPENCODE_LIVE_V1_PASSWORD"])
    #expect(await probe.probe(endpoint: v1URL, credential: .password(v1Password)) == .v1("1.19.3"))
    print("PASS Swift V1 detection")
}

}

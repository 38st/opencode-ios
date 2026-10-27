import Foundation
import Testing
import OCFoundation
@testable import OCNetworking

/// Accepts the request and never answers, like a relay that holds the connection open.
private actor StalledTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
    nonisolated func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

private struct FailingTransport: HTTPTransport {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> HTTPResponse { throw URLError(code) }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

struct PushRelayClientTests {
    @Test func stalledRelayFailsAsUnreachableWithinTheResourceDeadline() async throws {
        let transport = StalledTransport()
        let deadlines = Deadlines()
        let clock = NetworkClock(sleep: { duration in await deadlines.record(duration); try await Task.sleep(for: .milliseconds(20)) })
        let client = PushRelayClient(url: try #require(URL(string: "http://127.0.0.1:9")), transport: transport, clock: clock)
        let started = ContinuousClock.now
        await #expect(throws: PushRelayError.unreachable) {
            _ = try await client.request(.post, path: "/v1/devices", body: .object(["apnsToken": .string("token")]))
        }
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(await deadlines.values == [.seconds(30)])
        let request = try #require(await transport.requests.first)
        #expect(request.timeoutInterval == 15)
    }
    @Test func connectionFailuresAreUnreachable() async throws {
        for code in [URLError.Code.timedOut, .cannotConnectToHost, .networkConnectionLost] {
            let client = PushRelayClient(url: try #require(URL(string: "http://127.0.0.1:9")), transport: FailingTransport(code: code))
            await #expect(throws: PushRelayError.unreachable) { _ = try await client.request(.get, path: "/v1/health") }
        }
        let client = PushRelayClient(url: try #require(URL(string: "http://127.0.0.1:9")), transport: FailingTransport(code: .badServerResponse))
        await #expect(throws: URLError.self) { _ = try await client.request(.get, path: "/v1/health") }
    }
}

private actor Deadlines {
    private(set) var values: [Duration] = []
    func record(_ value: Duration) { values.append(value) }
}

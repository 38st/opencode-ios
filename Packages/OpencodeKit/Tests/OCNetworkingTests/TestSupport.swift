import Foundation
import Synchronization
import Testing
import Clocks
import OCFoundation
import OCModels
@testable import OCNetworking

let testURL = URL(string: "http://127.0.0.1:4096")!
let connectedFrame = Data("data: {\"id\":\"evt_test\",\"type\":\"server.connected\",\"data\":{}}\n\n".utf8)
let testInfo = ServerInfo(version: "2.0.32")

func response(_ status: Int = 200, type: String = "application/json", headers: [String: String] = [:],
              body: Data = Data(), url: URL = testURL) -> HTTPResponse {
    HTTPResponse(data: body, response: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: headers.merging(["Content-Type": type]) { old, _ in old })!)
}

final class FakeTransport: HTTPTransport, Sendable {
    struct State: Sendable {
        var requests: [URLRequest] = []
        var streams: [AsyncThrowingStream<TransportChunk, any Error>.Continuation] = []
        var streamRequests: [URLRequest] = []
        var cancellations = 0
    }
    let state = Mutex(State())
    let handler: @Sendable (URLRequest, Int) async throws -> HTTPResponse
    let streamStatus: Int
    let streamHeaders: [String: String]
    init(streamStatus: Int = 200, streamHeaders: [String: String] = [:],
         handler: @escaping @Sendable (URLRequest, Int) async throws -> HTTPResponse = { _, _ in
             response(body: try JSONEncoder().encode(testInfo))
         }) {
        self.handler = handler; self.streamStatus = streamStatus; self.streamHeaders = streamHeaders
    }
    var requests: [URLRequest] { state.withLock { $0.requests } }
    var streamCount: Int { state.withLock { $0.streams.count } }
    var cancellations: Int { state.withLock { $0.cancellations } }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let index = state.withLock { state in state.requests.append(request); return state.requests.count - 1 }
        return try await handler(request, index)
    }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.state.withLock { $0.cancellations += 1 } }
            continuation.yield(.response(response(streamStatus, type: "text/event-stream", headers: streamHeaders).response))
            state.withLock { $0.streams.append(continuation); $0.streamRequests.append(request) }
        }
    }
    func emit(_ data: Data, index: Int? = nil) {
        let continuation = state.withLock { $0.streams[index ?? ($0.streams.count - 1)] }
        continuation.yield(.bytes(data))
    }
    func close(index: Int? = nil) {
        let continuation = state.withLock { $0.streams[index ?? ($0.streams.count - 1)] }
        continuation.finish()
    }
}

actor FakeResolver: EndpointResolving {
    var count = 0
    let result: EndpointResolution?
    init(result: EndpointResolution? = nil) { self.result = result }
    func resolve(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String],
                 localNetworkDenied: Bool) -> EndpointResolution {
        count += 1
        return result ?? EndpointResolution(selected: endpoints.first, diagnoses: [:])
    }
}

final class FakePathMonitor: NetworkPathMonitoring, Sendable {
    let stream: AsyncStream<NetworkPathStatus>
    let continuation: AsyncStream<NetworkPathStatus>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func updates() -> AsyncStream<NetworkPathStatus> { stream }
}

struct TestTime: Sendable {
    let test = TestClock<Duration>()
    let origin = ContinuousClock.now
    var clock: NetworkClock {
        let start = TestClock<Duration>.Instant()
        return NetworkClock(now: { origin.advanced(by: start.duration(to: test.now)) },
                            date: { Date(timeIntervalSince1970: 1_790_000_000 + start.duration(to: test.now).seconds) },
                            sleep: { try await test.sleep(for: $0) })
    }
}

func eventually(_ message: String = "condition", _ predicate: () async -> Bool) async {
    for _ in 0..<10_000 {
        if await predicate() { return }
        await Task.yield()
    }
    Issue.record("Did not reach \(message)")
}

func isConnected(_ connection: ServerConnection) async -> Bool {
    if case .connected = await connection.state { true } else { false }
}
func isWaiting(_ connection: ServerConnection, _ failure: ConnectionFailure) async -> Bool {
    if case .waiting(_, _, let actual) = await connection.state { actual == failure } else { false }
}

struct FixtureRecord: Decodable {
    struct Request: Decodable { let method: String; let path: String }
    struct Response: Decodable { let status: Int; let headers: [String: String]; let body: JSONValue; let bodyFormat: String }
    let request: Request
    let response: Response
    func http() throws -> HTTPResponse {
        let data = response.bodyFormat == "text" ? Data((response.body.stringValue ?? "").utf8) : try JSONEncoder().encode(response.body)
        return HTTPResponse(data: data, response: HTTPURLResponse(url: testURL, statusCode: response.status,
                            httpVersion: "HTTP/1.1", headerFields: response.headers)!)
    }
}
enum Fixtures {
    static var root: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appending(path: "Fixtures/v2")
    }
    static var versions: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "manifest.json").path) }
            .sorted { $0.path < $1.path }
    }
    static func records(_ name: String, version: URL) throws -> [FixtureRecord] {
        try JSONDecoder().decode([FixtureRecord].self, from: Data(contentsOf: version.appending(path: "rest/\(name).json")))
    }
}

// TestClock yields to background tasks; serialize virtual-time cases to avoid
// competing clock advances and make scheduling reproducible on the macOS runner.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct NetworkingTests {}

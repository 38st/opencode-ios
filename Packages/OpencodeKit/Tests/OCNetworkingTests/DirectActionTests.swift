import Clocks
import Foundation
import Testing
import OCFoundation
@testable import OCNetworking

private actor ActionTransport: HTTPTransport {
    var calls: [String] = []
    let clock: TestClock<Duration>
    init(clock: TestClock<Duration>) { self.clock = clock }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        calls.append((request.url?.host ?? "") + (request.url?.path ?? ""))
        if request.url?.host == "last.invalid" { try await clock.sleep(for: .seconds(30)) }
        try Task.checkCancellation()
        let status = request.httpMethod == "POST" ? 204 : 200
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
        return HTTPResponse(data: Data("{}".utf8), response: response)
    }
    nonisolated func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}
@Test func directActionTriesLastForThreeSecondsThenRacesReadsOnly() async throws {
    let clock = TestClock(), transport = ActionTransport(clock: clock)
    let client = DirectActionClient(endpoints: try ["https://last.invalid", "https://other.invalid"].map { try #require(URL(string: $0)) },
        credential: nil, transport: transport, clock: .init(sleep: { try await clock.sleep(for: $0) }))
    let task = Task { try await client.connect() }
    await clock.advance(by: .seconds(3))
    let connected = try await task.value
    #expect(connected.url.host == "other.invalid")
    _ = try await connected.request(path: "/reply", method: .post, body: .object(["decision": .string("once")]))
    #expect(await transport.calls == ["last.invalid/api/info", "other.invalid/api/info", "other.invalid/reply"])
}

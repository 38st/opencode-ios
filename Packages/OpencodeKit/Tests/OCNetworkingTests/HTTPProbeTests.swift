import Foundation
import Testing
import Clocks
import OCFoundation
import OCModels
@testable import OCNetworking

extension NetworkingTests {
@Test func preemptiveAuthScopeAndGetRetries() async throws {
    let transport = FakeTransport { _, attempt in
        if attempt < 2 { throw URLError(.networkConnectionLost) }
        return response(body: Data("{\"ok\":true}".utf8))
    }
    let client = APIClient(baseURL: testURL.appending(path: "proxy"), credential: .password("fake"), transport: transport, clock: TestTime().clock)
    let value = try await client.send(Endpoint<JSONValue>.json(path: "/api/test", scope: .location(directory: "/tmp/a b")))
    #expect(value["ok"] == .bool(true))
    #expect(transport.requests.count == 3)
    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("opencode:fake".utf8).base64EncodedString())
    #expect(request.url?.path == "/proxy/api/test")
    #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/tmp/a b")
}

@Test func postIsNeverRetriedAndGetStopsAfterThreeAttempts() async {
    for method in [HTTPMethod.post, .get] {
        let transport = FakeTransport { _, _ in throw URLError(.cannotConnectToHost) }
        do { _ = try await APIClient(baseURL: testURL, transport: transport, clock: TestTime().clock).send(Endpoint<JSONValue>.json(method: method, path: "/api/test")) }
        catch APIError.transport {} catch { Issue.record("Unexpected error") }
        #expect(transport.requests.count == (method == .get ? 3 : 1))
    }
}

@Test func httpErrorMappingAndContentTypeBeforeDecode() async {
    for (status, type) in [(401, "application/json"), (404, "application/json"), (200, "text/html"), (503, "application/json"), (409, "application/json")] {
        let transport = FakeTransport { _, _ in response(status, type: type, headers: ["Retry-After": "7"], body: Data("{\"_tag\":\"Conflict\"}".utf8)) }
        do {
            _ = try await APIClient(baseURL: testURL, transport: transport, clock: TestTime().clock).send(Endpoint<Int>(path: "/api/test") { _, _ in
                Issue.record("Must not decode an unsuccessful response"); return 0
            })
            Issue.record("Expected failure")
        } catch APIError.unauthorized { #expect(status == 401) }
        catch APIError.notOpencode { #expect(status == 404 || type == "text/html") }
        catch APIError.serviceStarting(let delay) { #expect(delay == .seconds(7)) }
        catch APIError.server(let tag, let code, _) { #expect(tag == "Conflict" && code == status) }
        catch { Issue.record("Unexpected error") }
        #expect(transport.requests.count == 1)
    }
}

@Test(arguments: Fixtures.versions) func recordedProbeOutcomesAndClock(version: URL) async throws {
    let info = try Fixtures.records("server", version: version)[0].http()
    let unauthorized = try Fixtures.records("pairing", version: version)[0].http()
    let v1 = try Fixtures.records("v1-probe", version: version)
    let health = try v1[0].http(), html = try v1[1].http()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    let serverDate = try #require(info.response.value(forHTTPHeaderField: "Date").flatMap(formatter.date(from:)))
    let wall = serverDate.addingTimeInterval(-5)
    let serverClock = ServerClock(now: { wall })
    let transport = FakeTransport { _, _ in info }
    let outcome = await ServerProbe(transport: transport, clock: NetworkClock(now: TestTime().clock.now, date: { wall }, sleep: TestTime().clock.sleep), serverClock: serverClock).probe(endpoint: testURL)
    guard case .v2(let body) = outcome else { Issue.record("Expected V2"); return }
    #expect(body.version == version.lastPathComponent && body.supportsPairing)
    #expect(serverClock.offset == 5)
    let auth = await ServerProbe(transport: FakeTransport { _, _ in unauthorized }, clock: TestTime().clock).probe(endpoint: testURL)
    #expect(auth == .unauthorized(.v2))
    for fallback in [html, response(404), response(401, body: Data())] {
        let probe = ServerProbe(transport: FakeTransport { request, _ in request.url?.path == "/global/health" ? health : fallback }, clock: TestTime().clock)
        #expect(await probe.probe(endpoint: testURL) == .v1("1.19.3"))
    }
    #expect(await ServerProbe(transport: FakeTransport { _, _ in html }, clock: TestTime().clock).probe(endpoint: testURL) == .notOpencode)
    // Startup is a source-derived mutation: recordings capture ready servers only.
    let starting = response(503, headers: ["Retry-After": "2"], body: info.data)
    #expect(await ServerProbe(transport: FakeTransport { _, _ in starting }, clock: TestTime().clock).probe(endpoint: testURL) == .v2Starting(retryAfter: .seconds(2)))
}

@Test func versionGatesAndNullTolerance() throws {
    #expect(ServerInfo.minimumVersion == "2.0.25")
    for (version, supported, pairing) in [("2.0.9", false, false), ("2.0.10", false, false), ("2.0.24", false, false),
                                          ("2.0.25", true, true), ("2.0.25-beta", false, false), ("2.2.2", true, true),
                                          ("3.0.0", false, true), ("garbage", false, false)] {
        let json = "{\"version\":\"\(version)\",\"pid\":null,\"urls\":[null,4,\"http://localhost:1\"],\"paths\":null,\"capabilities\":null,\"future\":true}"
        let info = try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
        #expect(info.isSupported == supported && info.supportsPairing == pairing)
        #expect(info.urls.count == 1 && info.paths.isEmpty)
    }
}

}

extension NetworkingTests {
    @Test func unrelatedJSONIsNotAnOpencodeServer() async {
        let probe = ServerProbe(transport: FakeTransport { _, _ in response(body: Data("{}".utf8)) }, clock: TestTime().clock)
        #expect(await probe.probe(endpoint: testURL) == .notOpencode)
    }

    @Test func probeTimeoutUsesOnlyInjectedTime() async {
        let time = TestTime()
        let transport = FakeTransport { _, _ in
            try await time.clock.sleep(.seconds(100))
            return response()
        }
        let probe = ServerProbe(transport: transport, clock: time.clock)
        let task = Task { await probe.probe(endpoint: testURL, timeout: .seconds(2)) }
        await eventually { transport.requests.count == 1 }
        await time.test.advance(by: .seconds(2))
        #expect(await task.value == .failure(.timeout))
    }
}

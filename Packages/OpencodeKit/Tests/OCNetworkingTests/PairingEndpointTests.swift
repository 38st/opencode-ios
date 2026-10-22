import Foundation
import Clocks
import Testing
import OCModels
@testable import OCNetworking

extension NetworkingTests {
@Test func pairingParserReferenceVectors() throws {
    let link = try PairingParser.parse(" http://192.168.1.2:49374/auth/connect/abc_DEF-123 ")
    #expect(link.code == "abc_DEF-123" && link.urls.map(\.absoluteString) == ["http://192.168.1.2:49374"])
    let qr = try PairingParser.parse(#"{"code":"abc_DEF-123","urls":["http://192.168.1.2:49374","http://100.64.0.3:49374","http://192.168.1.2:49374"]}"#)
    #expect(qr.urls.count == 2)
    for invalid in ["http://192.168.1.2:49374/auth/connect/", "http://192.168.1.2:49374/auth/connect/abc/extra",
                    "opencode-ios://auth/connect/abc", "192.168.1.2:49374", #"{"code":"abc","urls":[]}"#,
                    #"{"code":"a/b","urls":["http://192.168.1.2:49374"]}"#,
                    #"{"code":"abc","urls":["opencode-ios://host"]}"#, #"{"urls":["http://192.168.1.2:49374"]}"#, "{not json"] {
        #expect(throws: PairingError.invalidInput) { try PairingParser.parse(invalid) }
    }
    for address in ["192.168.1.2:4096", "https://opencode.example.com/", "localhost", "devbox:4096", "[::1]:4096"] {
        #expect(PairingParser.bareServerAddress(address) != nil)
    }
    for address in ["abc_DEF-123", "http://192.168.1.2:4096/auth/connect/", "http://192.168.1.2:4096/auth/connect/…", "http://192.168.1.2:4096/connect"] {
        #expect(PairingParser.bareServerAddress(address) == nil)
    }
    for legacy in ["http://host/connect#eyJ1c2Vy", "http://host/connect?data=eyJ1c2Vy"] {
        #expect(PairingParser.isLegacy(legacy))
        #expect(throws: PairingError.legacyLink) { try PairingParser.parse(legacy) }
    }
    #expect(!PairingParser.isLegacy("http://host/connect"))
    #expect(!PairingParser.isLegacy("http://host/auth/connect/abc"))
    for invalid in ["https://user:pass@example.com", "http://host?a=1", "http://host#x", "ssh://host"] {
        #expect(PairingParser.serverAddress(invalid) == nil)
    }
    #expect(PairingParser.serverAddress("https://host/proxy/")?.path == "/proxy")
}

@Test func endpointClassificationAndATS() throws {
    for (url, kind) in [
        ("http://10.1.2.3", EndpointKind.lan), ("http://172.16.1.2", .lan), ("http://172.31.0.1", .lan),
        ("http://192.168.1.1", .lan), ("http://127.12.0.1", .lan), ("http://host.local", .lan),
        ("http://localhost", .lan), ("http://devbox:4096", .lan), ("http://[::1]", .lan),
        ("http://[fc00::1]", .lan), ("http://[fe80::1]", .lan), ("http://[::ffff:192.168.1.2]", .lan),
        ("http://100.64.0.0", .tailnet), ("http://100.127.255.255", .tailnet),
        ("https://host.ts.net", .tailnet), ("https://a.opentunnel.xyz", .tunnel),
        ("https://opentunnel.xyz.evil.com", .https), ("https://example.com", .https), ("ssh://host", .ssh)
    ] { #expect(EndpointPolicy.classify(URL(string: url)!) == kind, Comment(rawValue: url)) }
    #expect([EndpointKind.lan, .tailnet, .https, .tunnel, .ssh].map(\.rank) == [0, 1, 2, 3, 4])
    for refused in ["http://example.com", "http://host.ts.net", "http://8.8.8.8", "http://172.32.0.1", "http://100.128.0.0"] {
        #expect(throws: (any Error).self) { try EndpointPolicy.validate(URL(string: refused)!) }
    }
    try EndpointPolicy.validate(URL(string: "http://100.64.0.3")!)
    try EndpointPolicy.validate(URL(string: "https://host.ts.net")!)
}

@Test func resolverWaitsHalfSecondForBetterRank() async {
    let time = TestTime()
    let clock = time.clock
    let lan = EndpointRecord(url: testURL, kind: .lan)
    let remote = EndpointRecord(url: URL(string: "https://example.com")!, kind: .https)
    let transport = FakeTransport { request, _ in
        if request.url?.host == "127.0.0.1" { try await clock.sleep(.milliseconds(300)) }
        return response(body: try JSONEncoder().encode(testInfo))
    }
    let resolver = EndpointResolver(transport: transport, clock: clock)
    let task = Task { await resolver.resolve(endpoints: [remote, lan], credential: .password("fake")) }
    await eventually { transport.requests.count == 2 }
    await time.test.advance(by: .milliseconds(350))
    let result = await task.value
    #expect(result.selected?.id == lan.id)
    #expect(result.diagnoses.count == 2)
}

@Test func resolverTimeoutsDiagnosesAndDiscovery() async {
    let discoveredInfo = ServerInfo(version: "2.0.32", urls: [URL(string: "http://localhost:2")!, URL(string: "https://new.example")!])
    let transport = FakeTransport { request, _ in
        switch request.url?.host {
        case "dns.example": throw URLError(.cannotFindHost)
        case "tls.example": throw URLError(.serverCertificateUntrusted)
        case "auth.example": return response(401, body: Data(#"{"_tag":"UnauthorizedError"}"#.utf8))
        case "timeout.example": throw URLError(.timedOut)
        case "192.168.1.2": throw URLError(.notConnectedToInternet)
        default: return response(body: try JSONEncoder().encode(discoveredInfo))
        }
    }
    let entries = ["https://dns.example", "https://tls.example", "https://auth.example", "https://timeout.example", "http://192.168.1.2", "http://public.example", "https://ok.example"]
        .map { EndpointRecord(url: URL(string: $0)!, kind: EndpointPolicy.classify(URL(string: $0)!)) }
    let result = await EndpointResolver(transport: transport, clock: TestTime().clock).resolve(endpoints: entries, credential: .password("fake"), localNetworkDenied: true)
    for (entry, failure) in zip(entries, [ConnectionFailure.dnsFailure, .tlsError, .unauthorized, .timeout, .localNetworkDenied, .insecureRemote]) {
        #expect(result.diagnoses[entry.id] == .failure(failure))
    }
    #expect(result.discovered.map(\.url.absoluteString) == ["https://new.example"])
    #expect(result.discovered.first?.source == .discovered)
}

@Test func pairingSingleUseRacesAndPrefersFirstAfterHealthCheck() async throws {
    let first = URL(string: "https://preferred.example")!
    let second = URL(string: "https://fast.example")!
    let transport = FakeTransport { request, _ in
        if request.url?.path == "/api/info" { return response(body: try JSONEncoder().encode(testInfo)) }
        if request.url?.host == "preferred.example" { return response(401) }
        return response(body: Data(#"{"token":"redeemed"}"#.utf8))
    }
    let result = try await PairingService(transport: transport, clock: TestTime().clock).redeem(PairingLink(urls: [first, second], code: "abc"))
    #expect(result.preferredURL == first && result.token == "redeemed")
    #expect(result.server.endpoints.map(\.url) == [first, second])
    #expect(transport.requests.filter { $0.url?.path == "/auth/connect/abc" }.count == 2)
    let health = try #require(transport.requests.first { $0.url?.path == "/api/info" })
    #expect(health.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("opencode:redeemed".utf8).base64EncodedString())
}

@Test func expiredVersusUnreachablePairing() async {
    for expired in [true, false] {
        let service = PairingService(transport: FakeTransport { _, _ in
            if expired { return response(401) }
            throw URLError(.cannotConnectToHost)
        }, clock: TestTime().clock)
        do { _ = try await service.redeem(PairingLink(urls: [testURL], code: "abc")); Issue.record("Expected error") }
        catch let error as PairingError { #expect(error == (expired ? .expired : .unreachable)) }
        catch { Issue.record("Unexpected error") }
    }
}

@Test func untrustedNetworksCanPreferHTTPS() async {
    let endpoints = [EndpointRecord(url: testURL, kind: .lan),
                     EndpointRecord(url: URL(string: "https://safe.example")!, kind: .https)]
    let resolver = EndpointResolver(transport: FakeTransport(), clock: TestTime().clock, prefersHTTPS: true)
    let result = await resolver.resolve(endpoints: endpoints, credential: .password("fake"))
    #expect(result.selected?.url.scheme == "https")
}

}

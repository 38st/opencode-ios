import Foundation
import Testing
import OCFoundation
import OCModels
@testable import OCNetworking

/// The credential travels in the clear only when no encrypted endpoint answers.
@Suite struct EndpointPrivacyTests {
    let lan = EndpointRecord(url: URL(string: "http://192.168.1.20:4096")!, kind: .lan)
    let tunnel = EndpointRecord(url: URL(string: "https://mac.example")!, kind: .https)

    @Test func anEncryptedEndpointThatAnswersKeepsTheCredentialOffPlainHTTP() async {
        let transport = FakeTransport()
        let result = await EndpointResolver(transport: transport, clock: TestTime().clock, prefersHTTPS: true)
            .resolve(endpoints: [lan, tunnel], credential: .password("fake"))
        #expect(result.selected?.id == tunnel.id)
        #expect(transport.requests.map(\.url?.host) == ["mac.example"])
        #expect(result.diagnoses[lan.id] == .notSelected)
    }

    @Test func plainHTTPIsTriedWhenNoEncryptedEndpointAnswers() async {
        let transport = FakeTransport { request, _ in
            if request.url?.scheme == "https" { throw URLError(.cannotFindHost) }
            return response(body: try JSONEncoder().encode(testInfo))
        }
        let result = await EndpointResolver(transport: transport, clock: TestTime().clock, prefersHTTPS: true)
            .resolve(endpoints: [lan, tunnel], credential: .password("fake"))
        #expect(result.selected?.id == lan.id)
        #expect(result.diagnoses[tunnel.id] == .failure(.dnsFailure))
        #expect(transport.requests.map(\.url?.host) == ["mac.example", "192.168.1.20"])
    }

    @Test func aLANOnlyServerIsUnchanged() async {
        let transport = FakeTransport()
        let result = await EndpointResolver(transport: transport, clock: TestTime().clock, prefersHTTPS: true)
            .resolve(endpoints: [lan], credential: .password("fake"))
        #expect(result.selected?.id == lan.id)
    }

    @Test func notificationActionsTryEncryptedEndpointsFirst() async throws {
        let transport = FakeTransport()
        let client = DirectActionClient(endpoints: [lan.url, tunnel.url], credential: .password("fake"), transport: transport)
        let session = try await client.connect()
        #expect(session.url == tunnel.url)
        #expect(transport.requests.map(\.url?.host) == ["mac.example"])
        #expect(EndpointPolicy.isEncrypted(URL(string: "http://100.101.102.103:4096")!))
        #expect(!EndpointPolicy.isEncrypted(lan.url))
    }
}

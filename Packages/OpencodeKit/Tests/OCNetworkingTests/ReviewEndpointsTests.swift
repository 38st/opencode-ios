import Foundation
import Testing
import OCModels
import OCFoundation
@testable import OCNetworking

@Test func rawFileReadsAcceptOnlyTheirRawStatusesAndEscapeSegments() async throws {
    for status in [200, 206, 304, 416] {
        let transport = FakeTransport { request, _ in
            #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
            #expect(request.value(forHTTPHeaderField: "Range") == "bytes=0-3")
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "W/\"4-a\"")
            #expect(request.url?.absoluteString.contains("space%20%23%25%3F.txt") == true)
            return response(status, type: "text/plain", headers: ["ETag": "W/\"4-a\"", "Content-Range": status == 416 ? "bytes */4" : "bytes 0-3/4"], body: status == 304 || status == 416 ? Data() : Data("text".utf8))
        }
        let value = try await APIClient(baseURL: testURL, transport: transport).readFile("sub/space #%?.txt", directory: "/p", range: 0..<4, etag: "W/\"4-a\"")
        #expect(value.status == status && value.totalSize == 4)
    }
    let api = APIClient(baseURL: testURL, transport: FakeTransport { _, _ in response(type: "text/html", body: Data("<html/>".utf8)) })
    do { _ = try await api.send(ReadEndpoints.location("/p")); Issue.record("JSON route accepted HTML") } catch APIError.notOpencode {}
    do { _ = try await api.readFile("../secret", directory: "/p"); Issue.record("Parent path accepted") } catch APIError.refused {}
}
@Test func review503RetainsUserMessageAndDiffOmitsOptionalQueries() async throws {
    let api = APIClient(baseURL: testURL, transport: FakeTransport { _, _ in response(503, body: Data(#"{"_tag":"VcsError","message":"Choose a review base"}"#.utf8)) })
    do { _ = try await api.send(ReviewEndpoints.diff("/p")); Issue.record("Expected 503") }
    catch APIError.server(_, let status, let body) { #expect(status == 503 && body["message"]?.stringValue == "Choose a review base") }
    // The server's own service states keep their retry semantics on every other route.
    for body in [#"{"code":"service_starting"}"#, #"{"code":"service_stopping"}"#,
                 #"{"code":"service_failed","message":"The background service could not start.","action":"Run `opencode service restart`."}"#] {
        let api = APIClient(baseURL: testURL, transport: FakeTransport { _, _ in response(503, headers: ["Retry-After": "1"], body: Data(body.utf8)) })
        do { _ = try await api.send(ReadEndpoints.location("/p")); Issue.record("Expected 503") }
        catch APIError.serviceStarting(let delay) { #expect(delay == .seconds(1)) }
        catch { Issue.record("Unexpected \(error) for \(body)") }
    }
    let endpoint = ReadEndpoints.diff("s")
    #expect(endpoint.query.isEmpty)
    #expect(ReviewEndpoints.diff("/p", mode: "branch").query == [.init(name: "mode", value: "branch")])
    #expect(ComposerEndpoints.find("x", directory: "/p", type: "file", limit: 200).query.contains(.init(name: "type", value: "file")))
}

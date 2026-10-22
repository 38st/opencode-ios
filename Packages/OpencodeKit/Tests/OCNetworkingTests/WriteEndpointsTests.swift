import Foundation
import Testing
import OCFoundation
import OCModels
@testable import OCNetworking

@Test func writeEndpointsPreserveBodiesAndEncodeOptionalReasons() throws {
    let prompt = PromptInput(text: "Steer", files: [.init(uri: "data:text/plain;base64,YQ==")], delivery: .queue)
    let bytes = try prompt.body(id: "msg_id")
    #expect(WriteEndpoints.prompt("ses_id", body: bytes).body == bytes)
    let raw = try JSONDecoder().decode(JSONValue.self, from: bytes)
    #expect(raw["id"] == .string("msg_id") && raw["delivery"] == .string("queue"))
    #expect(raw["agent"] == nil && raw["model"] == nil && raw["resume"] == nil)
    #expect(WriteEndpoints.interrupt("s", resume: true).query.first?.value == "true")
    let dismiss = WriteEndpoints.dismissForm("global", form: "f", reason: "Not now & later?", directory: "/path with spaces")
    let request = try APIClient.request(baseURL: testURL, path: dismiss.path, method: dismiss.method, query: dismiss.query, scope: dismiss.scope)
    let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.contains(.init(name: "message", value: "Not now & later?")) == true)
    #expect(query?.contains(.init(name: "location[directory]", value: "/path with spaces")) == true)
}
@Test func permission404AndForm409AreSettledButUnrelatedErrorsRemainErrors() async throws {
    for (status, tag, id, success) in [(404, "PermissionNotFoundError", "p", true), (404, "SessionNotFoundError", "s", false)] {
        let api = APIClient(baseURL: testURL, transport: FakeTransport { _, _ in
            response(status, body: try JSONEncoder().encode(["_tag": tag, "id": id]))
        })
        do { try await api.send(WriteEndpoints.permission("s", request: "p", decision: .once)); #expect(success) }
        catch { #expect(!success) }
    }
    for (status, tag, id, success) in [(409, "FormAlreadySettledError", "f", true), (404, "FormNotFoundError", "f", true), (409, "ConflictError", "f", false), (409, "FormAlreadySettledError", "other", false)] {
        let api = APIClient(baseURL: testURL, transport: FakeTransport { _, _ in
            response(status, body: try JSONEncoder().encode(["_tag": tag, "id": id]))
        })
        do { try await api.send(WriteEndpoints.formReply("s", form: "f", answer: ["ok": .bool(true)])); #expect(success) }
        catch { #expect(!success) }
    }
}
@Test func commandsAreNeverAutomaticallyRetried() async throws {
    let transport = FakeTransport { _, _ in throw URLError(.networkConnectionLost) }
    let api = APIClient(baseURL: testURL, transport: transport)
    do { try await api.send(WriteEndpoints.command("s", name: "review", input: .init(text: "changes"))) } catch APIError.transport {}
    #expect(transport.requests.count == 1)
    #expect(transport.requests.first?.url?.path == "/api/session/s/command")
}

@Test func gatewayWriteRejectionRetainsItsPermanentStatus() async throws {
    let api = APIClient(baseURL: testURL, transport: FakeTransport { _, _ in
        response(413, type: "text/plain", body: Data("Request too large".utf8))
    })
    do {
        _ = try await api.send(WriteEndpoints.prompt("s", body: Data(#"{"id":"msg_id","text":"saved"}"#.utf8)))
        Issue.record("Expected a permanent rejection")
    } catch APIError.server(_, let status, _) { #expect(status == 413) }
}

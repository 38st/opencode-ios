import Foundation
import Testing
import OCModels
import OCFoundation
@testable import OCNetworking

private func request<R>(_ endpoint: Endpoint<R>) throws -> URLRequest {
    try APIClient.request(baseURL: testURL, path: endpoint.path, method: endpoint.method, query: endpoint.query, scope: endpoint.scope, body: endpoint.body)
}
private func body(_ request: URLRequest) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody)) }
private func query(_ request: URLRequest) -> [String: String] {
    Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a }
}

@Test func sessionFeatureRoutesMatchTheServer() throws {
    let move = try request(SessionEndpoints.move("ses_1", directory: "/wt a", delivery: .queue))
    #expect(move.httpMethod == "POST" && move.url?.path == "/api/session/ses_1/move" && move.url?.query == nil, "Move is global")
    #expect(try body(move) == .object(["directory": .string("/wt a"), "delivery": .string("queue")]))
    let export = try request(SessionEndpoints.export("ses_1", sanitize: true))
    #expect(export.httpMethod == "GET" && export.url?.path == "/api/experimental/session/ses_1/export" && query(export) == ["sanitize": "true"])
    #expect(query(try request(SessionEndpoints.export("ses_1", sanitize: false))) == ["sanitize": "false"])
    let range = StatsRange(.today, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    let stats = try request(SessionEndpoints.stats(range, projectID: "prj"))
    #expect(stats.url?.path == "/api/experimental/session/stats")
    #expect(query(stats) == ["from": "1799938800000", "to": "1800000000000", "timezone": "Asia/Tokyo", "tools": "detail", "project": "prj"])
    #expect(query(try request(SessionEndpoints.stats(range, projectID: nil)))["project"] == nil, "All projects omit the filter")
    let generate = try request(SessionEndpoints.generate("ses_1", prompt: "Why?"))
    let generated = try body(generate)
    #expect(generate.httpMethod == "POST" && generate.url?.path == "/api/session/ses_1/generate" && generated == .object(["prompt": .string("Why?")]))
}

@Test func sessionFeatureResponsesDecodeWithErrorsAndEmptyStates() async throws {
    let transport = FakeTransport { request, _ in
        switch request.url?.path ?? "" {
        case "/api/experimental/session/ses_wrapped/export":
            response(body: Data(#"{"data":{"info":{"id":"ses_wrapped"},"messages":[]}}"#.utf8))
        case "/api/experimental/session/ses_bare/export": response(body: Data(#"{"info":{"id":"ses_bare"},"messages":[{"id":"m","type":"user"}]}"#.utf8))
        case "/api/experimental/session/ses_broken/export": response(body: Data(#"{"data":{"messages":[]}}"#.utf8))
        case "/api/experimental/session/ses_missing/export":
            response(404, body: Data(#"{"_tag":"SessionNotFoundError","message":"Session not found"}"#.utf8))
        case "/api/experimental/session/stats":
            response(body: Data(#"{"data":{"range":{"from":1,"to":2},"sessions":0,"prompts":0,"steps":0,"tools":{"mode":"detail","totals":{"calls":0},"usage":[]},"activity":[],"models":[]}}"#.utf8))
        case "/api/session/ses_1/generate": response(body: Data(#"{"data":{"text":"Side answer."}}"#.utf8))
        case "/api/session/ses_busy/generate": response(503, body: Data(#"{"_tag":"ServiceUnavailableError","message":"session generation"}"#.utf8))
        case "/api/session/ses_1/move": response(204)
        case "/api/session/ses_bad/move": response(400, body: Data(#"{"_tag":"InvalidRequestError","message":"Not a directory: /x"}"#.utf8))
        default: response(404)
        }
    }
    let client = APIClient(baseURL: testURL, transport: transport)
    #expect(try await client.send(SessionEndpoints.export("ses_wrapped", sanitize: true))["info"]?["id"] == .string("ses_wrapped"))
    #expect(try await client.send(SessionEndpoints.export("ses_bare", sanitize: true))["messages"]?.arrayValue?.count == 1)
    await #expect(throws: APIError.self) { try await client.send(SessionEndpoints.export("ses_broken", sanitize: true)) }
    do { _ = try await client.send(SessionEndpoints.export("ses_missing", sanitize: true)); Issue.record("Expected a 404") }
    catch APIError.server(let tag, let status, _) { #expect(tag == "SessionNotFoundError" && status == 404) }
    let stats = try await client.send(SessionEndpoints.stats(StatsRange(.week, now: .now), projectID: nil)).data
    #expect(stats.isEmpty && stats.tools.byTool.isEmpty)
    #expect(try await client.send(SessionEndpoints.generate("ses_1", prompt: "q")).data.text == "Side answer.")
    await #expect(throws: APIError.self) { try await client.send(SessionEndpoints.generate("ses_busy", prompt: "q")) }
    try await client.send(SessionEndpoints.move("ses_1", directory: "/wt", delivery: .steer))
    do { try await client.send(SessionEndpoints.move("ses_bad", directory: "/x", delivery: .steer)); Issue.record("Expected a 400") }
    catch APIError.server(_, let status, let body) { #expect(status == 400 && body["message"]?.stringValue == "Not a directory: /x") }
}

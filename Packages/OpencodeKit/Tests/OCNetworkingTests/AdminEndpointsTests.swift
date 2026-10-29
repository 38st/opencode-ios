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

@Test func integrationRoutesAreLocationScopedAndCarryNoStoredSecret() throws {
    let list = try request(AdminEndpoints.integrations("/w p"))
    #expect(list.url?.path == "/api/integration" && query(list)["location[directory]"] == "/w p")
    let key = try request(AdminEndpoints.connectKey("mock", directory: "/w", key: "fake-key", answers: .object(["region": .string("eu")]), label: "Work"))
    #expect(key.httpMethod == "POST" && key.url?.path == "/api/integration/mock/connect/key")
    #expect(try body(key) == .object(["key": .string("fake-key"), "answer": .object(["region": .string("eu")]), "label": .string("Work")]))
    #expect(try body(request(AdminEndpoints.connectKey("mock", directory: "/w", key: "k"))) == .object(["key": .string("k")]), "Absent fields are omitted")
    let oauth = try request(AdminEndpoints.startOAuth("openai", directory: "/w", methodID: "chatgpt"))
    #expect(oauth.url?.path == "/api/integration/openai/connect/oauth")
    #expect(try body(oauth) == .object(["methodID": .string("chatgpt")]))
    #expect(try request(AdminEndpoints.oauthStatus("openai", attempt: "con_1", directory: "/w")).url?.path == "/api/integration/openai/connect/oauth/con_1")
    let complete = try request(AdminEndpoints.completeOAuth("openai", attempt: "con_1", directory: "/w", code: "abc"))
    #expect(complete.url?.path == "/api/integration/openai/connect/oauth/con_1/complete")
    #expect(try body(complete)["code"]?.stringValue == "abc")
    #expect(try request(AdminEndpoints.cancelOAuth("openai", attempt: "con_1", directory: "/w")).httpMethod == "DELETE")
    #expect(try request(AdminEndpoints.startCommand("copilot", directory: "/w", methodID: "gh")).url?.path == "/api/integration/copilot/connect/command")
    #expect(try request(AdminEndpoints.cancelCommand("copilot", attempt: "con_2", directory: "/w")).url?.path == "/api/integration/copilot/connect/command/con_2")
    let rename = try request(AdminEndpoints.renameCredential("cred_1", label: "Home"))
    #expect(rename.httpMethod == "PATCH" && rename.url?.path == "/api/credential/cred_1" && rename.url?.query == nil)
    #expect(try request(AdminEndpoints.activateCredential("cred_1")).url?.path == "/api/credential/cred_1/activate")
    #expect(try request(AdminEndpoints.removeCredential("cred_1")).httpMethod == "DELETE")
}

@Test func adminRoutesMatchTheServer() throws {
    #expect(try request(AdminEndpoints.mcpConnect("fixture", directory: "/w")).url?.path == "/api/experimental/mcp/fixture/connect")
    #expect(try request(AdminEndpoints.mcpDisconnect("fixture", directory: "/w")).url?.path == "/api/experimental/mcp/fixture/disconnect")
    let saved = try request(AdminEndpoints.savedPermissions(projectID: "prj"))
    #expect(saved.url?.path == "/api/permission/saved" && query(saved) == ["projectID": "prj"])
    #expect(try request(AdminEndpoints.deleteSavedPermission("psv_1")).url?.path == "/api/permission/saved/psv_1")
    #expect(try body(request(AdminEndpoints.checkPlugins("/w"))) == .object([:]))
    #expect(try body(request(AdminEndpoints.updatePlugins("/w", targets: ["a@1"]))) == .object(["targets": .array([.string("a@1")])]))
    let project = try request(AdminEndpoints.updateProject("prj", name: "App", icon: .object(["color": .string("blue")]), startCommand: "bun install"))
    #expect(project.httpMethod == "PATCH" && project.url?.path == "/api/project/prj")
    #expect(try body(project) == .object(["name": .string("App"), "icon": .object(["color": .string("blue")]), "commands": .object(["start": .string("bun install")])]))
    #expect(try body(request(AdminEndpoints.updateProject("prj", startCommand: ""))) == .object(["commands": .object(["start": .string("")])]))
    let remove = try request(AdminEndpoints.removeWorktree(projectID: "prj", directory: "/wt", force: false))
    #expect(remove.httpMethod == "DELETE" && remove.url?.path == "/api/worktree")
    #expect(try body(remove) == .object(["projectID": .string("prj"), "directory": .string("/wt"), "force": .bool(false)]))
    #expect(try body(request(AdminEndpoints.createWorktree(projectID: "prj"))) == .object(["projectID": .string("prj")]))
    #expect(try request(AdminEndpoints.refreshWorktrees(projectID: "prj")).url?.path == "/api/worktree/refresh")
    #expect(query(try request(AdminEndpoints.vcsStatus("/wt")))["location[directory]"] == "/wt")
    #expect(try body(request(AdminEndpoints.setShell(nil))) == .object(["shell": .null]), "null returns to the default")
    #expect(try request(AdminEndpoints.setShell("/bin/zsh")).url?.path == "/api/experimental/config")
    let evict = try request(AdminEndpoints.evictLocation("/w"))
    #expect(evict.httpMethod == "DELETE" && evict.url?.path == "/api/debug/location" && query(evict)["location[directory]"] == "/w")
    #expect(try request(AdminEndpoints.reloadLocations).url?.path == "/api/location/reload")
    #expect(query(try request(AdminEndpoints.archivedProjects)) == ["archived": "true"])
}

@Test func adminResponsesDecodeTolerantly() async throws {
    let transport = FakeTransport { request, _ in
        switch request.url?.path ?? "" {
        case "/api/config": response(body: Data(#"[{"type":"directory","path":"/c"},{"type":"document","info":{"shell":"/bin/zsh"}},7]"#.utf8))
        case "/api/integration/x/connect/oauth/con_1": response(body: Data(#"{"location":{"directory":"/w"},"data":{"status":"failed","message":"Denied","time":{"created":1}}}"#.utf8))
        case "/api/integration/x/connect/command/con_1": response(body: Data(#"{"location":{"directory":"/w"},"data":{"status":"later"}}"#.utf8))
        case "/api/debug/location": response(body: Data(#"[{"directory":"/w"},{"directory":"/v","workspaceID":"wrk_1"}]"#.utf8))
        case "/api/plugin": response(body: Data(#"{"location":{"directory":"/w"},"data":[{"id":"p","source":{"type":"package","target":"p@1","version":"1.0.0","outdated":true},"features":{"server":true},"state":{"status":"failed","error":"Boom"}}]}"#.utf8))
        default: response(404, body: Data(#"{"_tag":"NotFound"}"#.utf8))
        }
    }
    let api = APIClient(baseURL: testURL, transport: transport)
    let config = try await api.send(AdminEndpoints.config("/w")).values
    #expect(config.map(\.type) == ["directory", "document"])
    #expect(try await api.send(AdminEndpoints.oauthStatus("x", attempt: "con_1", directory: "/w")) == .failed("Denied"))
    #expect(try await api.send(AdminEndpoints.commandStatus("x", attempt: "con_1", directory: "/w")) == .unknown("later"))
    #expect(try await api.send(AdminEndpoints.bootedLocations).values.map(\.directory) == ["/w", "/v"])
    let plugin = try #require(try await api.send(AdminEndpoints.plugins("/w")).data.values.first)
    #expect(plugin.outdated && plugin.target == "p@1" && plugin.failure == "Boom" && plugin.features == ["server"])
}

@Test func worktreeRefusalsKeepTheirForceFlag() async throws {
    let transport = FakeTransport { _, _ in
        response(400, body: Data(#"{"_tag":"WorktreeError","name":"WorktreeError","data":{"message":"contains modified or untracked files","forceRequired":true}}"#.utf8))
    }
    let api = APIClient(baseURL: testURL, transport: transport)
    do {
        try await api.send(AdminEndpoints.removeWorktree(projectID: "p", directory: "/wt", force: false))
        Issue.record("Expected a refusal")
    } catch APIError.server(let tag, let status, let body) {
        #expect(tag == "WorktreeError" && status == 400)
        #expect(WorktreeFailure(raw: body).forceRequired)
    }
}

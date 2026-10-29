import Foundation
import Testing
import OCModels
import OCFoundation
@testable import OCNetworking

private struct RecordedFrame: Decodable {
    let connection: Int
    let direction: String
    let opcode: Int?
    let payload: String?
    var bytes: Data { payload.flatMap { Data(base64Encoded: $0) } ?? Data() }
}

/// The recorded PTY session (Tools/fixture-recorder `pty`): replayed and live text, then one 0x00 control frame per
/// connection, and a resume whose cursor counts the first connection's live output in UTF-16 code units.
@Test(arguments: Fixtures.versions) func recordedFramesParseInOrder(version: URL) throws {
    let url = version.appending(path: "ws/pty.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let frames = try JSONDecoder().decode([RecordedFrame].self, from: Data(contentsOf: url)).filter { $0.direction == "received" }
    var cursors: [Int: Int] = [:], live: [Int: Int] = [:], controls: [Int: Int] = [:]
    for frame in frames {
        let parsed = frame.opcode == 2 ? PTYFrame.parse(binary: frame.bytes) : frame.opcode == 1 ? .output(String(decoding: frame.bytes, as: UTF8.self)) : nil
        switch parsed {
        case .control(let cursor)?:
            #expect(controls[frame.connection] == nil, "One control frame per connection")
            controls[frame.connection] = cursor; cursors[frame.connection] = cursor
        case .output(let text)?:
            if let cursor = cursors[frame.connection] { cursors[frame.connection] = cursor + text.utf16.count; live[frame.connection, default: 0] += text.utf16.count }
        case .ignored?, nil: break
        }
    }
    let first = try #require(cursors[1]), resumed = try #require(controls[2])
    #expect(controls[1] == 0)
    #expect(live[1, default: 0] > 0)
    #expect(resumed >= first, "The resumed connection starts at or after the cursor the first one reached")
}

@Test func controlFramesNeedAZeroByteAndASafeCursor() {
    func frame(_ json: String, first: UInt8 = 0) -> Data { Data([first]) + Data(json.utf8) }
    #expect(PTYFrame.parse(binary: frame(#"{"cursor":42}"#)) == .control(cursor: 42))
    #expect(PTYFrame.parse(binary: frame(#"{"cursor":0,"other":true}"#)) == .control(cursor: 0))
    for ignored in [frame(#"{"cursor":42}"#, first: 1), frame("{bad"), frame(#"{"cursor":-1}"#), frame(#"{"cursor":1.5}"#),
                    frame(#"{"cursor":"7"}"#), frame(#"{"cursor":9007199254740992}"#), frame("{}"), Data(), Data([0])] {
        #expect(PTYFrame.parse(binary: ignored) == .ignored)
    }
}

@Test func terminalRoutesAreLocationScoped() throws {
    func request<R>(_ endpoint: Endpoint<R>) throws -> URLRequest {
        var request = try APIClient.request(baseURL: testURL, path: endpoint.path, method: endpoint.method, query: endpoint.query, scope: endpoint.scope, body: endpoint.body)
        for (name, value) in endpoint.headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
    let list = try request(TerminalEndpoints.list("/w p"))
    #expect(list.httpMethod == "GET" && list.url?.path == "/api/pty")
    #expect(URLComponents(url: try #require(list.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/w p")
    let create = try request(TerminalEndpoints.create("/w", command: "/bin/zsh", title: "Terminal 2"))
    #expect(create.httpMethod == "POST" && create.url?.path == "/api/pty")
    #expect(try JSONDecoder().decode(JSONValue.self, from: try #require(create.httpBody)) == .object(["command": .string("/bin/zsh"), "title": .string("Terminal 2")]))
    let defaultShell = try request(TerminalEndpoints.create("/w", title: "Terminal 1"))
    #expect(try JSONDecoder().decode(JSONValue.self, from: try #require(defaultShell.httpBody))["command"] == nil, "The server's configured shell")
    let resize = try request(TerminalEndpoints.update("pty_1", directory: "/w", cols: 80, rows: 24))
    #expect(resize.httpMethod == "PUT" && resize.url?.path == "/api/pty/pty_1")
    #expect(try JSONDecoder().decode(JSONValue.self, from: try #require(resize.httpBody)) == .object(["size": .object(["cols": .integer(80), "rows": .integer(24)])]))
    #expect(try request(TerminalEndpoints.delete("pty_1", directory: "/w")).httpMethod == "DELETE")
    let token = try request(TerminalEndpoints.connectToken("pty_1", directory: "/w"))
    #expect(token.url?.path == "/api/pty/pty_1/connect-token" && token.value(forHTTPHeaderField: "x-opencode-ticket") == "1")
    let shells = try request(TerminalEndpoints.shells)
    #expect(shells.url?.path == "/api/config/shell" && shells.url?.query == nil, "A global route")
    let run = try request(TerminalEndpoints.runShell("/w", command: "ls -la"))
    #expect(run.httpMethod == "POST" && run.url?.path == "/api/shell")
    #expect(try request(TerminalEndpoints.removeShell("sh_1", directory: "/w")).httpMethod == "DELETE")
}

@Test func routeHeadersReachTheRequestAndShellsDecodeBare() async throws {
    let transport = FakeTransport { request, _ in
        if request.url?.path == "/api/config/shell" { return response(body: Data(#"[{"path":"/bin/bash","name":"bash","acceptable":true}]"#.utf8)) }
        #expect(request.value(forHTTPHeaderField: "x-opencode-ticket") == "1")
        return response(body: Data(#"{"location":{"directory":"/w"},"data":{"ticket":"t-1","expires_in":60}}"#.utf8))
    }
    let api = APIClient(baseURL: testURL, transport: transport)
    #expect(try await api.send(TerminalEndpoints.connectToken("pty_1", directory: "/w")).data.ticket == "t-1")
    #expect(try await api.send(TerminalEndpoints.shells).values.map(\.path) == ["/bin/bash"])
}

@Test func socketRequestCarriesTheHeaderNotTheCredential() throws {
    let api = APIClient(baseURL: testURL, credential: .password("secret"))
    let request = try api.webSocketRequest(path: "/api/pty/pty_1/connect", query: [.init(name: "cursor", value: "-1")], scope: .location(directory: "/w"))
    let url = try #require(request.url)
    #expect(url.scheme == "ws" && url.path == "/api/pty/pty_1/connect")
    #expect(!url.absoluteString.contains("secret") && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    #expect(Set(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []) == ["cursor", "location[directory]"])
    let ticketed = try api.webSocketRequest(path: "/api/pty/pty_1/connect", query: [.init(name: "ticket", value: "t")], scope: .location(directory: "/w"), authenticated: false)
    #expect(ticketed.value(forHTTPHeaderField: "Authorization") == nil)
    let secure = try APIClient(baseURL: try #require(URL(string: "https://host.example/base"))).webSocketRequest(path: "/api/pty/p/connect", query: [], scope: .global)
    #expect(secure.url?.scheme == "wss" && secure.url?.path == "/base/api/pty/p/connect")
}

@Test func aPingThatNeverAnswersTimesOut() async {
    let started = ContinuousClock.now
    #expect(await URLSessionWebSocket.answers(within: .milliseconds(50)) { _ in } == false)
    #expect(started.duration(to: .now) < .seconds(5), "The deadline answers; nothing waits on the lost ping")
    #expect(await URLSessionWebSocket.answers(within: .seconds(5)) { pong in pong(nil) } == true)
    #expect(await URLSessionWebSocket.answers(within: .seconds(5)) { pong in pong(URLError(.networkConnectionLost)) } == false)
}

import Foundation
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCSecurity
import OCSync

private let projectionEnvironment = ProcessInfo.processInfo.environment
private let projectionLive = projectionEnvironment["OPENCODE_LIVE_MOCK_URL"] != nil
private enum ProjectionFailure: Error { case timeout }
@MainActor private func projectionWait(_ predicate: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(45))
    while !predicate() {
        if ContinuousClock.now >= deadline { throw ProjectionFailure.timeout }
        try await Task.sleep(for: .milliseconds(20))
    }
}
extension LiveContracts {
@Test(.enabled(if: projectionLive, "Requires Tools/contract sandbox"), .timeLimit(.minutes(3)))
@MainActor func sandboxProjectionAndMidTurnReconnect() async throws {
    let address = try #require(projectionEnvironment["OPENCODE_LIVE_URL"])
    let url = try #require(URL(string: address))
    let password = try #require(projectionEnvironment["OPENCODE_LIVE_PASSWORD"])
    let directory = try #require(projectionEnvironment["OPENCODE_LIVE_DIRECTORY"])
    let mockAddress = try #require(projectionEnvironment["OPENCODE_LIVE_MOCK_URL"])
    let mock = try #require(URL(string: mockAddress))
    let credential = Credential.password(password), api = APIClient(baseURL: url, credential: credential)
    let endpoint = EndpointRecord(url: url, kind: .lan)
    let record = ServerRecord(name: "Live projection", endpoints: [endpoint])
    let credentials = CredentialStore(secrets: InMemorySecretStore())
    try await credentials.save(credential, for: record.id)
    let connection = ServerConnection(endpoints: [endpoint], credential: credential, pathMonitor: nil)
    await connection.allowLocalNetwork()
    let store = ServerStore(record: record, connection: connection, credentials: credentials)
    do {
        await store.start()
        try await projectionWait { store.resync?.records.last?.succeeded == true }
        for (scenario, disconnect) in [("reasoning-text", false), ("interrupt", true)] {
            var request = URLRequest(url: mock.appending(path: "admin/scenario")); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["name": scenario])
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            let body: JSONValue = .object(["title": .string("Swift live parity"), "location": .object(["directory": .string(directory)]), "model": .object(["providerID": .string("mock"), "id": .string("mock-1")])])
            let info = try await api.send(Endpoint<DataResponse<SessionInfo>>.json(method: .post, path: "/api/session", body: JSONEncoder().encode(body))).data
            store.readPath.seed(info: info, messages: [])
            try await store.readPath.open(info.id)
            let _: DataResponse<InboxItem> = try await api.send(.json(method: .post, path: "/api/session/\(info.id)/prompt", body: JSONEncoder().encode(["text": "Run the live scenario."])))
            if disconnect {
                try await projectionWait { store.sessions[info.id]?.transcript?.snapshot.contains(where: { $0.content.contains { $0.fields.text == "Starting." } }) == true }
                await store.suspend()
            }
            try await api.send(Endpoint<Void>(method: .post, path: "/api/experimental/session/\(info.id)/wait") { _, _ in () })
            if disconnect {
                let count = store.resync?.records.count ?? 0
                await store.start()
                try await projectionWait { (store.resync?.records.count ?? 0) > count && store.resync?.records.last?.succeeded == true }
            } else { try await projectionWait { store.sessions[info.id]?.status == .idle && store.sessions[info.id]?.info.time.idle != nil } }
            let snapshot = try await api.send(ReadEndpoints.messages(info.id, limit: 200, order: .asc))
            let serverInfo = try await api.send(ReadEndpoints.session(info.id)).data
            #expect(store.sessions[info.id]?.transcript?.snapshot.map { $0.raw.omittingNullFields } == snapshot.data.map { $0.raw.omittingNullFields })
            #expect(store.sessions[info.id]?.info.raw.omittingNullFields == serverInfo.raw.omittingNullFields)
            print("PASS Swift projection parity: \(scenario), stream interrupted: \(disconnect)")
        }
        await store.dispose()
    } catch { await store.dispose(); throw error }
}

}

import Foundation
import OCModels
import OCNetworking
import OCPersistence
import OCSecurity

/// The in-app demo: one recorded server played by `ScenarioTransport`, kept in memory only. Nothing is
/// saved, nothing reaches the network, and leaving the demo discards it all.
public enum DemoMode {
    public static let serverName = "Demo server"

    /// A registry for the demo. `fallback` receives any request not meant for the recorded server; tests
    /// pass one that fails, the app passes none (such a request then fails offline).
    @MainActor public static func registry(scenario: DemoScenario? = nil, pacing: Duration = .milliseconds(1),
                                           fallback: (any HTTPTransport)? = nil) async throws -> ServerRegistry {
        let scenario = try scenario ?? DemoScenario.bundled()
        let transport = ScenarioTransport(scenario: scenario, pacing: pacing, fallback: fallback)
        let info = scenario.routes["GET /api/info"].flatMap { try? JSONDecoder().decode(ServerInfo.self, from: JSONEncoder().encode($0)) }
        let record = ServerRecord(name: serverName, endpoints: [EndpointRecord(url: ScenarioTransport.baseURL, kind: .https)], lastInfo: info)
        let credentials = CredentialStore(secrets: InMemorySecretStore())
        try await credentials.save(.password("demo"), for: record.id)
        let clock = NetworkClock()
        let registry = ServerRegistry(records: DemoRecords(records: [record]), credentials: credentials, clock: clock,
            pathMonitor: nil, localNetworkExplained: true, transport: transport,
            fetchInfo: { url, credential, headers in
                try await APIClient(baseURL: url, credential: credential, headers: headers, transport: transport, clock: clock)
                    .send(Endpoint<ServerInfo>.json(path: "/api/info"))
            },
            factory: { record, credential, headers in
                ServerConnection(endpoints: record.endpoints, credential: credential, headers: headers, transport: transport,
                                 clock: clock, pathMonitor: nil, prefersHTTPS: true, allowsLocalNetwork: true)
            })
        await registry.load()
        return registry
    }
}

/// The demo's one server, never written anywhere.
actor DemoRecords: ServerRecordStore {
    private var records: [ServerRecord]
    init(records: [ServerRecord]) { self.records = records }
    nonisolated(nonsending) func load() async throws -> [ServerRecord] { await current() }
    nonisolated(nonsending) func save(_ records: [ServerRecord]) async throws { await replace(records) }
    private func current() -> [ServerRecord] { records }
    private func replace(_ value: [ServerRecord]) { records = value }
}

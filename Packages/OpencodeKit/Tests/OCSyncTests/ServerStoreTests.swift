import Foundation
import Testing
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync

@MainActor @Suite(.serialized) struct ServerStoreTests {
    @Test func exactlyOneResyncPerConnectedSignalAndEventBatchesAreDelivered() async {
        let connection = FakeConnection(), refreshes = RefreshCounter(), sink = PendingServerEventSink()
        let time = SyncTime()
        let store = ServerStore(record: syncRecord(), connection: connection,
                                credentials: CredentialStore(secrets: InMemorySecretStore()), clock: time.clock,
                                eventSink: sink, fetchInfo: { _, _, _ in await refreshes.refresh() })
        let event = ServerEvent.decode(Data(#"{"id":"evt_test","type":"server.connected","data":{}}"#.utf8))
        guard case .connected(let header) = event else { Issue.record("Bad fixture"); return }
        for count in 1...3 {
            await connection.emit(.state(.connected(syncEndpoint.id, since: time.clock.now())))
            store.readPath.client = { emptyReadAPI() }
            await connection.emit(.resyncNeeded(.serverConnected(header)))
            await connection.emit(.events(.init(events: [event])))
            await settle { store.resync?.records.count == count && sink.batchCount == count }
            #expect(await refreshes.count == count)
        }
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.backlogOverflow))
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.oversizedEvent))
        await settle { store.resync?.records.count == 5 }
        #expect(await refreshes.count == 5)
        #expect(store.capabilities.pairing)
        await store.dispose()
    }

    @Test func discoveredEndpointsAndHealthArePersisted() async throws {
        let records = MemoryRecords(), connection = FakeConnection(), time = SyncTime()
        let registry = ServerRegistry(records: records, credentials: CredentialStore(secrets: InMemorySecretStore()),
                                      clock: time.clock, pathMonitor: nil, localNetworkExplained: true,
                                      factory: { _, _, _ in connection })
        await registry.load()
        let server = try await registry.add(syncRecord(), credential: .password("secret"))
        let discovered = URL(string: "https://studio.example.com")!
        let info = ServerInfo(version: "2.0.32", urls: [discovered, URL(string: "http://localhost:4000")!])
        await connection.setSnapshot(.init(resolution: .init(selected: syncEndpoint,
            diagnoses: [syncEndpoint.id: .success(info)]), lastResolvedAt: time.clock.now()))
        await connection.emit(.state(.connected(syncEndpoint.id, since: time.clock.now())))
        await settle { await records.load().first?.endpoints.count == 2 }
        let persisted = await records.load()
        #expect(persisted.first?.endpoints.last?.source == .discovered)
        #expect(persisted.first?.lastInfo == info)
        #expect(server.record.endpoints.first?.stats.lastSuccess == time.clock.date())
        #expect(server.diagnosis(for: syncEndpoint.id) == "Healthy")
        await registry.shutdown()
    }

    @Test func unauthorizedAndV1AreActionableAndTransitionsAreBounded() async {
        let connection = FakeConnection(), time = SyncTime()
        let store = ServerStore(record: syncRecord(), connection: connection,
                                credentials: CredentialStore(secrets: InMemorySecretStore()), clock: time.clock)
        for _ in 0..<60 { await connection.emit(.state(.resolving)) }
        await connection.emit(.state(.incompatible(.v1("1.19.3"))))
        await settle { store.state == .incompatible(.v1("1.19.3")) }
        #expect(store.transitions.count == 50)
        #expect(ServerStatus(state: store.state, endpoints: []).title == "Update opencode")
        await connection.emit(.state(.unauthorized))
        await settle { store.needsRepair }
        #expect(store.state == .unauthorized)
        await store.start()
        #expect(await connection.starts.isEmpty)
        await store.dispose()
    }

    @Test func resync401RequiresRepair() async {
        let connection = FakeConnection()
        let store = ServerStore(record: syncRecord(), connection: connection,
                                credentials: CredentialStore(secrets: InMemorySecretStore()), clock: SyncTime().clock,
                                fetchInfo: { _, _, _ in throw APIError.unauthorized })
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.backlogOverflow))
        await settle { store.resync?.records.count == 1 }
        #expect(store.needsRepair)
        #expect(store.state == .unauthorized)
        #expect(store.resync?.records.first?.succeeded == false)
        await store.dispose()
    }

    @Test func expiryAndDiagnosticsExcludeSecrets() async throws {
        let time = SyncTime(), credentials = CredentialStore(secrets: InMemorySecretStore()), connection = FakeConnection()
        var record = syncRecord()
        record.name = "password-secret"
        record.endpoints[0].url = URL(string: "https://example.com/private-secret")!
        let store = ServerStore(record: record, connection: connection, credentials: credentials, clock: time.clock)
        try await credentials.save(.pairingToken("token-secret", expiresAt: time.clock.date().addingTimeInterval(5 * 86400)), for: record.id)
        await store.start()
        #expect(store.tokenExpiresSoon)
        let exported = store.diagnosticsExport()
        for secret in ["password-secret", "private-secret", "token-secret", "Authorization", "example.com"] {
            #expect(!exported.contains(secret))
        }
        await store.dispose()
    }
}

extension ServerStoreTests {
    @Test func backgroundCancelsRefreshAndIgnoresLateResyncSignals() async {
        let connection = FakeConnection(), time = SyncTime(), counter = RefreshCounter(), sink = PendingServerEventSink()
        let store = ServerStore(record: syncRecord(), connection: connection,
            credentials: CredentialStore(secrets: InMemorySecretStore()), clock: time.clock, eventSink: sink,
            fetchInfo: { _, _, _ in
                let info = await counter.refresh()
                try await time.clock.sleep(.seconds(30))
                return info
            })
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.backlogOverflow))
        await settle { await counter.count == 1 }
        await store.suspend()
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.oversizedEvent))
        await connection.emit(.events(.init(events: [])))
        await settle { sink.batchCount == 1 }
        #expect(await counter.count == 1)
        #expect(store.resync?.isRunning == false)
        #expect(store.resync?.records.isEmpty == true)
        await store.dispose()
    }

    @Test func resyncInfoRefreshPersistsDiscoveryAndCapabilities() async throws {
        let records = MemoryRecords(), connection = FakeConnection()
        let fresh = ServerInfo(version: "2.0.25", urls: [URL(string: "https://fresh.example.com")!],
                               capabilities: .init(persistentPty: true))
        let registry = ServerRegistry(records: records, credentials: CredentialStore(secrets: InMemorySecretStore()),
            clock: SyncTime().clock, pathMonitor: nil, localNetworkExplained: true,
            fetchInfo: { _, _, _ in fresh }, factory: { _, _, _ in connection })
        await registry.load()
        let store = try await registry.add(syncRecord(), credential: .password("secret"))
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.backlogOverflow))
        await settle { store.resync?.records.count == 1 }
        #expect(store.capabilities.pairing && store.capabilities.persistentPty)
        #expect(await records.load().first?.endpoints.last?.url == fresh.urls.first)
        #expect(await records.load().first?.lastInfo == fresh)
        await registry.shutdown()
    }
}

extension ServerStoreTests {
    @Test func laterStateDoesNotOverwriteFreshResyncWithOldResolution() async {
        let connection = FakeConnection(), time = SyncTime()
        let store = ServerStore(record: syncRecord(), connection: connection,
            credentials: CredentialStore(secrets: InMemorySecretStore()), clock: time.clock,
            fetchInfo: { _, _, _ in ServerInfo(version: "2.0.32") })
        await connection.setSnapshot(.init(resolution: .init(selected: syncEndpoint,
            diagnoses: [syncEndpoint.id: .success(ServerInfo(version: "2.0.24"))]), lastResolvedAt: time.clock.now()))
        await connection.emit(.state(.connected(syncEndpoint.id, since: time.clock.now())))
        await settle { store.info?.version == "2.0.24" }
        store.readPath.client = { emptyReadAPI() }
        await connection.emit(.resyncNeeded(.backlogOverflow))
        await settle { store.resync?.records.count == 1 }
        await connection.emit(.state(.waiting(attempt: 1, retryAt: time.clock.now(), failure: .streamClosed)))
        await settle { if case .waiting = store.state { true } else { false } }
        #expect(store.info?.version == "2.0.32")
        #expect(store.capabilities.pairing)
        await store.dispose()
    }
}

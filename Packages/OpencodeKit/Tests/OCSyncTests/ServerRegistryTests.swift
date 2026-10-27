import Foundation
import Testing
import Clocks
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync

@MainActor @Suite(.serialized) struct ServerRegistryTests {
    @Test func coldNotificationActionUsesLastHealthyEnabledEndpoint() async throws {
        let records = MemoryRecords()
        var record = syncRecord()
        let healthy = EndpointRecord(url: try #require(URL(string: "https://healthy.example.invalid")), kind: .https,
            stats: .init(lastSuccess: Date(timeIntervalSince1970: 100)))
        let disabled = EndpointRecord(url: try #require(URL(string: "https://disabled.example.invalid")), kind: .https,
            isEnabled: false, stats: .init(lastSuccess: Date(timeIntervalSince1970: 200)))
        record.endpoints += [healthy, disabled]
        await records.save([record])
        let registry = ServerRegistry(records: records, credentials: CredentialStore(secrets: InMemorySecretStore()),
            pathMonitor: nil, factory: { _, _, _ in FakeConnection() })
        await registry.load()
        let client = try await registry.directActions(for: #require(registry.servers.first))
        #expect(client.endpoints == [healthy.url, syncEndpoint.url])
        await registry.shutdown()
    }

    @Test func persistenceRoundTripRenameOrderAndKeychainRemoval() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = JSONServerRecordStore(url: directory.appending(path: "servers.json"))
        let secrets = InMemorySecretStore(), credentials = CredentialStore(secrets: secrets)
        let registry = ServerRegistry(records: records, credentials: credentials, pathMonitor: nil,
                                      factory: { _, _, _ in FakeConnection() })
        await registry.load()
        let first = try await registry.add(syncRecord(), credential: .password("never-in-json"))
        let second = try await registry.add(syncRecord(), credential: .password("also-secret"))
        try await registry.rename(first, to: "Home")
        #expect(try await records.load().map(\.id) == [first.id, second.id])
        let data = try Data(contentsOf: directory.appending(path: "servers.json"))
        #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
        #expect(!String(decoding: data, as: UTF8.self).contains("never-in-json"))
        let restored = ServerRegistry(records: records, credentials: credentials, pathMonitor: nil,
                                      factory: { _, _, _ in FakeConnection() })
        await restored.load()
        #expect(restored.servers.map(\.record.name) == ["Home", "Studio"])
        try await registry.remove(first)
        #expect(try await credentials.credential(for: first.id) == nil)
        #expect(try await credentials.credential(for: second.id) == .password("also-secret"))
        #expect(try await records.load().map(\.id) == [second.id])
        await registry.shutdown(); await restored.shutdown()
    }

    @Test(arguments: [19, 20, 21, 60, 61]) func foregroundThresholds(seconds: Int) async throws {
        let time = SyncTime(), connection = FakeConnection(), background = FakeBackground()
        let registry = ServerRegistry(records: MemoryRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()),
                                      clock: time.clock, background: background, pathMonitor: nil, localNetworkExplained: true,
                                      factory: { _, _, _ in connection })
        await registry.load()
        _ = try await registry.add(syncRecord(), credential: .password("secret"))
        await registry.setScenePhase(.active)
        await connection.setSnapshot(.init(lastActivity: time.clock.now(), lastResolvedAt: time.clock.now()))
        await registry.setScenePhase(.background)
        #expect(await connection.stops == 1)
        #expect(background.starts == 1 && background.ends == [1])
        background.expiration?() // Expiration cannot end an already ended task twice.
        #expect(background.ends == [1])
        await time.test.advance(by: .seconds(seconds))
        await registry.setScenePhase(.active)
        #expect(await connection.starts.last == (seconds > 60))
        let reconnects = await connection.reconnects
        #expect(reconnects.count == (seconds > 20 ? 1 : 0))
        if let reconnect = reconnects.first {
            #expect(reconnect.0 == .foreground && reconnect.1 == (seconds > 60))
        }
        await registry.shutdown()
    }

    @Test func pathChangeInBackgroundForcesRaceAndActiveChangesDebounce() async throws {
        let time = SyncTime(), connection = FakeConnection()
        let registry = ServerRegistry(records: MemoryRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()),
                                      clock: time.clock, pathMonitor: nil, localNetworkExplained: true,
                                      factory: { _, _, _ in connection })
        await registry.load()
        _ = try await registry.add(syncRecord(), credential: .password("secret"))
        registry.networkPathChanged(.init(interfaces: ["en0"]))
        await registry.setScenePhase(.active)
        await connection.setSnapshot(.init(lastActivity: time.clock.now(), lastResolvedAt: time.clock.now()))
        await registry.setScenePhase(.background)
        registry.networkPathChanged(.init(interfaces: ["pdp_ip0"]))
        await registry.setScenePhase(.active)
        #expect(await connection.starts.last == true)
        registry.networkPathChanged(.init(interfaces: ["en0"]))
        await time.test.advance(by: .milliseconds(499))
        #expect(await connection.reconnects.isEmpty)
        await time.test.advance(by: .milliseconds(1))
        await settle { await connection.reconnects.count == 1 }
        let reconnect = await connection.reconnects.first
        #expect(reconnect?.0 == .networkPathChanged && reconnect?.1 == true)
        await registry.shutdown()
    }

    @Test func localNetworkGatePrecedesAnyLANConnection() async throws {
        let connection = FakeConnection()
        let registry = ServerRegistry(records: MemoryRecords(), credentials: CredentialStore(secrets: InMemorySecretStore()),
                                      pathMonitor: nil, factory: { _, _, _ in connection })
        await registry.load(); await registry.setScenePhase(.active)
        _ = try await registry.add(syncRecord(), credential: .password("secret"))
        #expect(await connection.starts.isEmpty)
        #expect(registry.requiresLocalNetworkExplanation)
        await registry.acknowledgeLocalNetwork()
        #expect(await connection.starts.count == 1)
        await registry.shutdown()
    }
}

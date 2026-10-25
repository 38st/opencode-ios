import Foundation
import Testing
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync

@MainActor @Suite struct ConnectionNoticeTests {
    @Test func healthyAndConnectingStatesShowNoBanner() {
        let now = ContinuousClock.now
        #expect(ConnectionNotice(state: .connected(syncEndpoint.id, since: now), endpoints: [syncEndpoint]) == nil)
        #expect(ConnectionNotice(state: .idle, endpoints: []) == nil)
        #expect(ConnectionNotice(state: .resolving, endpoints: []) == nil)
        #expect(ConnectionNotice(state: .connecting(attempt: 2), endpoints: []) == nil)
        #expect(!ConnectionNotice.isOffline(.connecting(attempt: 2)))
    }

    @Test func offlineStatesExplainAndOfferRecovery() throws {
        let now = ContinuousClock.now
        let waiting = try #require(ConnectionNotice(state: .waiting(attempt: 3, retryAt: now.advanced(by: .seconds(12)), failure: .timeout),
                                                    endpoints: [], now: now))
        #expect(waiting.title == "Offline · showing saved messages")
        #expect(waiting.detail == "Retrying in 12s · Attempt 3 · " + ConnectionFailure.timeout.message)
        #expect(waiting.action == .reconnect && waiting.actionTitle == "Reconnect now")
        #expect(ConnectionNotice(state: .unauthorized, endpoints: [])?.action == .repair)
        #expect(ConnectionNotice(state: .incompatible(.v1("1.19.3")), endpoints: [])?.title == "Update opencode · showing saved messages")
        #expect(ConnectionNotice(state: .serviceStarting(.seconds(2)), endpoints: [])?.action == nil)
        #expect(ConnectionNotice.isOffline(.suspended) && ConnectionNotice.isOffline(.unauthorized))
    }

    @Test func aFailedResyncIsVisibleWhileConnected() {
        let notice = ConnectionNotice(state: .connected(syncEndpoint.id, since: .now), endpoints: [syncEndpoint], lastResyncFailed: true)
        #expect(notice?.action == .refresh)
        #expect(notice?.identifier == "connected")
    }

    @Test func storeMarksItsReadPathOfflineUntilReconnected() async {
        let connection = FakeConnection(), time = SyncTime()
        let store = ServerStore(record: syncRecord(), connection: connection,
                                credentials: CredentialStore(secrets: InMemorySecretStore()), clock: time.clock)
        await connection.emit(.state(.waiting(attempt: 1, retryAt: time.clock.now(), failure: .transport)))
        await settle { store.readPath.offline }
        #expect(store.connectionNotice?.action == .reconnect)
        await connection.emit(.state(.connecting(attempt: 2)))
        await settle { store.state == .connecting(attempt: 2) }
        // Connecting between retries is not yet reachable, but the last known state stays as it was.
        #expect(!store.readPath.offline)
        await connection.emit(.state(.connected(syncEndpoint.id, since: time.clock.now())))
        await settle { if case .connected = store.state { true } else { false } }
        #expect(!store.readPath.offline && store.connectionNotice == nil)
        await store.dispose()
    }
}

@MainActor @Suite struct NewSessionTargetTests {
    let a = ServerID(), b = ServerID()

    @Test func homeProjectWinsOverTheOpenSession() {
        let target = NewSessionTarget.resolve(servers: [a, b], chosenServer: nil, homeServer: nil,
                                              homeProject: b.rawValue.uuidString + ":repo", origin: .init(serverID: a, projectID: "other"))
        #expect(target == .init(serverID: b, projectID: "repo"))
    }

    @Test func homeServerWinsOverTheOpenSessionsServer() {
        let target = NewSessionTarget.resolve(servers: [a, b], chosenServer: nil, homeServer: a, homeProject: nil,
                                              origin: .init(serverID: b, projectID: "repo"))
        #expect(target == .init(serverID: a))
        let same = NewSessionTarget.resolve(servers: [a, b], chosenServer: nil, homeServer: b, homeProject: nil,
                                            origin: .init(serverID: b, projectID: "repo"))
        #expect(same == .init(serverID: b, projectID: "repo"))
    }

    @Test func fallsBackToTheOpenSessionThenTheFirstServer() {
        #expect(NewSessionTarget.resolve(servers: [a, b], chosenServer: nil, homeServer: nil, homeProject: nil,
                                         origin: .init(serverID: b, projectID: "repo")) == .init(serverID: b, projectID: "repo"))
        #expect(NewSessionTarget.resolve(servers: [a, b], chosenServer: nil, homeServer: nil, homeProject: nil, origin: nil) == .init(serverID: a))
        #expect(NewSessionTarget.resolve(servers: [], chosenServer: nil, homeServer: nil, homeProject: nil, origin: nil) == nil)
    }

    @Test func aServerPickedInNewSessionKeepsOnlyItsOwnProject() {
        let project = a.rawValue.uuidString + ":repo"
        #expect(NewSessionTarget.resolve(servers: [a, b], chosenServer: b, homeServer: nil, homeProject: project, origin: nil) == .init(serverID: b))
        #expect(NewSessionTarget.resolve(servers: [a, b], chosenServer: a, homeServer: nil, homeProject: project, origin: nil) == .init(serverID: a, projectID: "repo"))
    }

    @Test func removedServersAndMalformedFiltersAreIgnored() {
        let removed = ServerID()
        #expect(NewSessionTarget.resolve(servers: [a], chosenServer: removed, homeServer: removed,
                                         homeProject: removed.rawValue.uuidString + ":repo", origin: .init(serverID: removed)) == .init(serverID: a))
        #expect(NewSessionTarget.resolve(servers: [a], chosenServer: nil, homeServer: nil, homeProject: "not-a-uuid:repo", origin: nil) == .init(serverID: a))
    }
}

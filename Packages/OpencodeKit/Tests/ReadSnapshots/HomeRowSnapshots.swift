#if os(iOS)
import Foundation
import Testing
import SwiftUI
import OCModels
import OCFoundation
import OCNetworking
import OCSecurity
@testable import OCSync
import FeatureInbox

extension ReadPerformanceTests.Snapshots {
    @Test func homeRows() async throws {
        for state in ["needs-you", "failed", "running", "unread", "syncing", "idle", "offline", "offline-running"] {
            let connection = SnapshotConnection()
            let endpoint = EndpointRecord(url: try #require(URL(string: "https://studio.example.com")), kind: .https)
            let server = ServerStore(record: .init(name: "Studio Mac", endpoints: [endpoint]), connection: connection,
                credentials: CredentialStore(secrets: InMemorySecretStore()), fetchInfo: { _, _, _ in .init(version: "2.0.32") })
            server.readPath.client = nil
            let offline = state.hasPrefix("offline")
            await connection.emit(.state(offline ? .waiting(attempt: 2, retryAt: .now, failure: .transport) : .connected(endpoint.id, since: .now)))
            for _ in 0..<20 { await Task.yield() }
            if state != "syncing" { server.readPath.confirmStatus() }
            let unread = ["failed", "unread"].contains(state)
            let info = SessionInfo(raw: .object([
                "id": .string("session"), "projectID": .string("project"), "title": .string("Review the session implementation"),
                "location": .object(["directory": .string("/work/opencode-ios")]), "cost": .number(1.24),
                "outcome": .string(state == "failed" ? "failed" : "succeeded"),
                "time": .object(["idle": .integer(100), "viewed": .integer(unread ? 0 : 100)])
            ]))
            server.readPath.seed(info: info)
            if state == "needs-you" {
                server.readPath.permissions[info.id] = [.init(raw: .object(["id": .string("permission"), "sessionID": .string(info.id)]))]
            }
            if state.hasSuffix("running") { server.readPath.running.insert(info.id) }
            if state == "unread" { try await server.readPath.setLocalMeta(.init(pinned: true), sessionID: info.id) }
            let session = try #require(server.sessions[info.id])
            await capture(HomeSessionRow(item: .init(server: server, session: session))
                .transaction { $0.disablesAnimations = true }, name: "home-" + state, height: 600)
            await server.dispose()
        }
    }
}

private actor SnapshotConnection: ConnectionControlling {
    nonisolated let output: AsyncStream<ConnectionOutput>
    let continuation: AsyncStream<ConnectionOutput>.Continuation
    init() { (output, continuation) = AsyncStream.makeStream() }
    func start(rerace: Bool) {}
    func stop() {}
    func forceReconnect(_ reason: ReconnectReason, rerace: Bool) {}
    func snapshot() -> ConnectionSnapshot { .init() }
    func configure(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String]) {}
    func setNetworkPath(_ path: NetworkPathStatus) {}
    func updateEndpoints(_ endpoints: [EndpointRecord]) {}
    func allowLocalNetwork() {}
    func emit(_ value: ConnectionOutput) { continuation.yield(value) }
}
#endif

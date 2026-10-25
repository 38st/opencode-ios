import Foundation
import OCModels

/// The connection problem shown outside Settings: a banner on Home and in the session screen.
/// Nil while the server is connected and its last resync succeeded, and during the brief
/// connecting states, so a healthy launch never flashes a banner.
public struct ConnectionNotice: Equatable, Sendable {
    public enum Action: Sendable { case reconnect, refresh, repair, details }
    public var title: String
    public var detail: String?
    public var action: Action?
    /// Changes only when the kind of problem changes, not with the retry countdown.
    public let identifier: String
    public var actionTitle: String? {
        switch action {
        case .reconnect: "Reconnect now"
        case .refresh: "Retry"
        case .repair: "Pair again"
        case .details: "View details"
        case nil: nil
        }
    }
    public init?(state: ConnectionState, endpoints: [EndpointRecord], lastResyncFailed: Bool = false, now: ContinuousClock.Instant = .now) {
        identifier = state.diagnosticName
        let status = ServerStatus(state: state, endpoints: endpoints, now: now)
        switch state {
        case .connected:
            guard lastResyncFailed else { return nil }
            title = "Could not refresh · showing saved messages"; action = .refresh
        case .idle, .resolving, .connecting: return nil
        case .waiting:
            title = "Offline · showing saved messages"
            detail = status.title + (status.detail.map { " · " + $0 } ?? ""); action = .reconnect
        case .unauthorized:
            title = "Needs re-pairing · showing saved messages"; action = .repair
        case .incompatible:
            title = status.title + " · showing saved messages"; action = .details
        case .serviceStarting:
            title = "Server starting · showing saved messages"
        case .suspended:
            title = "Paused · showing saved messages"; action = .reconnect
        }
    }
    /// Whether running and working indicators should be shown as last known rather than live.
    public static func isOffline(_ state: ConnectionState) -> Bool {
        switch state {
        case .connected, .idle, .resolving, .connecting: false
        case .waiting, .unauthorized, .incompatible, .serviceStarting, .suspended: true
        }
    }
}

public extension ServerStore {
    var connectionNotice: ConnectionNotice? { notice(now: .now) }
    func notice(now: ContinuousClock.Instant) -> ConnectionNotice? {
        let lastResyncFailed = resync.map { !$0.isRunning && $0.records.last?.succeeded == false } ?? false
        return ConnectionNotice(state: state, endpoints: record.endpoints, lastResyncFailed: lastResyncFailed, now: now)
    }
    /// Runs the notice's action that needs no UI: reconnecting or refreshing.
    func perform(_ action: ConnectionNotice.Action) async {
        switch action {
        case .reconnect, .refresh: await reconnect()
        case .repair, .details: break
        }
    }
}

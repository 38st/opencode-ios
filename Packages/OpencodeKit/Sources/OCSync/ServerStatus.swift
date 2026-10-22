import Foundation
import OCModels

public struct ServerStatus: Equatable, Sendable {
    public enum Tone: Sendable { case good, progress, warning, neutral }
    public var title: String
    public var detail: String?
    public var symbol: String
    public var tone: Tone
    public let stateIdentifier: String
    public init(state: ConnectionState, endpoints: [EndpointRecord], now: ContinuousClock.Instant = .now) {
        stateIdentifier = state.diagnosticName
        detail = nil
        switch state {
        case .connected(let id, _):
            let kind = endpoints.first { $0.id == id }?.kind
            title = "Connected · \(kind?.label ?? "Server")"; symbol = "checkmark.circle.fill"; tone = .good
        case .idle, .resolving, .connecting:
            title = "Connecting"; symbol = "arrow.triangle.2.circlepath"; tone = .progress
        case .waiting(let count, let retryAt, let failure):
            let remaining = now.duration(to: retryAt)
            let seconds = max(0, Int(ceil(Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18)))
            title = "Retrying in \(seconds)s"; detail = "Attempt \(count) · \(failure.message)"
            symbol = "arrow.clockwise"; tone = .warning
        case .unauthorized:
            title = "Needs re-pairing"; symbol = "key.fill"; tone = .warning
        case .incompatible(.notOpencode):
            title = "Not an opencode server"; symbol = "exclamationmark.triangle.fill"; tone = .warning
        case .incompatible:
            title = "Update opencode"; symbol = "arrow.up.circle.fill"; tone = .warning
        case .serviceStarting:
            title = "Starting"; symbol = "hourglass"; tone = .progress
        case .suspended:
            title = "Paused"; symbol = "pause.circle.fill"; tone = .neutral
        }
    }
}

public extension ConnectionState {
    /// Stable state names for diagnostics and accessibility automation, independent of display wording.
    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .resolving: "resolving"
        case .connecting: "connecting"
        case .connected: "connected"
        case .waiting: "waiting"
        case .suspended: "suspended"
        case .serviceStarting: "serviceStarting"
        case .unauthorized: "unauthorized"
        case .incompatible: "incompatible"
        }
    }
}

public extension EndpointKind {
    var label: String {
        switch self {
        case .lan: "LAN"
        case .tailnet: "Tailscale"
        case .tunnel: "Tunnel"
        case .https: "HTTPS"
        case .ssh: "SSH"
        case .unknown: "Server"
        }
    }
}

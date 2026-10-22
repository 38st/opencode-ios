import Foundation

public enum ConnectionFailure: String, Error, Codable, Sendable, Equatable {
    case localNetworkDenied, dnsFailure, tlsError, timeout, unauthorized
    case insecureRemote, invalidURL, transport, firstFrameTimeout, invalidFirstFrame
    case watchdog, streamClosed, backlogOverflow, notOpencode, cancelled, unknown

    public var message: String {
        switch self {
        case .insecureRemote: "Plain HTTP is only supported for local networking. Use an HTTPS URL for this host."
        case .localNetworkDenied: "Allow Local Network access in Settings."
        case .dnsFailure: "The hostname could not be resolved. Check DNS and tunnel domain blocking."
        case .tlsError: "The server's TLS connection could not be verified."
        case .unauthorized: "Authentication failed. Pair with the server again."
        case .timeout: "The server did not respond in time."
        case .invalidURL: "Check the server URL."
        case .transport: "The server could not be reached. Check the address and network."
        case .firstFrameTimeout: "The server did not open its event stream in time."
        case .invalidFirstFrame: "The server sent an unexpected first event."
        case .watchdog: "The event stream stopped responding."
        case .streamClosed: "The server closed the event stream."
        case .backlogOverflow: "Catching up after too many events."
        case .notOpencode: "This address is not an opencode server."
        case .cancelled: "The connection was cancelled."
        case .unknown: "An unknown connection error occurred."
        }
    }
}

public enum ReconnectReason: String, Sendable, Equatable {
    case networkPathChanged, foreground, userRequested, backlogOverflow, unknown
}

public enum ConnectionState: Sendable, Equatable {
    case idle, resolving, connecting(attempt: Int)
    case connected(EndpointID, since: ContinuousClock.Instant)
    case waiting(attempt: Int, retryAt: ContinuousClock.Instant, failure: ConnectionFailure)
    case suspended, serviceStarting(Duration), unauthorized, incompatible(ProbeOutcome)
}

public struct StateTransition: Sendable, Equatable {
    public let state: ConnectionState
    public let at: ContinuousClock.Instant
    public init(state: ConnectionState, at: ContinuousClock.Instant) { self.state = state; self.at = at }
}

public enum ResyncReason: Sendable, Equatable {
    case serverConnected(EventHeader), backlogOverflow, oversizedEvent
}

public struct EventBatch: Sendable, Equatable {
    public let events: [ServerEvent]
    public init(events: [ServerEvent]) { self.events = events }
}

public enum ConnectionOutput: Sendable, Equatable {
    case state(ConnectionState)
    case events(EventBatch)
    case resyncNeeded(ResyncReason)
}

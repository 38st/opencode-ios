import Foundation

public enum ConnectionFailure: String, Error, Codable, Sendable, Equatable {
    case localNetworkDenied, dnsFailure, tlsError, timeout, unauthorized
    case insecureRemote, invalidURL, transport, firstFrameTimeout, invalidFirstFrame
    case watchdog, streamClosed, backlogOverflow, notOpencode, cancelled, unknown

    public var message: String {
        switch self {
        case .insecureRemote: localized("Plain HTTP is only supported for local networking. Use an HTTPS URL for this host.")
        case .localNetworkDenied: localized("Allow Local Network access in Settings.")
        case .dnsFailure: localized("The hostname could not be resolved. Check DNS and tunnel domain blocking.")
        case .tlsError: localized("The server's TLS connection could not be verified.")
        case .unauthorized: localized("Authentication failed. Pair with the server again.")
        case .timeout: localized("The server did not respond in time.")
        case .invalidURL: localized("Check the server URL.")
        case .transport: localized("The server could not be reached. Check the address and network.")
        case .firstFrameTimeout: localized("The server did not open its event stream in time.")
        case .invalidFirstFrame: localized("The server sent an unexpected first event.")
        case .watchdog: localized("The event stream stopped responding.")
        case .streamClosed: localized("The server closed the event stream.")
        case .backlogOverflow: localized("Catching up after too many events.")
        case .notOpencode: localized("This address is not an opencode server.")
        case .cancelled: localized("The connection was cancelled.")
        case .unknown: localized("An unknown connection error occurred.")
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

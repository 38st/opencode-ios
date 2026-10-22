import Foundation
import OCModels

public struct ConnectionSnapshot: Sendable {
    public var resolution: EndpointResolution?
    public var lastActivity: ContinuousClock.Instant?
    public var lastResolvedAt: ContinuousClock.Instant?
    public init(resolution: EndpointResolution? = nil, lastActivity: ContinuousClock.Instant? = nil,
                lastResolvedAt: ContinuousClock.Instant? = nil) {
        self.resolution = resolution; self.lastActivity = lastActivity; self.lastResolvedAt = lastResolvedAt
    }
}

/// The app owns lifecycle policy; the connection owns transport and retry policy.
public protocol ConnectionControlling: Sendable {
    var output: AsyncStream<ConnectionOutput> { get }
    func start(rerace: Bool) async
    func stop() async
    func forceReconnect(_ reason: ReconnectReason, rerace: Bool) async
    func snapshot() async -> ConnectionSnapshot
    func configure(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String]) async
    func setNetworkPath(_ path: NetworkPathStatus) async
    func updateEndpoints(_ endpoints: [EndpointRecord]) async
    func allowLocalNetwork() async
}

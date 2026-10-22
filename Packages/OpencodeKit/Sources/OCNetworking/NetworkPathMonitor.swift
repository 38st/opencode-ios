import Foundation
import Network

public struct NetworkPathStatus: Sendable, Equatable {
    public var isSatisfied: Bool
    public var localNetworkDenied: Bool
    public var isExpensive: Bool
    public var isConstrained: Bool
    public var interfaces: [String]
    public init(isSatisfied: Bool = true, localNetworkDenied: Bool = false, isExpensive: Bool = false,
                isConstrained: Bool = false, interfaces: [String] = []) {
        self.isSatisfied = isSatisfied; self.localNetworkDenied = localNetworkDenied
        self.isExpensive = isExpensive; self.isConstrained = isConstrained; self.interfaces = interfaces
    }
}

public protocol NetworkPathMonitoring: Sendable {
    func updates() -> AsyncStream<NetworkPathStatus>
}

/// ServerConnection owns the subscription and its 500 ms debounce task.
public struct NetworkPathMonitor: NetworkPathMonitoring {
    public init() {}
    public func updates() -> AsyncStream<NetworkPathStatus> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(NetworkPathStatus(isSatisfied: path.status == .satisfied,
                    localNetworkDenied: path.status == .unsatisfied && path.unsatisfiedReason == .localNetworkDenied,
                    isExpensive: path.isExpensive, isConstrained: path.isConstrained,
                    interfaces: path.availableInterfaces.map(\.name).sorted()))
            }
            continuation.onTermination = { @Sendable _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "app.opencode.path"))
        }
    }
}

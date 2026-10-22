import Foundation
import OCFoundation
import OCModels

public enum EndpointDiagnosis: Sendable, Equatable {
    case success(ServerInfo), failure(ConnectionFailure), starting(Duration), incompatible(ProbeOutcome), notSelected
}
public struct EndpointResolution: Sendable {
    public let selected: EndpointRecord?
    public let diagnoses: [EndpointID: EndpointDiagnosis]
    public let discovered: [EndpointRecord]
    public init(selected: EndpointRecord?, diagnoses: [EndpointID: EndpointDiagnosis], discovered: [EndpointRecord] = []) {
        self.selected = selected; self.diagnoses = diagnoses; self.discovered = discovered
    }
}
public protocol EndpointResolving: Sendable {
    func resolve(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String],
                 localNetworkDenied: Bool) async -> EndpointResolution
}

public actor EndpointResolver: EndpointResolving {
    private let probe: ServerProbe
    private let clock: NetworkClock
    private let prefersHTTPS: Bool
    public init(transport: any HTTPTransport = URLSessionTransport(), clock: NetworkClock = .init(), serverClock: ServerClock = .init(), prefersHTTPS: Bool = false) {
        self.probe = ServerProbe(transport: transport, clock: clock, serverClock: serverClock); self.clock = clock
        self.prefersHTTPS = prefersHTTPS
    }
    private func rank(_ endpoint: EndpointRecord) -> Int {
        endpoint.kind.rank + (prefersHTTPS && endpoint.url.scheme != "https" ? 10 : 0)
    }
    private enum Result: Sendable { case probe(EndpointRecord, ProbeOutcome), deadline }
    public func resolve(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String] = [:],
                        localNetworkDenied: Bool = false) async -> EndpointResolution {
        let enabled = endpoints.filter(\.isEnabled)
        return await withTaskGroup(of: Result.self) { group in
            for endpoint in enabled {
                group.addTask { [probe] in
                    .probe(endpoint, await probe.probe(endpoint: endpoint.url, credential: credential, headers: headers,
                                                       timeout: endpoint.kind == .lan ? .seconds(2) : .seconds(6)))
                }
            }
            var selected: EndpointRecord?
            var diagnoses: [EndpointID: EndpointDiagnosis] = [:]
            var discovered: [EndpointRecord] = []
            var remaining = enabled.count
            while let result = await group.next() {
                if Task.isCancelled { break }
                switch result {
                case .deadline: group.cancelAll(); return finish()
                case .probe(let endpoint, let outcome):
                    remaining -= 1
                    switch outcome {
                    case .v2(let info):
                        diagnoses[endpoint.id] = .success(info)
                        if selected == nil {
                            group.addTask { [clock] in
                                try? await clock.sleep(.milliseconds(500)); return .deadline
                            }
                        }
                        if selected == nil || rank(endpoint) < (selected.map(rank) ?? Int.max) { selected = endpoint }
                        for url in info.urls where !EndpointPolicy.isLoopback(url) && !endpoints.contains(where: { $0.url == url })
                            && !discovered.contains(where: { $0.url == url }) {
                            guard (try? EndpointPolicy.validate(url)) != nil else { continue }
                            discovered.append(EndpointRecord(url: url, kind: EndpointPolicy.classify(url), source: .discovered))
                        }
                    case .unauthorized: diagnoses[endpoint.id] = .failure(.unauthorized)
                    case .v2Starting(let delay): diagnoses[endpoint.id] = .starting(delay)
                    case .failure(let failure):
                        let denied = localNetworkDenied && endpoint.kind == .lan && [.transport, .timeout].contains(failure)
                        diagnoses[endpoint.id] = .failure(denied ? .localNetworkDenied : failure)
                    case .notOpencode: diagnoses[endpoint.id] = .failure(.notOpencode)
                    default: diagnoses[endpoint.id] = .incompatible(outcome)
                    }
                    if remaining == 0 { group.cancelAll(); return finish() }
                }
            }
            group.cancelAll()
            return finish()
            func finish() -> EndpointResolution {
                for endpoint in enabled where diagnoses[endpoint.id] == nil { diagnoses[endpoint.id] = .notSelected }
                return EndpointResolution(selected: selected, diagnoses: diagnoses, discovered: discovered)
            }
        }
    }
}

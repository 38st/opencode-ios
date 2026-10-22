import Foundation
import OCFoundation
import OCModels

public struct ServerProbe: Sendable {
    private let transport: any HTTPTransport
    private let clock: NetworkClock
    public let serverClock: ServerClock
    public init(transport: any HTTPTransport = URLSessionTransport(), clock: NetworkClock = .init(),
                serverClock: ServerClock = .init()) {
        self.transport = transport; self.clock = clock; self.serverClock = serverClock
    }
    public func probe(endpoint: URL, credential: Credential? = nil, headers: [String: String] = [:],
                      timeout: Duration = .seconds(6)) async -> ProbeOutcome {
        do {
            return try await withTimeout(timeout, clock: clock) {
                let sent = clock.date()
                let request = try APIClient.request(baseURL: endpoint, path: "/api/info", credential: credential,
                                                    headers: headers, timeout: timeout.seconds)
                let result = try await transport.send(request)
                let response = result.response
                if let date = response.value(forHTTPHeaderField: "Date") {
                    serverClock.observe(httpDate: date, requestSentAt: sent, responseReceivedAt: clock.date())
                }
                if response.statusCode == 503 { return .v2Starting(retryAfter: APIClient.retryAfter(response, now: clock.date())) }
                let isJSON = response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true
                if response.statusCode == 401,
                   isJSON, let raw = try? JSONDecoder().decode([String: JSONValue].self, from: result.data),
                   raw["_tag"] == .string("UnauthorizedError") { return .unauthorized(.v2) }
                if response.statusCode == 200 && isJSON {
                    guard let info = try? JSONDecoder().decode(ServerInfo.self, from: result.data),
                          SemVer(info.version) != nil else { return .notOpencode }
                    return info.isSupported ? .v2(info) : .unsupportedV2(info)
                }
                if response.statusCode == 404 || response.statusCode == 401 || (response.statusCode == 200 && !isJSON) {
                    return try await probeV1(endpoint: endpoint, credential: credential, headers: headers)
                }
                return .notOpencode
            }
        } catch { return .failure(diagnose(error)) }
    }
    private func probeV1(endpoint: URL, credential: Credential?, headers: [String: String]) async throws -> ProbeOutcome {
        struct Health: Decodable { let healthy: Bool; let version: String }
        let request = try APIClient.request(baseURL: endpoint, path: "/global/health", credential: credential, headers: headers)
        let result = try await transport.send(request)
        guard result.response.statusCode == 200,
              result.response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              let health = try? JSONDecoder().decode(Health.self, from: result.data) else { return .notOpencode }
        return .v1(health.version)
    }
}

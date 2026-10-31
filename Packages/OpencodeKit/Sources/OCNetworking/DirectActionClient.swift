import Foundation
import OCFoundation
import OCModels

public enum ActionDeadline: Error, Sendable { case exceeded }

/// The operation and its transport must cooperate with cancellation. URLSessionTransport does.
public func withActionDeadline<T: Sendable>(seconds: Duration, clock: NetworkClock = .init(),
    operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await clock.sleep(seconds); try Task.checkCancellation(); throw ActionDeadline.exceeded }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw CancellationError() }
        return result
    }
}

/// Race only read-only probes. The selected endpoint alone receives the reply, with no POST retry.
public struct DirectActionClient: Sendable {
    public let endpoints: [URL]
    public let credential: Credential?
    public let headers: [String: String]
    private let transport: any HTTPTransport
    private let clock: NetworkClock
    public init(endpoints: [URL], credential: Credential?, headers: [String: String] = [:],
                transport: any HTTPTransport = URLSessionTransport(), clock: NetworkClock = .init()) {
        self.endpoints = endpoints; self.credential = credential; self.headers = headers
        self.transport = transport; self.clock = clock
    }
    /// Encrypted endpoints are tried first; the credential goes over plain HTTP only when none of them answers.
    public func connect() async throws -> DirectActionSession {
        let encrypted = endpoints.filter(EndpointPolicy.isEncrypted), plain = endpoints.filter { !EndpointPolicy.isEncrypted($0) }
        guard !encrypted.isEmpty, !plain.isEmpty else { return try await connect(endpoints) }
        do { return try await connect(encrypted) }
        catch { try Task.checkCancellation() }
        return try await connect(plain)
    }
    /// The first endpoint (the last one that worked) for 3 seconds, then a race of the others.
    private func connect(_ endpoints: [URL]) async throws -> DirectActionSession {
        guard let first = endpoints.first else { throw APIError.refused(.invalidURL) }
        do { return try await withActionDeadline(seconds: .seconds(3), clock: clock) { try await probe(first) } }
        catch { try Task.checkCancellation() }
        return try await withThrowingTaskGroup(of: DirectActionSession?.self) { group in
            for url in endpoints.dropFirst() { group.addTask { try? await probe(url) } }
            while let result = try await group.next() {
                if let result { group.cancelAll(); return result }
            }
            throw APIError.transport(URLError(.cannotConnectToHost))
        }
    }
    private func probe(_ url: URL) async throws -> DirectActionSession {
        let session = DirectActionSession(url: url, credential: credential, headers: headers, transport: transport)
        _ = try await session.request(path: "/api/info")
        return session
    }
}

public struct DirectActionSession: Sendable {
    public let url: URL
    let credential: Credential?
    let headers: [String: String]
    let transport: any HTTPTransport
    public func request(path: String, method: HTTPMethod = .get, body: JSONValue? = nil) async throws -> JSONValue {
        let request = try APIClient.request(baseURL: url, path: path, method: method,
            body: try body.map { try JSONEncoder().encode($0) }, credential: credential, headers: headers, timeout: 10)
        let result = try await transport.send(request)
        try Task.checkCancellation()
        try APIClient.validate(result.response, data: result.data, now: .now)
        if method != .get {
            guard result.response.statusCode == 204 else { throw APIError.decoding("Reply was not acknowledged") }
            return .null
        }
        let json = try JSONDecoder().decode(JSONValue.self, from: result.data)
        return json["data"] ?? json
    }
}

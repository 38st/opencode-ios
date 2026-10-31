import Foundation
import OCFoundation

/// The relay could not be reached, or did not answer within the client's deadline.
public enum PushRelayError: Error, Equatable, Sendable { case unreachable }

/// A relay answer with its status kept, for callers that act on specific refusals.
public struct RelayReply: Sendable, Equatable {
    public let status: Int
    public let body: JSONValue
    public init(status: Int, body: JSONValue) { self.status = status; self.body = body }
    /// The relay's `{"error": code}`, if any.
    public var error: String? { body["error"]?.stringValue }
}

public struct PushRelayClient: Sendable {
    public let url: URL
    private let transport: any HTTPTransport
    private let requestTimeout: Duration
    private let resourceTimeout: Duration
    private let clock: NetworkClock
    /// `requestTimeout` bounds idle time on the connection; `resourceTimeout` bounds the whole exchange,
    /// so a relay that accepts the connection and never answers cannot hold registration open.
    public init(url: URL, transport: any HTTPTransport = URLSessionTransport(),
                requestTimeout: Duration = .seconds(15), resourceTimeout: Duration = .seconds(30), clock: NetworkClock = .init()) {
        self.url = url; self.transport = transport
        self.requestTimeout = requestTimeout; self.resourceTimeout = resourceTimeout; self.clock = clock
    }
    public func request(_ method: HTTPMethod, path: String, secret: String? = nil, body: JSONValue? = nil) async throws -> JSONValue {
        var request = try APIClient.request(baseURL: url, path: path, method: method,
            body: try body.map { try JSONEncoder().encode($0) }, timeout: requestTimeout.seconds)
        if let secret { request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization") }
        let result: HTTPResponse
        do {
            let transport = transport, sent = request
            result = try await withTimeout(resourceTimeout, clock: clock) { try await transport.send(sent) }
        } catch let error as URLError where Self.unreachable.contains(error.code) {
            throw PushRelayError.unreachable
        }
        try Task.checkCancellation()
        try APIClient.validate(result.response, data: result.data, now: .now)
        return result.response.statusCode == 204 ? .null : try JSONDecoder().decode(JSONValue.self, from: result.data)
    }
    /// Sends exact body bytes with extra headers and returns any status, so App Attest can sign the body it
    /// sends and tell the relay's refusals apart. Only a JSON answer (or 204) is accepted.
    public func exchange(_ method: HTTPMethod, path: String, headers: [String: String] = [:], body: Data?) async throws -> RelayReply {
        var request = try APIClient.request(baseURL: url, path: path, method: method, body: body, timeout: requestTimeout.seconds)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let result: HTTPResponse
        do {
            let transport = transport, sent = request
            result = try await withTimeout(resourceTimeout, clock: clock) { try await transport.send(sent) }
        } catch let error as URLError where Self.unreachable.contains(error.code) {
            throw PushRelayError.unreachable
        }
        try Task.checkCancellation()
        let status = result.response.statusCode
        if status == 204 { return RelayReply(status: status, body: .null) }
        guard let body = try? JSONDecoder().decode(JSONValue.self, from: result.data) else {
            throw APIError.notOpencode(contentType: result.response.value(forHTTPHeaderField: "Content-Type"))
        }
        return RelayReply(status: status, body: body)
    }
    private static let unreachable: Set<URLError.Code> = [.timedOut, .cannotConnectToHost, .cannotFindHost,
        .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed]
}

public enum PushRPC {
    public static func endpoint(namespace: String, method: String, input: JSONValue = .object([:])) throws -> Endpoint<JSONValue> {
        .init(method: .post, path: "/api/rpc/\(namespace)/\(method)", body: try JSONEncoder().encode(JSONValue.object(["input": input]))) { data, _ in
            let raw = try JSONDecoder().decode(JSONValue.self, from: data)
            guard let output = raw["output"] else { throw APIError.decoding("Missing RPC output") }
            return output
        }
    }
}

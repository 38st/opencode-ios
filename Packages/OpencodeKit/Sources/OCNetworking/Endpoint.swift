import Foundation
import OCFoundation
import OCModels

public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }
public enum Scope: Sendable { case global, location(directory: String), session }

public struct Endpoint<Response: Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [URLQueryItem]
    public var scope: Scope
    public var body: Data?
    /// Only endpoint-specific, typed settlement errors may bypass normal validation.
    public var settled: @Sendable (Int, JSONValue) -> Bool
    /// VCS routes answer 503 with a user-facing message ("Choose a review base").
    /// Everywhere else a 503 means the service is starting or stopping.
    public var reports503Message = false
    public var decode: @Sendable (Data, HTTPURLResponse) throws -> Response
    public init(method: HTTPMethod = .get, path: String, query: [URLQueryItem] = [], scope: Scope = .global,
                body: Data? = nil, settled: @escaping @Sendable (Int, JSONValue) -> Bool = { _, _ in false },
                decode: @escaping @Sendable (Data, HTTPURLResponse) throws -> Response) {
        self.method = method; self.path = path; self.query = query; self.scope = scope; self.body = body; self.decode = decode
        self.settled = settled
    }
}

public extension Endpoint where Response: Decodable {
    static func json(method: HTTPMethod = .get, path: String, query: [URLQueryItem] = [], scope: Scope = .global,
                     body: Data? = nil) -> Self {
        Self(method: method, path: path, query: query, scope: scope, body: body) { data, _ in
            try JSONDecoder().decode(Response.self, from: data)
        }
    }
}

public struct Located<Value: Decodable & Sendable>: Decodable, Sendable {
    public let location: Location
    public let data: Value
}

public enum APIError: Error, Sendable {
    case unauthorized
    case serviceStarting(retryAfter: Duration)
    case server(tag: String, status: Int, body: JSONValue)
    case notOpencode(contentType: String?)
    case transport(URLError)
    case decoding(String)
    case refused(ConnectionFailure)
    case cancelled
}

public actor APIClient {
    private let baseURL: URL
    private let credential: Credential?
    private let headers: [String: String]
    private let transport: any HTTPTransport
    private let clock: NetworkClock
    private let serverClock: ServerClock?
    public init(baseURL: URL, credential: Credential? = nil, headers: [String: String] = [:],
                transport: any HTTPTransport = URLSessionTransport(), clock: NetworkClock = .init(), serverClock: ServerClock? = nil) {
        self.baseURL = baseURL; self.credential = credential; self.headers = headers
        self.transport = transport; self.clock = clock
        self.serverClock = serverClock
    }
    public func send<R>(_ endpoint: Endpoint<R>) async throws(APIError) -> R {
        let request: URLRequest
        do {
            request = try Self.request(baseURL: baseURL, path: endpoint.path, method: endpoint.method,
                                       query: endpoint.query, scope: endpoint.scope, body: endpoint.body,
                                       credential: credential, headers: headers)
        } catch let error as APIError { throw error } catch { throw .refused(.invalidURL) }
        for attempt in 0...2 {
            do {
                try Task.checkCancellation()
                let sent = clock.date()
                let result = try await transport.send(request)
                if let date = result.response.value(forHTTPHeaderField: "Date") {
                    serverClock?.observe(httpDate: date, requestSentAt: sent, responseReceivedAt: clock.date())
                }
                let status = result.response.statusCode
                let raw = status >= 400 ? (try? JSONDecoder().decode(JSONValue.self, from: result.data)) ?? .null : .null
                if status == 503, endpoint.reports503Message, let message = raw["message"]?.stringValue, !message.isEmpty {
                    throw APIError.server(tag: raw["_tag"]?.stringValue ?? "UnknownError", status: status, body: raw)
                }
                if status < 400 || !endpoint.settled(status, raw) {
                    // A gateway may reject a write with an HTML/plain-text 4xx.
                    // Preserve its status so the outbox does not retry forever.
                    if endpoint.method != .get, (400..<500).contains(status), status != 401 {
                        throw APIError.server(tag: raw["_tag"]?.stringValue ?? "UnknownError", status: status, body: raw)
                    }
                    try Self.validate(result.response, data: result.data, now: clock.date())
                }
                do { return try endpoint.decode(result.data, result.response) }
                catch { throw APIError.decoding("Response does not match the expected JSON shape") }
            } catch let error as APIError { throw error }
            catch is CancellationError { throw .cancelled }
            catch let error as URLError {
                if error.code == .cancelled { throw .cancelled }
                if endpoint.method == .get && attempt < 2 { continue }
                throw .transport(error)
            } catch {
                if endpoint.method == .get && attempt < 2 { continue }
                throw .transport(URLError(.unknown))
            }
        }
        throw .transport(URLError(.unknown))
    }

    /// Raw responses are confined to fs.read. JSON-route validation stays unchanged.
    public func readFile(_ path: String, directory: String, range: Range<Int>? = nil, etag: String? = nil) async throws -> RawFileResponse {
        guard !path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
            throw APIError.refused(.invalidURL)
        }
        var request = try Self.request(baseURL: baseURL, path: "/api/fs/read/" + path,
            scope: .location(directory: directory), credential: credential, headers: headers)
        // URLComponents.path escapes delimiters once, retaining slash separators.
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let range, !range.isEmpty { request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let result = try await transport.send(request)
        if result.response.statusCode == 401 { throw APIError.unauthorized }
        guard [200, 206, 304, 416].contains(result.response.statusCode) else {
            try Self.validate(result.response, data: result.data, now: clock.date())
            throw APIError.decoding("Unexpected file response")
        }
        return RawFileResponse(result)
    }

    public nonisolated static func request(baseURL: URL, path: String, method: HTTPMethod = .get,
                                           query: [URLQueryItem] = [], scope: Scope = .global, body: Data? = nil,
                                           credential: Credential? = nil, headers: [String: String] = [:],
                                           timeout: TimeInterval = 30) throws -> URLRequest {
        try EndpointPolicy.validate(baseURL)
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.refused(.invalidURL) }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? path : parts.path.trimmingSuffix("/") + path
        var items = query
        if case .location(let directory) = scope { items.append(URLQueryItem(name: "location[directory]", value: directory)) }
        parts.queryItems = items.isEmpty ? nil : items
        guard let url = parts.url else { throw APIError.refused(.invalidURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let secret = credential?.secret {
            request.setValue("Basic " + Data("opencode:\(secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        return request
    }

    nonisolated static func validate(_ response: HTTPURLResponse, data: Data = Data(), now: Date,
                                     contentType expected: String = "application/json") throws {
        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased().split(separator: ";").first.map(String.init)
        if response.statusCode == 401 { throw APIError.unauthorized }
        if response.statusCode == 503 { throw APIError.serviceStarting(retryAfter: retryAfter(response, now: now)) }
        if response.statusCode == 204 { return }
        if type != expected { throw APIError.notOpencode(contentType: type) }
        guard (200..<300).contains(response.statusCode) else {
            let raw = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
            var tag = "UnknownError"
            if case .object(let object) = raw, case .string(let value) = object["_tag"] { tag = value }
            throw APIError.server(tag: tag, status: response.statusCode, body: raw)
        }
    }
    nonisolated static func retryAfter(_ response: HTTPURLResponse, now: Date) -> Duration {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return .seconds(1) }
        if let seconds = Int64(value), seconds >= 0 { return .seconds(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return .seconds(max(0, formatter.date(from: value)?.timeIntervalSince(now) ?? 1))
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }
}

import Foundation
import OCModels

public struct PairingLink: Sendable, Equatable {
    public let urls: [URL]
    public let code: String
    public init(urls: [URL], code: String) { self.urls = urls; self.code = code }
}
public enum PairingError: Error, Sendable, Equatable, LocalizedError {
    case invalidInput, legacyLink, expired, unreachable
    public var errorDescription: String? {
        switch self {
        case .legacyLink: "This is an old pairing link. Re-run opencode pair to create a new one."
        case .expired: "This pairing link expired or was already used. Re-run opencode pair."
        case .invalidInput: "Enter an opencode pairing link, QR payload, or server URL and password."
        case .unreachable: "None of the server addresses could be reached."
        }
    }
}
public struct RedeemedPairing: Sendable {
    public let server: ServerRecord
    public let preferredURL: URL
    public let token: String
}

public enum PairingParser {
    public static func serverAddress(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("://") || text.hasPrefix("http://") || text.hasPrefix("https://") else { return nil }
        var normalized = text.hasPrefix("http://") || text.hasPrefix("https://") ? text : "http://" + text
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !text.contains(where: { $0.isWhitespace }) else { return nil }
        return url
    }
    public static func bareServerAddress(_ input: String) -> URL? {
        guard let url = serverAddress(input), url.path.isEmpty || url.path == "/", let host = url.host,
              host == "localhost" || host.contains(".") || host.hasPrefix("[") || url.port != nil else { return nil }
        return url
    }
    public static func isLegacy(_ input: String) -> Bool {
        guard let url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme), url.path == "/connect" else { return false }
        return !(url.fragment ?? "").isEmpty || url.queryItems?.contains(where: { $0.name == "data" }) == true
    }
    public static func parse(_ input: String) throws -> PairingLink {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLegacy(text) { throw PairingError.legacyLink }
        if text.hasPrefix("{") {
            struct Payload: Decodable { let code: String; let urls: [String] }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)), validCode(payload.code) else {
                throw PairingError.invalidInput
            }
            var seen: Set<String> = []
            let strings = payload.urls.filter { seen.insert($0).inserted }
            let urls = strings.compactMap(serverAddress)
            guard !urls.isEmpty, urls.count == strings.count else { throw PairingError.invalidInput }
            return PairingLink(urls: urls, code: payload.code)
        }
        guard var url = URLComponents(string: text), ["http", "https"].contains(url.scheme), url.host != nil else { throw PairingError.invalidInput }
        let prefix = "/auth/connect/"
        guard url.percentEncodedPath.hasPrefix(prefix) else { throw PairingError.invalidInput }
        let code = String(url.percentEncodedPath.dropFirst(prefix.count))
        guard validCode(code) else { throw PairingError.invalidInput }
        // The reference parses url.origin, intentionally discarding link query, fragment and userinfo.
        url.path = ""; url.query = nil; url.fragment = nil; url.user = nil; url.password = nil
        guard let address = url.url else { throw PairingError.invalidInput }
        return PairingLink(urls: [address], code: code)
    }
    private static func validCode(_ code: String) -> Bool {
        !code.isEmpty && code.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}

public struct PairingService: Sendable {
    private let transport: any HTTPTransport
    private let clock: NetworkClock
    public init(transport: any HTTPTransport = URLSessionTransport(), clock: NetworkClock = .init()) {
        self.transport = transport; self.clock = clock
    }
    private enum Attempt: Sendable { case success(Int, String), failure(Int, Bool), preferenceExpired }
    public func redeem(_ link: PairingLink) async throws -> RedeemedPairing {
        guard !link.urls.isEmpty else { throw PairingError.invalidInput }
        return try await withThrowingTaskGroup(of: Attempt.self) { group in
            for (index, url) in link.urls.enumerated() {
                group.addTask {
                    do {
                        let token: String = try await withTimeout(.seconds(5), clock: clock) {
                            struct Session: Decodable { let token: String }
                            let request = try APIClient.request(baseURL: url, path: "/auth/connect/" + link.code, timeout: 5)
                            let result = try await transport.send(request)
                            try APIClient.validate(result.response, data: result.data, now: clock.date())
                            return try JSONDecoder().decode(Session.self, from: result.data).token
                        }
                        return .success(index, token)
                    } catch APIError.unauthorized { return .failure(index, true) }
                    catch { return .failure(index, false) }
                }
            }
            var winner: (Int, String)?
            var firstAnswered: Bool?
            var expired = false
            var remaining = link.urls.count
            while let attempt = try await group.next() {
                try Task.checkCancellation()
                switch attempt {
                case .success(let index, let token):
                    remaining -= 1
                    if index == 0 { firstAnswered = true }
                    if winner == nil {
                        winner = (index, token)
                        if index != 0 && firstAnswered == nil {
                            group.addTask { try await clock.sleep(.seconds(1)); return .preferenceExpired }
                        }
                    }
                case .failure(let index, let unauthorized):
                    remaining -= 1; expired = expired || unauthorized
                    if index == 0 { firstAnswered = unauthorized }
                case .preferenceExpired: firstAnswered = false
                }
                if let winner, winner.0 == 0 || firstAnswered != nil {
                    group.cancelAll()
                    var preferred = winner.0
                    if winner.0 != 0, firstAnswered == true {
                        let outcome = await ServerProbe(transport: transport, clock: clock).probe(
                            endpoint: link.urls[0], credential: .password(winner.1), timeout: .seconds(5))
                        if case .v2 = outcome { preferred = 0 }
                    }
                    let endpoints = link.urls.map { EndpointRecord(url: $0, kind: EndpointPolicy.classify($0), source: .pairing) }
                    return RedeemedPairing(server: ServerRecord(name: link.urls[preferred].host ?? "opencode", endpoints: endpoints),
                                           preferredURL: link.urls[preferred], token: winner.1)
                }
                if remaining == 0 && winner == nil { throw expired ? PairingError.expired : PairingError.unreachable }
            }
            throw PairingError.unreachable
        }
    }
    public func manual(url: String, password: String) async throws -> (ServerRecord, Credential) {
        guard let url = PairingParser.serverAddress(url) else { throw PairingError.invalidInput }
        try EndpointPolicy.validate(url)
        let credential = Credential.password(password)
        let outcome = await ServerProbe(transport: transport, clock: clock).probe(endpoint: url, credential: credential)
        guard case .v2(let info) = outcome else {
            if case .unauthorized = outcome { throw APIError.unauthorized }
            throw PairingError.unreachable
        }
        return (ServerRecord(name: url.host ?? "opencode", endpoints: [.init(url: url, kind: EndpointPolicy.classify(url))], lastInfo: info), credential)
    }
}

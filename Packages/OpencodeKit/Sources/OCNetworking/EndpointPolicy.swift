import Foundation
import Darwin
import OCModels

public enum EndpointPolicy {
    public static func classify(_ url: URL) -> EndpointKind {
        if url.scheme == "ssh" { return .ssh }
        let host = hostname(url)
        if host == "ts.net" || host.hasSuffix(".ts.net") { return .tailnet }
        if let ip = ipv4(host), ip[0] == 100 && (64...127).contains(ip[1]) { return .tailnet }
        if isLocal(host) { return .lan }
        // The server source's remote URL contract uses *.opentunnel.xyz.
        if host == "opentunnel.xyz" || host.hasSuffix(".opentunnel.xyz") { return .tunnel }
        return url.scheme == "https" ? .https : .unknown
    }
    public static func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw APIError.refused(.invalidURL)
        }
        let host = hostname(url)
        let tailnetIP = ipv4(host).map { $0[0] == 100 && (64...127).contains($0[1]) } ?? false
        guard url.scheme == "https" || isLocal(host) || tailnetIP else { throw APIError.refused(.insecureRemote) }
    }
    /// HTTPS, or a tailnet address (WireGuard encrypts it). Anything else crosses the network in the clear.
    public static func isEncrypted(_ url: URL) -> Bool { url.scheme == "https" || classify(url) == .tailnet }
    public static func isLoopback(_ url: URL) -> Bool {
        let host = hostname(url)
        return host == "localhost" || host == "::1" || ipv4(host)?.first == 127
    }
    private static func hostname(_ url: URL) -> String {
        (url.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    private static func ipv4(_ host: String) -> [UInt8]? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }
        let bytes = pieces.compactMap { UInt8($0) }
        return bytes.count == 4 ? bytes : nil
    }
    private static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || (!host.isEmpty && !host.contains(".") && !host.contains(":")) { return true }
        if let ip = ipv4(host) {
            return ip[0] == 10 || ip[0] == 127 || (ip[0] == 172 && (16...31).contains(ip[1]))
                || (ip[0] == 192 && ip[1] == 168) || (ip[0] == 169 && ip[1] == 254)
        }
        var address = in6_addr()
        let literal = String(host.split(separator: "%", maxSplits: 1).first ?? "")
        guard inet_pton(AF_INET6, literal, &address) == 1 else { return false }
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
        if bytes[0] & 0xFE == 0xFC || (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80) { return true }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
            return isLocal(bytes[12...15].map(String.init).joined(separator: "."))
        }
        return false
    }
}

func diagnose(_ error: any Error, localNetworkDenied: Bool = false) -> ConnectionFailure {
    if let failure = error as? ConnectionFailure { return failure }
    if let error = error as? APIError {
        switch error {
        case .unauthorized: return .unauthorized
        case .refused(let reason): return reason
        case .notOpencode: return .notOpencode
        case .cancelled: return .cancelled
        case .transport(let error): return diagnose(error, localNetworkDenied: localNetworkDenied)
        default: return .transport
        }
    }
    if error is CancellationError { return .cancelled }
    guard let error = error as? URLError else { return .transport }
    switch error.code {
    case .cannotFindHost, .dnsLookupFailed: return .dnsFailure
    case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
         .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
         .clientCertificateRequired: return .tlsError
    case .timedOut: return .timeout
    case .cancelled: return .cancelled
    case .notConnectedToInternet, .cannotConnectToHost: return localNetworkDenied ? .localNetworkDenied : .transport
    default: return .transport
    }
}

import Foundation

public struct ServerID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public typealias EndpointID = UUID

public enum EndpointKind: String, Codable, Sendable, CaseIterable {
    case lan, tailnet, tunnel, https, ssh, unknown
    public var rank: Int {
        switch self {
        case .lan: 0
        case .tailnet: 1
        case .https: 2
        case .tunnel: 3
        case .ssh: 4
        case .unknown: 5
        }
    }
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum EndpointSource: String, Codable, Sendable {
    case pairing, manual, discovered, unknown
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct EndpointStats: Codable, Equatable, Sendable {
    public var lastSuccess: Date?
    public var medianRTT: TimeInterval?
    public var lastFailure: ConnectionFailure?
    public init(lastSuccess: Date? = nil, medianRTT: TimeInterval? = nil, lastFailure: ConnectionFailure? = nil) {
        self.lastSuccess = lastSuccess
        self.medianRTT = medianRTT
        self.lastFailure = lastFailure
    }
}

public struct EndpointRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: EndpointID
    public var url: URL
    public var kind: EndpointKind
    public var source: EndpointSource
    public var isEnabled: Bool
    public var headerNames: [String]
    public var stats: EndpointStats

    public init(id: EndpointID = UUID(), url: URL, kind: EndpointKind, source: EndpointSource = .manual,
                isEnabled: Bool = true, headerNames: [String] = [], stats: EndpointStats = .init()) {
        self.id = id
        self.url = url
        self.kind = kind
        self.source = source
        self.isEnabled = isEnabled
        self.headerNames = headerNames
        self.stats = stats
    }
}

public struct ServerRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: ServerID
    public var name: String
    public var endpoints: [EndpointRecord]
    public var lastInfo: ServerInfo?
    public var autoConnect: Bool
    public init(id: ServerID = .init(), name: String, endpoints: [EndpointRecord],
                lastInfo: ServerInfo? = nil, autoConnect: Bool = true) {
        self.id = id
        self.name = name
        self.endpoints = endpoints
        self.lastInfo = lastInfo
        self.autoConnect = autoConnect
    }
}

public enum Credential: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case password(String)
    case pairingToken(String, expiresAt: Date)
    case unknown

    public var secret: String? {
        switch self {
        case .password(let value), .pairingToken(let value, _): value
        case .unknown: nil
        }
    }
    public func expiresWithinFiveDays(now: Date = Date()) -> Bool {
        guard case .pairingToken(_, let expires) = self else { return false }
        return expires.timeIntervalSince(now) <= 5 * 24 * 60 * 60
    }
    public var description: String { "Credential([REDACTED])" }
    public var debugDescription: String { description }
}

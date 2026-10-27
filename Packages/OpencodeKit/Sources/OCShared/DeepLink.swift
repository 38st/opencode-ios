import Foundation

/// opencodeios://server/<UUID>[/session/<id>[/request/<id>]]
/// No query, fragment, user-info or port is accepted, so credentials cannot enter routing state.
public struct DeepLink: Equatable, Sendable {
    public let serverID: UUID
    public let sessionID: String?
    public let requestID: String?
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "opencodeios", url.host == "server", url.user == nil,
              url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard [1, 3, 5].contains(parts.count), let first = parts.first, let server = UUID(uuidString: first) else { return nil }
        func valid(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0) }
        }
        if parts.count >= 3 && (parts[1] != "session" || !valid(parts[2])) { return nil }
        if parts.count == 5 && (parts[3] != "request" || !valid(parts[4])) { return nil }
        serverID = server; sessionID = parts.count >= 3 ? parts[2] : nil; requestID = parts.count == 5 ? parts[4] : nil
    }
}

public extension DeepLink {
    static func url(serverID: UUID, sessionID: String? = nil, requestID: String? = nil) -> URL? {
        var url = URL(string: "opencodeios://server/" + serverID.uuidString)
        if let sessionID { url = url?.appending(path: "session").appending(path: sessionID) }
        if sessionID != nil, let requestID { url = url?.appending(path: "request").appending(path: requestID) }
        guard let url, DeepLink(url: url) != nil else { return nil }
        return url
    }
}

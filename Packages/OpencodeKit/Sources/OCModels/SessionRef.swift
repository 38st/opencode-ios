import Foundation

public struct SessionRef: Hashable, Codable, Sendable, Identifiable {
    public var serverID: ServerID
    public var sessionID: String
    public var requestID: String?
    public var id: String { serverID.rawValue.uuidString + ":" + sessionID + (requestID.map { ":" + $0 } ?? "") }
    public init(serverID: ServerID, sessionID: String, requestID: String? = nil) {
        self.serverID = serverID; self.sessionID = sessionID; self.requestID = requestID
    }
}
public struct SessionLocalMeta: Equatable, Sendable {
    public var pinned: Bool
    public var hidden: Bool
    public init(pinned: Bool = false, hidden: Bool = false) { self.pinned = pinned; self.hidden = hidden }
}

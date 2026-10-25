import Foundation
import OCModels

/// Where New session starts. Home's filters only choose what Home lists; this picks the server and
/// project a new session opens on, without writing back to those filters.
public struct NewSessionTarget: Equatable, Sendable {
    public var serverID: ServerID
    public var projectID: String?
    public init(serverID: ServerID, projectID: String? = nil) { self.serverID = serverID; self.projectID = projectID }

    /// In order: the server picked in New session itself, Home's project filter, Home's server filter,
    /// the session New session was started from, then the first saved server. A project is kept only
    /// when it belongs to the chosen server.
    /// - Parameters:
    ///   - homeProject: Home's project filter, `"<server UUID>:<project ID>"`.
    ///   - origin: the open session New session was started from, and its project.
    public static func resolve(servers: [ServerID], chosenServer: ServerID?, homeServer: ServerID?, homeProject: String?,
                               origin: NewSessionTarget?) -> NewSessionTarget? {
        let project = homeProject.flatMap(parse).flatMap { servers.contains($0.serverID) ? $0 : nil }
        let origin = origin.flatMap { servers.contains($0.serverID) ? $0 : nil }
        func projectID(on server: ServerID) -> String? {
            if let project, project.serverID == server { return project.projectID }
            if let origin, origin.serverID == server { return origin.projectID }
            return nil
        }
        if let chosenServer, servers.contains(chosenServer) { return .init(serverID: chosenServer, projectID: projectID(on: chosenServer)) }
        if let project { return project }
        if let homeServer, servers.contains(homeServer) { return .init(serverID: homeServer, projectID: projectID(on: homeServer)) }
        if let origin { return origin }
        return servers.first.map { .init(serverID: $0) }
    }
    private static func parse(_ value: String) -> NewSessionTarget? {
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let uuid = UUID(uuidString: String(parts[0])) else { return nil }
        return .init(serverID: ServerID(rawValue: uuid), projectID: String(parts[1]))
    }
}

import AppIntents
import CoreSpotlight
import Foundation
import OCShared
import UniformTypeIdentifiers

/// A paired server, or All servers for the widgets' filter.
public struct ServerEntity: AppEntity, Equatable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Server"
    public static let defaultQuery = ServerQuery()
    /// The widgets' default: every server.
    public static let all = ServerEntity(id: "all", name: "All servers")
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public init(_ server: SystemSnapshot.Server) { self.init(id: server.id, name: server.name) }
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    /// The server's ID, or nil for All servers.
    public var serverID: String? { id == Self.all.id ? nil : id }
}

public struct ServerQuery: EntityStringQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [ServerEntity] {
        let directory = await IntentEnvironment.directory()
        return identifiers.compactMap { id in id == ServerEntity.all.id ? .all : directory.server(id).map(ServerEntity.init) }
    }
    public func entities(matching string: String) async throws -> [ServerEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    /// All servers first, as the widgets' default, then each paired server.
    public func suggestedEntities() async throws -> [ServerEntity] { [.all] + (await IntentEnvironment.directory().servers.map(ServerEntity.init)) }
    public func defaultResult() async -> ServerEntity? { .all }
}

public struct ProjectEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    public static let defaultQuery = ProjectQuery()
    /// `<server>:<project>`.
    public let id: String
    public let server: String
    public let project: String
    public let name: String
    public let serverName: String
    public init(server: String, project: String, name: String, serverName: String) {
        self.id = server + ":" + project; self.server = server; self.project = project; self.name = name; self.serverName = serverName
    }
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(serverName)") }
}

public struct ProjectQuery: EntityStringQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let all = Self.entities(await IntentEnvironment.directory())
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }
    public func entities(matching string: String) async throws -> [ProjectEntity] {
        Self.entities(await IntentEnvironment.directory()).filter { $0.name.localizedCaseInsensitiveContains(string) || $0.serverName.localizedCaseInsensitiveContains(string) }
    }
    /// Projects with the most recent activity first.
    public func suggestedEntities() async throws -> [ProjectEntity] { Self.entities(await IntentEnvironment.directory()) }
    static func entities(_ directory: IntentDirectory) -> [ProjectEntity] {
        directory.projects.sorted { $0.activity > $1.activity }.compactMap { project in
            directory.server(project.server).map { ProjectEntity(server: project.server, project: project.project, name: project.name, serverName: $0.name) }
        }
    }
}

/// A root session. Spotlight indexes its title, project and server name, never its conversation.
public struct SessionEntity: IndexedEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Session"
    public static let defaultQuery = SessionQuery()
    /// `<server>:<session>`.
    public let id: String
    public let server: String
    public let session: String
    public let title: String
    public let project: String
    public let serverName: String
    public let activity: Date
    public init(server: String, session: String, title: String, project: String, serverName: String, activity: Date) {
        self.id = server + ":" + session; self.server = server; self.session = session; self.title = title
        self.project = project; self.serverName = serverName; self.activity = activity
    }
    public init(_ session: SystemSnapshot.Session, serverName: String) {
        self.init(server: session.server, session: session.session, title: session.title, project: session.project, serverName: serverName, activity: session.activity)
    }
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(detail)") }
    public var detail: String { project.isEmpty ? serverName : project + " · " + serverName }
    public var url: URL? { UUID(uuidString: server).flatMap { DeepLink.url(serverID: $0, sessionID: session) } }
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title; attributes.displayName = title
        attributes.contentDescription = detail
        attributes.keywords = [project, serverName].filter { !$0.isEmpty }
        // The day only: a running session would otherwise be indexed again at every step.
        attributes.contentModificationDate = Calendar(identifier: .gregorian).startOfDay(for: activity)
        return attributes
    }
}

public struct SessionQuery: EntityStringQuery {
    public init() {}
    public func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        let all = Self.entities(await IntentEnvironment.directory())
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }
    public func entities(matching string: String) async throws -> [SessionEntity] {
        Self.entities(await IntentEnvironment.directory()).filter { $0.title.localizedCaseInsensitiveContains(string) || $0.project.localizedCaseInsensitiveContains(string) }
    }
    /// The sessions that need you, then running ones, then the rest by last activity, as Home lists them. These also
    /// become Siri's parameter phrases, so with Spotlight switched off in Settings there are none.
    public func suggestedEntities() async throws -> [SessionEntity] {
        let directory = await IntentEnvironment.directory()
        guard directory.suggestsSessions else { return [] }
        return Array(Self.entities(directory).prefix(SystemDefaults.recentLimit))
    }
    static func entities(_ directory: IntentDirectory) -> [SessionEntity] {
        let rank = { (session: SystemSnapshot.Session) in session.status.needsYou ? 0 : session.status.isRunning ? 1 : 2 }
        return directory.sessions.sorted { (rank($0), $1.activity, $0.id) < (rank($1), $0.activity, $1.id) }
            .map { SessionEntity($0, serverName: directory.server($0.server)?.name ?? "") }
    }
}

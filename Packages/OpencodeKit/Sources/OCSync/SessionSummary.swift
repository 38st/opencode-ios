import Foundation
import OCModels

public struct SessionSummary: Identifiable {
    public let server: ServerStore
    public let session: SessionModel
    public let family: [SessionModel]
    public var id: String { server.id.rawValue.uuidString + ":" + session.id }
    public var ref: SessionRef { .init(serverID: server.id, sessionID: session.id) }
    public var runningCount: Int { family.filter { $0.status.isRunning || server.running.contains($0.id) }.count }
    public var failed: Bool { family.contains { $0.info.outcome == "failed" && $0.unread } }
    public var needsYou: Bool { family.contains { !(server.permissions[$0.id] ?? []).isEmpty || !(server.forms[.session($0.id)] ?? []).isEmpty } || failed }
    public var cost: Double { family.reduce(0) { $0 + $1.info.cost } }
    public var activity: Double { family.map { max($0.info.time.updated, $0.info.time.created) }.max() ?? 0 }
    public var meta: SessionLocalMeta { server.readPath.localMeta[session.id] ?? .init() }
    public var projectName: String {
        let project = server.projects.first { $0.id == session.info.projectID }
        return project?.name ?? URL(fileURLWithPath: project?.canonical ?? session.info.location.directory).lastPathComponent
    }
    public var reviewRef: SessionRef {
        for model in family {
            if let request = server.permissions[model.id]?.first { return .init(serverID: server.id, sessionID: model.id, requestID: request.id) }
            if let form = server.forms[.session(model.id)]?.first { return .init(serverID: server.id, sessionID: model.id, requestID: form.id) }
        }
        let failed = family.first { $0.info.outcome == "failed" && $0.unread } ?? session
        return .init(serverID: server.id, sessionID: failed.id, requestID: "error")
    }
    public init(server: ServerStore, session: SessionModel) {
        self.server = server; self.session = session; self.family = server.readPath.family(session.id)
    }
}

import Foundation
import OCFoundation
import OCModels

public struct InterruptResponse: Decodable, Sendable { public let interrupted: Bool }

public enum WriteEndpoints {
    /// The outbox passes the original body, never a re-encoded retry.
    public static func prompt(_ session: String, body: Data) -> Endpoint<DataResponse<InboxItem>> {
        .json(method: .post, path: path(session, "prompt"), scope: .session, body: body)
    }
    public static func interrupt(_ session: String, resume: Bool = false) -> Endpoint<InterruptResponse> {
        .json(method: .post, path: path(session, "interrupt"), query: [.init(name: "resume", value: String(resume))], scope: .session)
    }
    public static func delivery(_ session: String, item: String, delivery: Delivery) throws -> Endpoint<Void> {
        try empty(.patch, path(session, "inbox", item), body: ["delivery": encoded(delivery)])
    }
    public static func cancelInbox(_ session: String, item: String) -> Endpoint<Void> {
        .init(method: .delete, path: path(session, "inbox", item)) { _, _ in () }
    }
    public static func agent(_ session: String, agent: String) throws -> Endpoint<Void> {
        try empty(.post, path(session, "agent"), body: ["agent": .string(agent)])
    }
    public static func model(_ session: String, model: ModelRef) throws -> Endpoint<Void> {
        try empty(.post, path(session, "model"), body: ["model": model.raw])
    }
    /// Commands have no admission ID and must never be retried automatically.
    public static func command(_ session: String, name: String, input: PromptInput) throws -> Endpoint<Void> {
        var raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(input))
        raw.set("name", .string(name)); raw.set("resume", nil); raw.set("metadata", nil)
        return try empty(.post, path(session, "command"), body: raw.objectValue ?? [:])
    }
    public static func shell(_ session: String, id: String, command: String) throws -> Endpoint<Void> {
        try empty(.post, path(session, "shell"), body: ["id": .string(id), "command": .string(command)])
    }
    public static func create(body: Data) -> Endpoint<DataResponse<SessionInfo>> {
        .json(method: .post, path: "/api/session", body: body)
    }
    public static func create(id: String, location: Location, title: String? = nil, agent: String? = nil,
                              model: ModelRef? = nil) throws -> Endpoint<DataResponse<SessionInfo>> {
        let raw: JSONValue = .object(["id": .string(id), "location": .object(["directory": .string(location.directory)]),
            "title": title.map(JSONValue.string) ?? .null, "agent": agent.map(JSONValue.string) ?? .null, "model": model?.raw ?? .null])
        return create(body: try JSONEncoder().encode(raw.omittingNullFields))
    }
    public static func rename(_ session: String, title: String) throws -> Endpoint<Void> {
        try empty(.patch, path(session), body: ["title": .string(title)])
    }
    public static func delete(_ session: String) -> Endpoint<Void> {
        .init(method: .delete, path: path(session)) { _, _ in () }
    }
    public static func fork(_ session: String, before: String? = nil) throws -> Endpoint<DataResponse<SessionInfo>> {
        .json(method: .post, path: path(session, "fork"), scope: .session,
              body: try JSONEncoder().encode(JSONValue.object(before.map { ["before": .string($0)] } ?? [:])))
    }
    public static func compact(_ session: String, id: String, delivery: Delivery = .steer) throws -> Endpoint<DataResponse<InboxItem>> {
        .json(method: .post, path: path(session, "compact"), scope: .session,
              body: try JSONEncoder().encode(JSONValue.object(["id": .string(id), "delivery": encoded(delivery)])))
    }
    public static func stageRevert(_ session: String, message: String, files: Bool = true) throws -> Endpoint<DataResponse<SessionRevert>> {
        .json(method: .post, path: path(session, "revert", "stage"), scope: .session,
              body: try JSONEncoder().encode(JSONValue.object(["messageID": .string(message), "files": .bool(files)])))
    }
    public static func commitRevert(_ session: String) -> Endpoint<Void> {
        .init(method: .post, path: path(session, "revert", "commit"), scope: .session) { _, _ in () }
    }
    public static func redo(_ session: String) -> Endpoint<Void> {
        .init(method: .delete, path: path(session, "revert"), scope: .session) { _, _ in () }
    }
    public static func permission(_ session: String, request: String, decision: PermissionDecision, message: String? = nil) throws -> Endpoint<Void> {
        let raw: JSONValue = .object(["decision": .string(decision.rawValue), "message": message.map(JSONValue.string) ?? .null])
        return .init(method: .post, path: path(session, "permission", request, "reply"), scope: .session,
                     body: try JSONEncoder().encode(raw.omittingNullFields), settled: { status, raw in
            status == 404 && raw["_tag"]?.stringValue == "PermissionNotFoundError"
        }) { _, _ in () }
    }
    public static func formReply(_ session: String, form: String, answer: [String: JSONValue], directory: String? = nil) throws -> Endpoint<Void> {
        .init(method: .post, path: path(session, "form", form, "reply"), scope: directory.map { .location(directory: $0) } ?? .session,
              body: try JSONEncoder().encode(JSONValue.object(["answer": .object(answer)]).omittingNullFields),
              settled: { settledForm($0, $1, id: form) }) { _, _ in () }
    }
    public static func dismissForm(_ session: String, form: String, reason: String? = nil, directory: String? = nil) -> Endpoint<Void> {
        .init(method: .delete, path: path(session, "form", form), query: reason.map { [.init(name: "message", value: $0)] } ?? [],
              scope: directory.map { .location(directory: $0) } ?? .session,
              settled: { settledForm($0, $1, id: form) }) { _, _ in () }
    }
    private static func settledForm(_ status: Int, _ raw: JSONValue, id: String) -> Bool {
        raw["id"]?.stringValue == id && ((status == 409 && raw["_tag"]?.stringValue == "FormAlreadySettledError") ||
            (status == 404 && raw["_tag"]?.stringValue == "FormNotFoundError"))
    }
    private static func path(_ session: String, _ suffix: String...) -> String {
        (["", "api", "session", session] + suffix).joined(separator: "/")
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
    private static func empty(_ method: HTTPMethod, _ path: String, body: [String: JSONValue]) throws -> Endpoint<Void> {
        .init(method: method, path: path, scope: .session, body: try JSONEncoder().encode(JSONValue.object(body).omittingNullFields)) { _, _ in () }
    }
}

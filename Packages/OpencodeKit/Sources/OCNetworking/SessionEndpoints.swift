// Routes: packages/protocol/src/groups/session.ts at v2.2.2. Move, export and statistics are global; generate takes
// the session's location.
import Foundation
import OCFoundation
import OCModels

public struct GeneratedText: Decodable, Sendable { public let text: String }

public enum SessionEndpoints {
    /// 204. The server enqueues a `move` inbox item; `session.moved` follows at the delivery boundary.
    public static func move(_ session: String, directory: String, delivery: Delivery) throws -> Endpoint<Void> {
        let body = try JSONEncoder().encode(JSONValue.object(["directory": .string(directory), "delivery": encoded(delivery)]))
        return .init(method: .post, path: "/api/session/\(session)/move", body: body) { _, _ in () }
    }
    /// `SessionTransfer.Data` as raw JSON: the export is shared as the server wrote it.
    public static func export(_ session: String, sanitize: Bool) -> Endpoint<JSONValue> {
        .init(path: "/api/experimental/session/\(session)/export", query: [.init(name: "sanitize", value: String(sanitize))]) { data, _ in
            let raw = try JSONDecoder().decode(JSONValue.self, from: data)
            // v2.2.2 wraps the transfer in `data`; the protocol reference shows it bare.
            guard let transfer = raw["data"] ?? (raw["info"] != nil ? raw : nil), transfer["info"]?.objectValue != nil else {
                throw APIError.decoding("Export without session")
            }
            return transfer
        }
    }
    public static func stats(_ range: StatsRange, projectID: String?) -> Endpoint<DataResponse<SessionStats>> {
        var query = range.query.map { URLQueryItem(name: $0.0, value: $0.1) } + [.init(name: "tools", value: "detail")]
        if let projectID { query.append(.init(name: "project", value: projectID)) }
        return .json(path: "/api/experimental/session/stats", query: query)
    }
    /// A side question answered from the session's context; the history does not change.
    public static func generate(_ session: String, prompt: String) throws -> Endpoint<DataResponse<GeneratedText>> {
        .json(method: .post, path: "/api/session/\(session)/generate", scope: .session,
              body: try JSONEncoder().encode(["prompt": prompt]))
    }
    private static func encoded(_ delivery: Delivery) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(delivery))
    }
}

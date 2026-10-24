import Foundation
import OCFoundation

/// The sealed plaintext (`server/contracts/schema/payload.schema.json`). Unknown keys are ignored
/// and `null` is absent; a present field of the wrong type refuses the whole payload.
public struct PushPayload: Sendable, Equatable {
    public let kind: String
    /// The app's own reference for the server, sent with `registerDevice`.
    public let server: String
    /// Unix seconds, equal to the envelope's.
    public let expiry: Int64
    /// Pending permission requests and forms on the server, for the badge.
    public let pending: Int
    public let sessionID: String?
    public let rootSessionID: String?
    public let title: String?
    public let project: String?
    public let requestID: String?
    public let action: String?
    public let summary: String?
    public let options: [String]?
    public let risk: String?
    public let digest: String?
    public let freeText: Bool?
    public let reply: String?

    /// The risk tier; anything but a known tier counts as high, so it is never approved from a notification.
    public var riskTier: PermissionRisk { risk.flatMap(PermissionRisk.init(rawValue:)) ?? .high }

    public init(plaintext: Data) throws {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: plaintext), let object = json.objectValue else {
            throw PushEnvelopeError.payload
        }
        func present(_ key: String) -> JSONValue? { object[key].flatMap { $0 == .null ? nil : $0 } }
        func text(_ key: String) throws -> String? {
            guard let value = present(key) else { return nil }
            guard let text = value.stringValue else { throw PushEnvelopeError.payload }
            return text
        }
        func integer(_ key: String) -> Int64? { PushEnvelope.integer(present(key)) }
        guard integer("v") == Int64(PushContract.shared.payload.version),
              let kind = present("kind")?.stringValue, PushContract.shared.kinds[kind] != nil,
              let server = present("server")?.stringValue,
              let expiry = integer("exp"),
              let pending = integer("pending"), pending >= 0
        else { throw PushEnvelopeError.payload }
        self.kind = kind; self.server = server; self.expiry = expiry; self.pending = Int(pending)
        sessionID = try text("sessionID"); rootSessionID = try text("rootSessionID")
        title = try text("title"); project = try text("project"); requestID = try text("requestID")
        action = try text("action"); summary = try text("summary"); risk = try text("risk")
        digest = try text("digest"); reply = try text("reply")
        if let value = present("freeText") {
            guard let flag = value.boolValue else { throw PushEnvelopeError.payload }
            freeText = flag
        } else { freeText = nil }
        if let value = present("options") {
            guard let items = value.arrayValue else { throw PushEnvelopeError.payload }
            options = try items.map { item in
                guard let label = item.stringValue else { throw PushEnvelopeError.payload }
                return label
            }
        } else { options = nil }
    }
}

import CryptoKit
import Foundation
import OCFoundation
import OCModels

/// The request digest of `server/contracts/README.md`: lowercase hex SHA-256 of the RFC 8785
/// form of a projection of the server's JSON. Notification actions recompute it from a fresh
/// `GET` and act only if it still matches what the notification showed.
public enum PushDigest {
    public enum Failure: Error, Equatable {
        case invalid(String)
    }

    public static func permission(_ request: PermissionRequest) throws -> String { try permission(raw: request.raw) }
    public static func form(_ form: FormInfo) throws -> String { try self.form(raw: form.raw) }

    /// `{requestID, sessionID, action, resources, save}`; an absent or `null` `save` is `[]`.
    public static func permission(raw: JSONValue) throws -> String {
        try digest(permissionInput(raw))
    }

    /// `{formID, sessionID, title, fields: [{key, type, title, description, options: [{value, label}]}]}`.
    public static func form(raw: JSONValue) throws -> String {
        try digest(formInput(raw))
    }

    public static func permissionInput(_ raw: JSONValue) throws -> JSONValue {
        guard let object = raw.objectValue else { throw Failure.invalid("request") }
        return .object([
            "requestID": .string(try text(object["id"], "id")),
            "sessionID": .string(try text(object["sessionID"], "sessionID")),
            "action": .string(try text(object["action"], "action")),
            "resources": .array(try texts(object["resources"], "resources").map(JSONValue.string)),
            "save": .array(try (isAbsent(object["save"]) ? [] : texts(object["save"], "save")).map(JSONValue.string)),
        ])
    }

    public static func formInput(_ raw: JSONValue) throws -> JSONValue {
        guard let object = raw.objectValue, let fields = object["fields"]?.arrayValue else { throw Failure.invalid("form") }
        return .object([
            "formID": .string(try text(object["id"], "id")),
            "sessionID": .string(try text(object["sessionID"], "sessionID")),
            "title": .string(try text(object["title"], "title")),
            "fields": .array(try fields.map { field in
                guard let field = field.objectValue else { throw Failure.invalid("field") }
                let options = isAbsent(field["options"]) ? [] : try array(field["options"], "options")
                return .object([
                    "key": .string(try text(field["key"], "key")),
                    "type": .string(try text(field["type"], "type")),
                    "title": .string(isAbsent(field["title"]) ? "" : try text(field["title"], "title")),
                    "description": .string(isAbsent(field["description"]) ? "" : try text(field["description"], "description")),
                    "options": .array(try options.map { option in
                        guard let option = option.objectValue else { throw Failure.invalid("option") }
                        return .object(["value": .string(try text(option["value"], "value")), "label": .string(try text(option["label"], "label"))])
                    }),
                ])
            }),
        ])
    }

    public static func digest(_ input: JSONValue) throws -> String {
        SHA256.hash(data: Data(try CanonicalJSON.serialize(input).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isAbsent(_ value: JSONValue?) -> Bool { value == nil || value == .null }
    private static func text(_ value: JSONValue?, _ name: String) throws -> String {
        guard let text = value?.stringValue else { throw Failure.invalid(name) }
        return text
    }
    private static func array(_ value: JSONValue?, _ name: String) throws -> [JSONValue] {
        guard let items = value?.arrayValue else { throw Failure.invalid(name) }
        return items
    }
    private static func texts(_ value: JSONValue?, _ name: String) throws -> [String] {
        try array(value, name).map { try text($0, name) }
    }
}

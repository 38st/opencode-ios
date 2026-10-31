// Sources: packages/schema/src/{integration,credential,mcp,permission-saved,plugin,skill,reference,command}.ts and
// packages/protocol/src/groups/{integration,worktree,config}.ts at v2.2.1. Connections carry no secret: an account is
// a credential's ID, label and sign-in method, and the first credential connection is the active one
// (packages/app/src/settings/providers/accounts.ts).
import Foundation
import OCFoundation

/// A provider, search service or MCP server that can be signed in to.
public struct IntegrationInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var name: String { string("name", default: id) }
    public var methods: [IntegrationMethod] { self["methods"]?.lossy(IntegrationMethod.self).values ?? [] }
    public var connections: [IntegrationConnection] { self["connections"]?.lossy(IntegrationConnection.self).values ?? [] }
    /// Credential connections, the active one first.
    public var accounts: [IntegrationConnection] { connections.filter { $0.type == "credential" } }
    public var environment: [IntegrationConnection] { connections.filter { $0.type == "env" } }
    public var isConnected: Bool { !connections.isEmpty }
    public var needsAuth: Bool { connections.contains { $0.needsAuth != nil } }
}

public struct IntegrationMethod: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    /// `oauth`, `command`, `key`, `external` or `env`. A key method has no ID.
    public var type: String { string("type") }
    public var methodID: String? { self["id"]?.stringValue }
    public var id: String { type + ":" + (methodID ?? "") + ":" + (self["label"]?.stringValue ?? "") }
    public var label: String {
        if let label = self["label"]?.stringValue, !label.isEmpty { return label }
        switch type {
        case "key": return localized("API key", comment: "Provider sign-in method")
        case "env": return localized("Environment variable", comment: "Provider sign-in method")
        case "command": return localized("Command", comment: "Provider sign-in method: run a command")
        default: return type.capitalized
        }
    }
    /// Questions the server asks before connecting, in the shape of a form field.
    public var form: FormInfo? {
        guard let fields = self["form"], !(fields.arrayValue ?? []).isEmpty else { return nil }
        return FormInfo(raw: .object(["id": .string(id), "fields": fields]))
    }
    public var command: [String] { strings("command") }
    public var names: [String] { strings("names") }
    /// The phone can start these; `external` and `env` are set up on the server machine.
    public var isEditable: Bool { ["key", "oauth", "command"].contains(type) }
}

public struct IntegrationConnection: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    /// `credential` or `env`.
    public var type: String { string("type") }
    public var id: String { type == "env" ? "env:" + name : string("id") }
    /// The credential ID, `cred_…`.
    public var credentialID: String { string("id") }
    public var label: String { string("label", default: name) }
    public var name: String { string("name") }
    /// `key`, `oauth` or `external`.
    public var method: String { string("method") }
    public var needsAuth: NeedsAuth? {
        guard let status = self["status"], status["status"]?.stringValue == "needs_auth" else { return nil }
        return NeedsAuth(message: status["message"]?.stringValue ?? localized("Sign in again"), url: status["url"]?.stringValue)
    }
    public struct NeedsAuth: Equatable, Sendable { public var message: String; public var url: String? }
}

/// `POST …/connect/oauth`.
public struct OAuthAttempt: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var attemptID: String { string("attemptID") }
    public var url: String { string("url") }
    public var instructions: String { string("instructions") }
    /// `code`: paste the code the page shows. `auto`: the server finishes by itself (a loopback callback or device code
    /// polling on the server machine).
    public var mode: String { string("mode", default: "auto") }
    public var expires: Double? { self["time"]?["expires"]?.wireNumber }
}

/// `POST …/connect/command`.
public struct CommandAttempt: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var attemptID: String { string("attemptID") }
    public var expires: Double? { self["time"]?["expires"]?.wireNumber }
}

/// The status of an OAuth or command attempt.
public enum AttemptStatus: Equatable, Sendable {
    case pending(message: String?), complete, failed(String), expired, unknown(String)
    public init(raw: JSONValue) {
        switch raw["status"]?.stringValue ?? "" {
        case "pending": self = .pending(message: raw["message"]?.stringValue)
        case "complete": self = .complete
        case "failed": self = .failed(raw["message"]?.stringValue ?? localized("Sign-in failed."))
        case "expired": self = .expired
        case let other: self = .unknown(other)
        }
    }
    public var isTerminal: Bool {
        switch self { case .pending, .unknown: false; default: true }
    }
}

/// An "Allow always" rule of one project.
public struct SavedPermission: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var projectID: String { string("projectID") }
    public var action: String { string("action") }
    public var resource: String { string("resource") }
    public var created: Double { self["time"]?["created"]?.wireNumber ?? 0 }
}

public extension WorktreeInfo {
    var strategy: String? { self["strategy"]?.stringValue }
    var name: String { URL(fileURLWithPath: directory).lastPathComponent }
}

public struct PluginInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { self["id"]?.stringValue ?? target ?? path ?? sourceType }
    /// `builtin`, `package`, `local` or `sdk`.
    public var sourceType: String { self["source"]?["type"]?.stringValue ?? "" }
    /// A package plugin's specifier, which `POST /api/plugin/update` takes.
    public var target: String? { self["source"]?["target"]?.stringValue }
    public var version: String? { self["source"]?["version"]?.stringValue }
    public var path: String? { self["source"]?["path"]?.stringValue }
    public var outdated: Bool { self["source"]?["outdated"]?.boolValue ?? false }
    public var updating: Bool { self["source"]?["updating"]?.boolValue ?? false }
    public var failure: String? {
        self["state"]?["status"]?.stringValue == "failed" ? self["state"]?["error"]?.stringValue ?? localized("Failed to load") : nil
    }
    public var features: [String] {
        let object = self["features"]?.objectValue ?? [:]
        return ["server", "tui", "rpc", "gui"].filter { object[$0]?.boolValue == true }
    }
}

public struct SkillInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id", default: name) }
    public var name: String { string("name") }
    public var description: String? { self["description"]?.stringValue }
    public var path: String { string("path") }
    public var content: String { string("content") }
    public var autoinvoke: Bool { self["autoinvoke"]?.boolValue ?? true }
}

public struct CommandInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { name }
    public var name: String { string("name") }
    public var description: String? { self["description"]?.stringValue }
}

public struct ReferenceInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { name }
    public var name: String { string("name") }
    public var path: String { string("path") }
    public var description: String? { self["description"]?.stringValue }
    public var hidden: Bool { self["hidden"]?.boolValue ?? false }
    /// `local <path>` or `git <repository>#<branch>`.
    public var source: String {
        let source = self["source"]
        if source?["type"]?.stringValue == "git" {
            return (source?["repository"]?.stringValue ?? "git") + (source?["branch"]?.stringValue.map { "#" + $0 } ?? "")
        }
        return source?["path"]?.stringValue ?? path
    }
}

/// One `GET /api/config` entry: a configuration document or a directory searched for agents, commands and skills.
public struct ConfigEntry: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { type + ":" + (path ?? "inline") }
    public var type: String { string("type") }
    public var path: String? { self["path"]?.stringValue }
    public var info: JSONValue? { self["info"] }
}

/// Settings screens of one server, in the desktop's order.
public enum ServerSettingsSection: String, CaseIterable, Identifiable, Sendable {
    case providers, mcp, permissions, agents, configuration, worktrees, projects, usage, administration
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .providers: localized("Providers")
        case .mcp: "MCP"
        case .permissions: localized("Permissions", comment: "Server settings section")
        case .agents: localized("Agents and tools")
        case .configuration: localized("Configuration")
        case .worktrees: localized("Worktrees")
        case .projects: localized("Projects")
        case .usage: localized("Usage statistics")
        case .administration: localized("Administration")
        }
    }
    public var icon: String {
        switch self {
        case .providers: "providers"
        case .mcp: "mcp"
        case .permissions: "shield"
        case .agents: "brain"
        case .configuration: "code"
        case .worktrees: "branch"
        case .projects: "folder"
        case .usage: "window-analytics"
        case .administration: "server"
        }
    }
    /// Words the switcher also matches.
    public var keywords: String {
        switch self {
        case .providers: "accounts api key sign in models integrations"
        case .mcp: "servers tools resources"
        case .permissions: "allow always saved rules"
        case .agents: "commands skills plugins references"
        case .configuration: "config opencode.json shell"
        case .worktrees: "workspaces branches"
        case .projects: "name icon colour color start script"
        case .usage: "stats tokens cost sessions prompts tools models"
        case .administration: "server version locations reload update"
        }
    }
}

/// Hides values whose keys look secret before a configuration document is shown.
public enum ConfigRedaction {
    public static let placeholder = "[redacted]"
    static let secretWords: Set<String> = ["token", "tokens", "secret", "secrets", "password", "passwd", "authorization",
                                           "credential", "credentials", "cookie", "auth"]
    /// Run-together names a case split cannot separate: "apikey", "APIKEY", "accesskey".
    static let compoundKeys = ["apikey", "accesskey", "secretkey", "privatekey", "authkey", "sessionkey"]
    /// Matches whole words, so names such as "keybinds" or "monkey" stay visible while "apiKey", "api_key",
    /// "X-Api-Key" and "OPENAI_API_KEY" are hidden.
    public static func isSecret(_ name: String) -> Bool {
        let words = words(name)
        if words.contains(where: secretWords.contains) { return true }
        if let last = words.last, compoundKeys.contains(where: { last == $0 || last == $0 + "s" }) { return true }
        return words.last == "key" || words.last == "keys"
    }
    public static func redact(_ value: JSONValue, secret: Bool = false) -> JSONValue {
        switch value {
        case .object(let fields):
            // Everything under a secret name stays hidden: `credentials: {user, pass}` hides both.
            return .object(Dictionary(uniqueKeysWithValues: fields.map { key, child in (key, redact(child, secret: secret || isSecret(key))) }))
        // A secret name over a list (`keys: [...]`) hides every value in it.
        case .array(let values): return .array(values.map { redact($0, secret: secret) })
        case .null: return value
        default: return secret ? .string(placeholder) : value
        }
    }
    /// "apiKey", "api_key", "API-KEY" and "OPENAI_API_KEY" all split into lower-case words.
    static func words(_ name: String) -> [String] {
        var words: [String] = [], current = ""
        var previous: Character?
        for character in name {
            if character == "_" || character == "-" || character == "." || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                if character.isUppercase, let previous, previous.isLowercase || previous.isNumber, !current.isEmpty {
                    words.append(current); current = ""
                }
                current.append(Character(character.lowercased()))
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

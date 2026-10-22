import Foundation
import OCFoundation

public enum PermissionDecision: String, Codable, Sendable { case once, always, reject }

public struct PromptFileInput: Codable, Sendable, Equatable {
    public var uri: String
    public var name: String?
    public var description: String?
    public var mention: JSONValue?
    public init(uri: String, name: String? = nil, description: String? = nil, mention: JSONValue? = nil) {
        self.uri = uri; self.name = name; self.description = description; self.mention = mention
    }
}

/// Prompts deliberately carry no model or agent selection; those belong to the prelude.
public struct PromptInput: Codable, Sendable, Equatable {
    public var text: String
    public var files: [PromptFileInput]?
    public var agents: [WireObject]?
    public var skills: [WireObject]?
    public var metadata: JSONValue?
    public var delivery: Delivery
    public var resume: Bool?
    public init(text: String, files: [PromptFileInput]? = nil, agents: [WireObject]? = nil,
                skills: [WireObject]? = nil, metadata: JSONValue? = nil, delivery: Delivery = .steer, resume: Bool? = nil) {
        self.text = text; self.files = files; self.agents = agents; self.skills = skills
        self.metadata = metadata; self.delivery = delivery; self.resume = resume
    }
    public func body(id: String) throws -> Data {
        var raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))
        raw.set("id", .string(id))
        return try JSONEncoder().encode(raw.omittingNullFields)
    }
}

public struct WritePrelude: Codable, Sendable, Equatable {
    public var agent: String?
    public var model: ModelRef?
    /// Set only after the user has confirmed the staged revert.
    public var commitRevert: Bool
    public init(agent: String? = nil, model: ModelRef? = nil, commitRevert: Bool = false) {
        self.agent = agent; self.model = model; self.commitRevert = commitRevert
    }
}

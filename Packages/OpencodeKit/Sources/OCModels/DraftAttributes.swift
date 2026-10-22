import Foundation

public struct DraftMention: Codable, Sendable, Hashable {
    public var kind: String
    public var value: String
    // Equal adjacent mentions must remain separate attributed runs. Optional
    // decoding keeps drafts written before token identities readable.
    public var tokenID: String?
    public var selection: LineSelection?
    public init(kind: String, value: String, selection: LineSelection? = nil) { self.kind = kind; self.value = value; self.selection = selection; tokenID = UUID().uuidString }
}
public enum MentionAttribute: CodableAttributedStringKey {
    public typealias Value = DraftMention
    public static let name = "app.opencode.mention"
}
public struct DraftAttributes: AttributeScope {
    public let foundation: AttributeScopes.FoundationAttributes
    public let mention: MentionAttribute
}

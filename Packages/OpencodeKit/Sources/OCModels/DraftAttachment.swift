import Foundation
import OCFoundation

public struct DraftAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let filename: String
    public let name: String
    public let mime: String
    public let mention: JSONValue?
    public init(id: String = UUID().uuidString, filename: String, name: String, mime: String, mention: JSONValue? = nil) {
        self.id = id; self.filename = filename; self.name = name; self.mime = mime; self.mention = mention
    }
}

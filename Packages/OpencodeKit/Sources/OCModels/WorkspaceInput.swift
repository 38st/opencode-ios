import Foundation
import OCFoundation

public struct FileEntry: WireValue, Identifiable {
    public enum Kind: Equatable, Sendable { case file, directory, unknown(String) }
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { path }
    public var path: String { string("path") }
    public var type: Kind { switch string("type") { case "file": .file; case "directory": .directory; case let value: .unknown(value) } }
}
public struct WorktreeInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { directory }
    public var directory: String { string("directory") }
    public var branch: String? { self["branch"]?.stringValue }
}
public struct WorktreeFailure: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public let forceRequired: Bool
    public var errorDescription: String? { message }
    public init(raw: JSONValue) {
        let data = raw["data"] ?? raw
        message = data["message"]?.stringValue ?? localized("Failed to create worktree")
        forceRequired = data["forceRequired"]?.boolValue ?? false
    }
}

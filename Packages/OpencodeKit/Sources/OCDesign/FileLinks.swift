import SwiftUI
import OCModels

public struct OCFileLinks {
    public let open: (String) -> Void
    public let comment: ((LineComment) -> Void)?
    public let comments: (String) -> [LineComment]
    public let updateComment: (LineComment) -> Void
    public let removeComment: (String) -> Void
    /// Returns the subset of candidate links that name existing files. The host caches and batches the lookups.
    public let existing: ([String]) async -> Set<String>
    /// The same answer without waiting, when every candidate is already cached; otherwise nil.
    public let known: ([String]) -> Set<String>?
    public init(open: @escaping (String) -> Void, existing: @escaping ([String]) async -> Set<String>,
                known: @escaping ([String]) -> Set<String>? = { _ in nil }, comment: ((LineComment) -> Void)? = nil,
                comments: @escaping (String) -> [LineComment] = { _ in [] }, updateComment: @escaping (LineComment) -> Void = { _ in }, removeComment: @escaping (String) -> Void = { _ in }) {
        self.open = open; self.existing = existing; self.known = known; self.comment = comment; self.comments = comments
        self.updateComment = updateComment; self.removeComment = removeComment
    }
}
private struct FileLinksKey: EnvironmentKey { static let defaultValue: OCFileLinks? = nil }
extension EnvironmentValues {
    public var ocFileLinks: OCFileLinks? { get { self[FileLinksKey.self] } set { self[FileLinksKey.self] = newValue } }
}

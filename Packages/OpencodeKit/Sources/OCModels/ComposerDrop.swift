import Foundation
import UniformTypeIdentifiers

/// What an item dropped on the composer becomes. Attachments keep the composer's limits and errors; text goes in
/// at the cursor; a file dragged from the Files tab becomes an @file mention.
public enum ComposerDrop: Equatable, Sendable {
    case mention
    /// Load this type identifier and attach it.
    case attachment(String)
    case text(String)
    /// Audio, video and other types the server drops.
    case refused

    /// The in-app type a Files row carries. Its payload starts with this process's token, so another app's drop that
    /// claims the type is refused.
    public static let mentionType = "dev.opencodeios.file-mention"
    private static let processToken = UUID().uuidString
    public static func mentionPayload(_ path: String) -> Data { Data((processToken + "\n" + path).utf8) }
    /// The absolute path, or nil when the payload did not come from this process.
    public static func mentionPath(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8), let newline = text.firstIndex(of: "\n"), text[..<newline] == processToken else { return nil }
        let path = String(text[text.index(after: newline)...])
        return path.hasPrefix("/") ? path : nil
    }

    /// - Parameter named: whether the item names a file (`suggestedName` with an extension), which makes text a
    ///   text file to attach rather than text to insert.
    public static func classify(_ types: [String], named: String? = nil) -> ComposerDrop {
        if types.contains(mentionType) { return .mention }
        let known = types.compactMap { id in UTType(id).map { (id, $0) } }
        if let url = known.first(where: { $0.1.conforms(to: .fileURL) }) { return .attachment(url.0) }
        if let media = known.first(where: { $0.1.conforms(to: .image) || $0.1.conforms(to: .pdf) }) { return .attachment(media.0) }
        if let text = known.first(where: { $0.1.conforms(to: .plainText) }) ?? known.first(where: { $0.1.conforms(to: .text) }) {
            let file = named.map { !($0 as NSString).pathExtension.isEmpty } ?? false
            return file ? .attachment(text.0) : .text(text.0)
        }
        return .refused
    }
}

import Foundation
import OCFoundation
import OCModels

public typealias DraftAttachment = OCModels.DraftAttachment
public enum DraftError: Error, Sendable { case invalidPath, attachmentTooLarge }

public extension Draft {
    init(id: String = UUID().uuidString, serverID: String, sessionID: String? = nil, directory: String? = nil,
         attributedText: AttributedString, attachments: [DraftAttachment] = [], delivery: String = "steer", updatedAt: Date = Date(), options: ComposerOptions = .init(), comments: [LineComment] = []) throws {
        self.init(id: id, serverID: serverID, sessionID: sessionID, directory: directory,
            text: try JSONEncoder().encode(attributedText, configuration: DraftAttributes.self),
            attachments: try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(attachments)), delivery: delivery, updatedAt: updatedAt, options: options, comments: comments)
    }
    var attributedText: AttributedString {
        get throws { try JSONDecoder().decode(AttributedString.self, from: text, configuration: DraftAttributes.self) }
    }
    var attachmentFiles: [DraftAttachment] {
        get throws { try attachments.decoded([DraftAttachment].self) }
    }
}

public extension DraftStore {
    func importAttachment(_ source: URL, draftID: String, mime: String, name: String? = nil) throws -> DraftAttachment {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        return try storeAttachment(data, draftID: draftID, mime: mime, name: name ?? source.lastPathComponent)
    }
    func storeAttachment(_ data: Data, draftID: String, mime: String, name: String, mention: JSONValue? = nil) throws -> DraftAttachment {
        guard data.count <= 20 * 1024 * 1024 else { throw DraftError.attachmentTooLarge }
        let filename = UUID().uuidString
        let destination = try filesDirectory(draftID).appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
        return .init(filename: filename, name: name, mime: mime, mention: mention)
    }
    func attachmentURL(_ attachment: DraftAttachment, draftID: String) throws -> URL {
        guard validComponent(attachment.filename) else { throw DraftError.invalidPath }
        return try filesDirectory(draftID).appendingPathComponent(attachment.filename)
    }
    func promptFiles(_ draft: Draft) throws -> [PromptFileInput] {
        try draft.attachmentFiles.map { file in
            let data = try Data(contentsOf: attachmentURL(file, draftID: draft.id))
            return PromptFileInput(uri: "data:\(file.mime);base64,\(data.base64EncodedString())", name: file.name, mention: file.mention)
        }
    }
    internal func removeFiles(_ id: String) throws {
        let url = try filesDirectory(id)
        try FileManager.default.removeItem(at: url)
    }
    private func filesDirectory(_ id: String) throws -> URL {
        guard validComponent(id) else { throw DraftError.invalidPath }
        let root = try filesRoot ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "Drafts")
        let directory = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }
}

import Foundation
import OCFoundation
import OCModels
import OCPersistence

extension ReadStore {
    /// A rejected create keeps its immutable outbox bytes until the recovered draft is sent.
    /// This also runs on launch, so a rejection while the app is closing cannot lose input.
    func recoverFailedCreation(_ create: OutboxEntry, entries: [OutboxEntry]) async throws {
        guard failedCreationDirectories[create.id] == nil, let drafts,
              let body = try? JSONDecoder().decode(JSONValue.self, from: create.body),
              let directory = body["location"]?["directory"]?.stringValue else { return }
        let composer = composers["directory:" + directory]
        try await composer?.flush()
        let existing = try await drafts.load(serverID: serverID, directory: directory)
        if var existing, existing.options.creatingSessionID == create.id {
            existing.options.creatingSessionID = nil; existing.options.recoveringCreateID = create.id
            await drafts.save(existing); try await drafts.flush(); try await composer?.reload()
        } else if existing == nil,
           let prompt = entries.first(where: { $0.sessionID == create.id && $0.operation == "prompt" }),
           let input = try? JSONDecoder().decode(JSONValue.self, from: prompt.body) {
            let id = UUID().uuidString
            var files: [DraftAttachment] = []
            for file in input["files"]?.arrayValue ?? [] {
                guard let uri = file["uri"]?.stringValue, uri.hasPrefix("data:"),
                      let comma = uri.firstIndex(of: ","), let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { continue }
                let mime = String(uri.dropFirst(5).prefix { $0 != ";" })
                files.append(try await drafts.storeAttachment(data, draftID: id, mime: mime, name: file["name"]?.stringValue ?? "Attachment"))
            }
            var options = ComposerOptions(agent: input["metadata"]?["agent"]?.stringValue, model: ComposerInput.restoreModel(input["metadata"]))
            options.recoveringCreateID = create.id
            let draft = try Draft(id: id, serverID: serverID, directory: directory,
                                  attributedText: ComposerInput.restoreText(input), attachments: files, options: options)
            await drafts.save(draft); try await drafts.flush()
            try await composer?.reload()
        }
        failedCreationDirectories[create.id] = directory
    }
}

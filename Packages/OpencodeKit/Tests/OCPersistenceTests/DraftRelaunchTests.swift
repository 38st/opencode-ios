import Foundation
import Testing
import OCModels
import OCFoundation
import OCPersistence

@Test func attributedDraftAndOwnedAttachmentSurviveRelaunchAndSessionSwitch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("cache.sqlite"), files = root.appendingPathComponent("Drafts")
    let writer = try PersistenceWriter(url: url), store = DraftStore(writer: writer, filesRoot: files)
    var text = AttributedString("Read @main.swift")
    if let range = text.range(of: "@main.swift") { text[range][MentionAttribute.self] = DraftMention(kind: "file", value: "main.swift") }
    text.inlinePresentationIntent = .stronglyEmphasized
    let data = Data("attachment contents".utf8), id = UUID().uuidString
    let attachment = try await store.storeAttachment(data, draftID: id, mime: "text/plain", name: "main.swift")
    let options = ComposerOptions(shell: true, agent: "custom", model: .init(raw: .object(["id": .string("m"), "providerID": .string("p"), "variant": .string("high")])), editingOutboxID: "failed")
    let draft = try Draft(id: id, serverID: "server", sessionID: "session", attributedText: text, attachments: [attachment], delivery: "queue", options: options)
    await store.save(draft)
    let directory = try Draft(serverID: "server", directory: "/new/project", attributedText: AttributedString("not yet created"))
    await store.save(directory); try await store.flush()
    let reopened = DraftStore(writer: try PersistenceWriter(url: url), filesRoot: files)
    let restored = try #require(try await reopened.load(serverID: "server", sessionID: "session"))
    #expect(try restored.attributedText == text)
    #expect(restored.delivery == "queue")
    #expect(restored.options == options)
    #expect(try await reopened.promptFiles(restored).first?.uri == "data:text/plain;base64," + data.base64EncodedString())
    #expect(try await reopened.load(serverID: "server", directory: "/new/project")?.attributedText == AttributedString("not yet created"))
    #expect(try await reopened.load(serverID: "other", sessionID: "session") == nil)
    await #expect(throws: DraftError.self) { try await reopened.storeAttachment(data, draftID: "../escape", mime: "text/plain", name: "file") }
    try await reopened.delete(restored)
    await reopened.save(restored); try await reopened.flush()
    #expect(try await reopened.load(serverID: "server", sessionID: "session") == nil)
    #expect(!FileManager.default.fileExists(atPath: files.appendingPathComponent(id).path))
}

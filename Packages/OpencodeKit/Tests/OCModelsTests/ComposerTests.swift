import Foundation
import Testing
import OCFoundation
import OCModels
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

@Test func mentionsUseUTF16AndRestoreEveryToken() throws {
    var text = AttributedString("😀 e\u{301}漢字 @src/文件.swift 👩🏽‍💻 @reviewer 日本語 @lint @docs")
    for (label, kind, value) in [("@src/文件.swift", "file", "src/文件.swift"), ("@reviewer", "agent", "reviewer"), ("@lint", "skill", "lint"), ("@docs", "reference", "/references/documentation")] {
        let range = try #require(text.range(of: label)); text[range][MentionAttribute.self] = .init(kind: kind, value: value)
    }
    let input = ComposerInput.encode(text, directory: "/a b", agent: "build", model: nil)
    let raw = try JSONDecoder().decode(JSONValue.self, from: input.body(id: "msg_test"))
    let plain = String(text.characters) as NSString
    for key in ["files", "agents", "skills"] {
        for item in raw[key]?.arrayValue ?? [] {
            let mention = try #require(item["mention"]), start = try #require(mention["start"]?.wireInt), end = try #require(mention["end"]?.wireInt)
            #expect(plain.substring(with: NSRange(location: start, length: end - start)) == mention["text"]?.stringValue)
        }
    }
    #expect(input.files?.first?.uri == "file:///a%20b/src/%E6%96%87%E4%BB%B6.swift")
    #expect(raw["skills"]?.arrayValue?.first?.objectValue?.keys.sorted() == ["id", "mention"])
    let restored = ComposerInput.restoreText(raw)
    #expect(String(restored.characters) == String(text.characters))
    #expect(ComposerInput.encode(restored, directory: "/a b", agent: "build", model: nil) == input)
}

@Test func adjacentEqualMentionsRemainDistinctAndLegacyDraftsDecode() throws {
    var first = AttributedString("@file.swift"), second = AttributedString("@file.swift")
    first[MentionAttribute.self] = .init(kind: "file", value: "file.swift")
    second[MentionAttribute.self] = .init(kind: "file", value: "file.swift")
    first.append(second)
    #expect(first.runs.count == 2)
    let input = ComposerInput.encode(first, directory: "/project", agent: nil, model: nil)
    #expect(input.files?.count == 2)
    let raw = try JSONDecoder().decode(JSONValue.self, from: input.body(id: "id"))
    #expect(ComposerInput.restoreText(raw).runs.count == 2)
    let legacy = try JSONDecoder().decode(DraftMention.self, from: Data(#"{"kind":"file","value":"file.swift"}"#.utf8))
    #expect(legacy.kind == "file" && legacy.value == "file.swift" && legacy.tokenID == nil)
}

@Test func invalidMentionOffsetsArePlainText() {
    let raw: JSONValue = .object(["text": .string("😀 @agent"), "agents": .array([.object(["name": .string("agent"), "mention": .object(["start": .integer(1), "end": .integer(8), "text": .string("@agent")])])])])
    #expect(ComposerInput.restoreText(raw).runs.allSatisfy { $0[MentionAttribute.self] == nil })
}

@Test func directoryAndReferenceTokensRestoreUsingTheCatalog() throws {
    var text = AttributedString("@docs @Sources/")
    text[try #require(text.range(of: "@docs"))][MentionAttribute.self] = .init(kind: "reference", value: "/references/docs")
    text[try #require(text.range(of: "@Sources/"))][MentionAttribute.self] = .init(kind: "file", value: "Sources/")
    let input = ComposerInput.encode(text, directory: "/project", agent: nil, model: nil)
    let raw = try JSONDecoder().decode(JSONValue.self, from: input.body(id: "id"))
    let references: JSONValue = .array([.object(["name": .string("docs"), "path": .string("/references/docs")])])
    let restored = ComposerInput.restoreText(raw, references: references)
    #expect(restored.runs.compactMap { $0[MentionAttribute.self]?.kind } == ["reference", "file"])
    #expect(ComposerInput.encode(restored, directory: "/project", agent: nil, model: nil) == input)
}

@Test(arguments: [("@", true), ("a @foo", true), ("a@foo", false), ("(@foo", false), ("@foo@bar", false), ("/model", true), ("/model ", false), ("a /model", false)])
func composerTriggerRules(_ text: String, _ expected: Bool) { #expect((ComposerTrigger.detect(text) != nil) == expected) }

@Test func restoredMentionsDoNotReopenSuggestions() {
    var text = AttributedString("@sample.txt")
    text[MentionAttribute.self] = .init(kind: "file", value: "sample.txt")
    #expect(ComposerTrigger.detect(text) == nil)
    #expect(ComposerTrigger.detect(text, caret: 4) == nil)
    text.append(AttributedString(" @next"))
    #expect(ComposerTrigger.detect(text)?.query == "next")
}

@Test func contextSuggestionsPreserveCategoryAndServerOrder() {
    let refs: JSONValue = .array([.object(["name": .string("docs"), "path": .string("/docs")]), .object(["name": .string("secret"), "path": .string("/secret"), "hidden": .bool(true)])])
    let skills: JSONValue = .array([.object(["id": .string("lint")])])
    let agents = [AgentInfo(raw: .object(["name": .string("build"), "mode": .string("primary")])), AgentInfo(raw: .object(["name": .string("explore"), "mode": .string("subagent")]))]
    let files = ["z.swift", "a.swift"].map { FileEntry(raw: .object(["path": .string($0), "type": .string("file")])) }
    let values = ComposerSuggestions.context(query: "", references: refs, skills: skills, agents: agents, files: files)
    #expect(values.map(\.id) == ["reference:docs", "skill:lint", "agent:explore", "file:z.swift", "file:a.swift"])
    #expect(ComposerSuggestions.matches("documentation", query: "dcm"))
    #expect(!ComposerSuggestions.matches("documentation", query: "zcm"))
    #expect(ComposerSuggestions.context(query: "description", references: nil,
        skills: .array([.object(["id": .string("lint"), "description": .string("description")])]), agents: [], files: []).isEmpty)
}

@Test func clientCommandsRespectSessionAndAgentAvailability() {
    #expect(ComposerCommand.available(session: false, showAgent: false) == [.new, .model])
    #expect(ComposerCommand.available(session: true, showAgent: true) == ComposerCommand.allCases)
    #expect(ComposerCommand.available(session: true, showAgent: false, hasPrompts: false, reverted: false) == [.new, .model])
    #expect(ComposerCommand.available(session: true, showAgent: false, hasPrompts: false, reverted: true) == [.new, .redo, .model])
    #expect(ComposerCommand.new.description.isEmpty)
    let result = ComposerSuggestions.commands(query: "", server: .array([.object(["name": .string("review")])]), session: true, showAgent: false)
    #expect(result.first?.serverCommand == "review")
    #expect(!result.contains { $0.command == .agent })
    #expect(ComposerSuggestions.commands(query: "choose", server: nil, session: true, showAgent: false).map(\.command) == [.model])
    #expect(ComposerSuggestions.commands(query: "reduce", server: nil, session: true, showAgent: false).isEmpty)
}

@Test func deliveryAndShellNeverInterruptBeforeAdmission() {
    #expect(ComposerDelivery.action(running: false, blank: false, shell: false, preference: .queue) == .send(.steer, interrupt: false))
    #expect(ComposerDelivery.action(running: true, blank: false, shell: false, preference: .queue) == .send(.queue, interrupt: false))
    #expect(ComposerDelivery.action(running: true, blank: false, shell: false, preference: .queue, alternate: true) == .send(.steer, interrupt: false))
    #expect(ComposerDelivery.action(running: true, blank: false, shell: false, preference: .queue, interrupt: true) == .send(.steer, interrupt: true))
    #expect(ComposerDelivery.action(running: true, blank: true, shell: true, preference: .queue) == .stop)
    #expect(ComposerDelivery.action(running: true, blank: false, shell: true, preference: .queue) == .unqueueable)
}

@Test func attachmentsCanonicalBase64SizeAndType() async throws {
    let data = Data("漢字 e\u{301} 😀".utf8)
    let file = try await AttachmentProcessing.prepare(data, mime: "text/plain", name: "notes.txt")
    #expect(file.dataURL == "data:text/plain;base64," + data.base64EncodedString())
    let pdf = Data("%PDF-1.4\nOriginal PDF bytes".utf8)
    let document = try await AttachmentProcessing.prepare(pdf, mime: "application/pdf", name: "document.pdf")
    #expect(document.data == pdf && document.mime == "application/pdf")
    await #expect(throws: AttachmentError.self) { try await AttachmentProcessing.prepare(Data(repeating: 0, count: 20 * 1024 * 1024 + 1), mime: "text/plain", name: "large") }
    await #expect(throws: AttachmentError.self) { try await AttachmentProcessing.prepare(Data([0, 1, 2]), mime: "audio/wav", name: "audio.wav") }
}

@Test func largeImageDownscalesAndHEICConvertsToJPEG() async throws {
    let context = try #require(CGContext(data: nil, width: 2400, height: 1200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let image = try #require(context.makeImage())
    for type in [UTType.png, UTType.heic] {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); #expect(CGImageDestinationFinalize(destination))
        let prepared = try await AttachmentProcessing.prepare(data as Data, mime: type.preferredMIMEType ?? "", name: "photo." + (type.preferredFilenameExtension ?? ""))
        let source = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let output = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(output.width == 2000 && output.height == 1000)
        #expect(prepared.mime == (type == .png ? "image/png" : "image/jpeg"))
    }
}

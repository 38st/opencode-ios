#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCFoundation
import OCModels
import OCDesign
import OCRender
import OCNetworking
import OCPersistence
import OCSync
import FeatureReview
import FeatureFiles
import FeatureComposer
@testable import FeatureTranscript

@MainActor @Suite(.serialized) struct ReviewSnapshots {
    @Test func changesStates() async throws {
        for state in ["working", "branch", "last-turn", "turn", "empty", "empty-branch", "empty-last-turn", "no-git", "loading", "error", "reviewed", "filter", "truncated", "too-large", "binary", "image", "removed-image", "image-error", "creating", "create-failure"] {
            let store = try store(state)
            let model = store.review(sessionID: "s", directory: "/workspace")
            let composer = store.composer(sessionID: "s", directory: "/workspace")
            await composer.load()
            model.appear()
            if state != "loading" { await wait { model.loaded } }
            if state == "creating" || state == "create-failure" { model.initializeGit() }
            if state == "branch" || state == "empty-branch" { model.choose(.branch) }
            if state == "last-turn" || state == "empty-last-turn" { model.choose(.lastTurn) }
            if state == "turn" { model.choose(.turn("msg_turn")) }
            if state == "reviewed", let file = model.files.first { model.mark(file, reviewed: true) }
            if state == "filter" { model.filter = "swift" }
            if state != "reviewed" { model.expandAll(true) }
            if state == "image" || state == "image-error" { await wait { !model.images.isEmpty || !model.imageErrors.isEmpty } }
            await capture(ReviewScreen(model: model, composer: composer, openFile: { _, _ in }), name: "changes-" + state)
            model.disappear(); await store.stop()
        }
    }
    @Test func turnCards() async throws {
        for state in ["loading", "collapsed", "expanded"] {
            let store = try store(state), model = store.turnDiff(sessionID: "s", from: "msg_turn")
            if state != "loading" { model.load(); await wait { model.loaded } }
            let row = TimelineRow(id: "turn", kind: .turnEnd, files: ["Example.swift", "src/example.ts", "data.json", "README.md", "image.png", "binary.bin", "removed.txt"], turnFrom: "msg_turn")
            await capture(TurnChangesCard(row: row, model: model, expanded: state == "expanded", open: { _ in }), name: "turn-" + state)
            await store.stop()
        }
    }
    @Test func rendererStates() async {
        for (name, path, patch) in [("swift", "Example.swift", Self.patch), ("typescript", "example.ts", Self.fixture("review-typescript.patch")), ("json", "data.json", Self.fixture("review-json.patch"))] {
            for split in [false, true] { for wrap in [true, false] {
                await capture(OCDiffView([.init(path: path, text: patch)], split: split, wrap: wrap), name: "diff-\(name)-\(split ? "split" : "unified")-\(wrap ? "wrap" : "nowrap")")
            } }
        }
        let context = "--- a\n+++ b\n@@ -1,31 +1,31 @@\n" + (1...15).map { " line \($0)\n" }.joined() + "-old\n+new\n" + (17...31).map { " line \($0)\n" }.joined()
        for all in [false, true] { await capture(OCDiffView([.init(path: "context.swift", text: context)], showAll: all), name: all ? "context-expanded" : "context-collapsed") }
        await capture(DiffCardView(file: "Example.swift", patch: Self.patch, additions: 2, deletions: 2, expanded: true), name: "tool-diff")
        let source = "struct Example {\n    let name = \"name\"\n    let value = 2\n}\n"
        let search = await CodeSearchResult.find("name", in: source)
        await capture(OCDiffView([.init(path: "Example.swift", text: source, source: true)], search: search, currentMatch: search.matches.first), name: "files-find-in-file")
    }
    @Test func comments() async throws {
        let comment = LineComment(id: "comment", file: "Example.swift", selection: .init(start: 2, end: 3), comment: "Keep the public name and document the new value.", time: .distantPast, preview: "    let value = 2\n    let title = \"Updated\"")
        for editing in [false, true] {
            await capture(OCLineCommentEditor(file: comment.file, selection: comment.selection, initialText: editing ? comment.comment : "", editing: editing, submit: { _ in }, cancel: {}), name: editing ? "comment-edit" : "comment-empty")
        }
        await capture(OCCommentCard(comment, edit: {}, delete: {}), name: "comment-card")
        await capture(OCDiffView([.init(path: comment.file, text: Self.patch)], comments: [comment], selected: comment.selection), name: "comment-annotation")
        await capture(OCLineCommentEditor(file: comment.file, selection: comment.selection, initialText: comment.comment, editing: false, submit: { _ in }, cancel: {}), name: "comment-ready")
        let old = LineComment(id: "deleted", file: comment.file, selection: .init(start: 2, end: 3, side: .deletions), comment: "Preserve this old behavior.", time: .distantPast, deletedText: "    let value = 1\n    let title = \"Original\"")
        await capture(OCDiffView([.init(path: comment.file, text: Self.patch)], split: true, comments: [old, comment]), name: "comment-split-sides")
        await capture(OCDiffView([.init(path: comment.file, text: Self.patch)], split: true, selected: comment.selection, inlineComment: comment,
                                inlineEditor: AnyView(OCLineCommentEditor(file: comment.file, selection: comment.selection, initialText: comment.comment, editing: true, showsFile: false, submit: { _ in }, cancel: {}))), name: "comment-inline-editor")
        let store = try store("working"), model = store.composer(sessionID: "s", directory: "/workspace")
        await model.load(); model.addComment(comment)
        await capture(ComposerDock(store: store, model: model), name: "comment-composer")
        let input = ComposerInput.encode(AttributedString("Review this change"), directory: "/workspace", comments: [comment], agent: nil, model: nil)
        let sent = try JSONDecoder().decode(JSONValue.self, from: input.body(id: "prompt"))
        await capture(ScrollView { SentPrompt(.init(raw: sent)).frame(maxWidth: .infinity, alignment: .trailing) }, name: "comment-sent")
        let many = (1...6).map { LineComment(id: "comment-\($0)", file: comment.file, selection: .init(start: $0), comment: "Review comment \($0)", time: .distantPast) }
        for text in ["", "Review these comments"] {
            let input = ComposerInput.encode(AttributedString(text), directory: "/workspace", comments: many, agent: nil, model: nil)
            let sent = try JSONDecoder().decode(JSONValue.self, from: input.body(id: "prompt"))
            await capture(ScrollView { SentPrompt(.init(raw: sent)).frame(maxWidth: .infinity, alignment: .trailing) }, name: text.isEmpty ? "comment-only" : "comment-show-more")
        }
        await store.stop()
    }
    @Test func files() async throws {
        for state in ["tree", "find", "source", "markdown", "binary", "large-file", "quick-look", "image", "list-error", "not-found", "file-loading"] {
            let store = try store(state), model = store.files(sessionID: "s", directory: "/workspace")
            let composer = store.composer(sessionID: "s", directory: "/workspace")
            await composer.load(); model.appear()
            await wait { model.children[""] != nil || model.listingErrors.contains("") }
            if state == "find" { model.query = "Example"; await wait { !model.results.isEmpty } }
            if !["tree", "find", "list-error"].contains(state) {
                let file = state == "markdown" ? "README.md" : state == "quick-look" ? "document.pdf" : state == "binary" ? "binary.bin" : ["image", "image-error", "removed-image"].contains(state) ? "image.png" : "Example.swift"
                if let path = ReviewPath(file, root: .location, location: "/workspace", project: "/workspace") { model.open(path, selection: .init(start: 2, end: 3)); await wait { !model.loading } }
            }
            await capture(FilesScreen(model: model, composer: composer), name: "files-" + state)
            model.disappear(); await store.stop()
        }
    }
    @Test func contextPanel() async throws {
        for state in ["known-limit", "unknown-limit", "no-assistant"] {
            let store = try store("context-" + state)
            Self.seedContext(store, state: state)
            await capture(ContextPanel(store: store, sessionID: "s").environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!), name: "context-" + state)
            await store.stop()
        }
        let store = try store("context-sheet")
        Self.seedContext(store, state: "known-limit")
        await capture(ContextSheet(store: store, sessionID: "s") {}.environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!), name: "context-sheet", widths: [393])
        await store.stop()
    }
    /// A session with usage, todos, MCP servers, a system prompt and a subagent.
    static func seedContext(_ store: ReadStore, state: String) {
        let model: JSONValue = .object(["id": .string(state == "unknown-limit" ? "mock-preview" : "mock-1"), "providerID": .string("mock"), "variant": .string("careful")])
        let location: JSONValue = .object(["directory": .string("/Users/Shared/opencode-ios")])
        let time = { (created: Double) -> JSONValue in .object(["created": .double(created), "updated": .double(created + 600_000)]) }
        let info = SessionInfo(raw: .object(["id": .string("s"), "title": .string("Polish the iPad workspace"), "agent": .string("build"), "model": model, "cost": .double(0.4213),
                                             "location": location, "time": time(1_792_000_000_000)]))
        let child = SessionInfo(raw: .object(["id": .string("ses_child"), "parentID": .string("s"), "title": .string("Review the switcher"), "cost": .double(0.0571),
                                              "location": location, "time": time(1_792_000_300_000)]))
        let todos: JSONValue = .array([.object(["content": .string("Add the menu bar"), "status": .string("completed")]), .object(["content": .string("Build the switcher"), "status": .string("in_progress")]),
                                       .object(["content": .string("Fill the Context tab"), "status": .string("pending")])])
        var messages: [SessionMessage] = [.init(raw: .object(["id": .string("msg_0"), "type": .string("system"), "text": .string("You are opencode, an interactive coding agent."), "time": .object(["created": .double(1_792_000_000_000)])])),
                                          .init(raw: .object(["id": .string("msg_1"), "type": .string("user"), "text": .string("Polish the iPad workspace"), "time": .object(["created": .double(1_792_000_010_000)])]))]
        if state != "no-assistant" {
            messages.append(.init(raw: .object(["id": .string("msg_2"), "type": .string("assistant"), "model": model, "agent": .string("build"), "time": .object(["created": .double(1_792_000_420_000)]),
                "tokens": .object(["input": .integer(52_400), "output": .integer(3_120), "reasoning": .integer(1_880), "cache": .object(["read": .integer(18_200), "write": .integer(940)])]),
                "content": .array([.object(["type": .string("tool"), "id": .string("tool_1"), "name": .string("todowrite"), "state": .object(["status": .string("completed"), "input": .object(["todos": todos])])])])])))
        }
        store.seed(info: info, messages: messages)
        store.seed(info: child, messages: [])
        let catalog = store.catalog(for: Location(directory: "/Users/Shared/opencode-ios"))
        catalog.models.seed([ModelInfo(raw: .object(["id": .string("mock-1"), "providerID": .string("mock"), "name": .string("Mock Sonnet"), "limit": .object(["context": .integer(200_000), "output": .integer(16_000)])]))])
        catalog.providers.seed([ProviderInfo(raw: .object(["id": .string("mock"), "name": .string("Mock Provider")]))])
        catalog.mcp.seed([MCPServer(raw: .object(["name": .string("filesystem"), "status": .object(["status": .string("connected")])])),
                          MCPServer(raw: .object(["name": .string("github"), "status": .object(["status": .string("failed"), "error": .string("Token expired")])]))])
        catalog.vcs.seed(.object(["branch": .object(["current": .string("ipad-workspace")])]))
    }
    private func store(_ state: String) throws -> ReadStore {
        let client = APIClient(baseURL: try #require(URL(string: "http://127.0.0.1:1")), transport: ReviewSnapshotTransport(state: state))
        let store = ReadStore(serverID: "snapshot-" + state, cache: CacheStore(writer: try PersistenceWriter()), client: { client })
        store.seed(info: .init(raw: .object(["id": .string("s"), "location": .object(["directory": .string("/workspace")])])), messages: [])
        return store
    }
    private func wait(_ predicate: () -> Bool) async {
        for _ in 0..<500 { if predicate() { return }; try? await Task.sleep(for: .milliseconds(10)) }
    }
    private func capture<V: View>(_ view: V, name: String) async { await capture(view, name: name, widths: [393, 820]) }
    /// References keep the names `capture(_:name:)` gave them.
    private func capture<V: View>(_ view: V, name: String, widths: [Double]) async {
        if let filter = ProcessInfo.processInfo.environment["OC_SNAPSHOT_FILTER"], !name.contains(filter) { return }
        for width in widths { for dark in [false, true] { for accessibility in [false, true] {
            let size = CGSize(width: width, height: 852)
            let controller = UIHostingController(rootView: view
                .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.background))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            controller.traitOverrides.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
            controller.view.frame = CGRect(origin: .zero, size: size)
            // The app-hosted snapshot bundle always has a scene, as in ComposerSnapshots.
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                Issue.record("Snapshots need a connected window scene"); return
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size); window.rootViewController = controller; window.makeKeyAndVisible()
            controller.view.layoutIfNeeded(); try? await Task.sleep(for: .milliseconds(350))
            await DiffPreparation.settle()
            let label = "\(name)-\(dark ? "dark" : "light")-\(Int(width))-\(accessibility ? "accessibility5" : "default")"
            let strategy: Snapshotting<UIViewController, UIImage> = .image(size: size)
            if ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1" {
                if let result = verifySnapshot(of: controller as UIViewController, as: strategy, named: label, record: true, testName: "capture(_:name:)"), !result.contains("Record mode is on") { Issue.record(Comment(rawValue: result)) }
            } else { assertSnapshot(of: controller as UIViewController, as: strategy, named: label, testName: "capture(_:name:)") }
            window.isHidden = true
        } } }
    }
    nonisolated static var patch: String { fixture("review-swift.patch") }
    nonisolated static var imageFixture: Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? Data(contentsOf: root.appendingPathComponent("Fixtures/source/m4/image.png"))) ?? Data()
    }
    nonisolated static func fixture(_ name: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("Fixtures/source/m4/" + name), encoding: .utf8)) ?? "Missing fixture: " + name
    }
}

private actor ReviewSnapshotTransport: HTTPTransport {
    let state: String
    init(state: String) { self.state = state }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let path = request.url?.path ?? "", url = try #require(request.url)
        if state == "loading" || state == "creating" && path == "/api/vcs/init" || state == "file-loading" && path.contains("/fs/read/") { try await Task.sleep(for: .seconds(30)) }
        if state == "create-failure" && path == "/api/vcs/init" || state == "list-error" && path == "/api/fs/list" || ["not-found", "image-error"].contains(state) && path.contains("/fs/read/") {
            return .init(data: Data("{\"_tag\":\"FileNotFoundError\",\"message\":\"Request failed\"}".utf8), response: try #require(HTTPURLResponse(url: url, statusCode: state == "not-found" ? 404 : 500, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
        }
        if state == "error" { return .init(data: Data("{\"message\":\"Choose a review base\"}".utf8), response: try #require(HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))) }
        if path.contains("/fs/read/") {
            let text = state == "markdown" ? "# Review fixture\n\nA **Markdown** preview with a list.\n\n- Review the source\n- Add a comment" : "struct Example {\n    let value = 2\n    let title = \"Updated\"\n}\n"
            let data = state == "binary" ? Data([0, 1, 2, 3]) : state == "image" ? ReviewSnapshots.imageFixture : Data(text.utf8)
            let headers = ["Content-Type": "text/plain", "ETag": "snapshot", "Content-Range": "bytes 0-\(data.count - 1)/\(state == "large-file" ? 3_000_000 : data.count)"]
            return .init(data: data, response: try #require(HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: headers)))
        }
        let value: JSONValue
        let location: JSONValue = .object(["directory": .string("/workspace")])
        switch path {
        case "/api/location": value = .object(["directory": .string("/workspace"), "project": .object(["directory": .string("/workspace")])])
        case "/api/vcs": value = .object(["location": location, "data": ["no-git", "creating", "create-failure"].contains(state) ? .object([:]) : .object(["provider": .string("git"), "branch": .object(["current": .string("feature"), "default": .string("main")])])])
        case "/api/fs/find": value = .object(["location": location, "data": .array(["Sources/Example.swift", "Tests/ExampleTests.swift"].map { .object(["path": .string($0), "type": .string("file")]) })])
        case "/api/fs/list": value = .object(["location": location, "data": .array([.object(["path": .string("Sources/"), "type": .string("directory")]), .object(["path": .string("Example.swift"), "type": .string("file")]), .object(["path": .string("README.md"), "type": .string("file")])])])
        default:
            let patch = state == "truncated" ? "--- a\n+++ b\n" : state == "binary" ? "" : ReviewSnapshots.patch
            let binary = ["binary", "image", "image-error", "removed-image"].contains(state)
            var files: JSONValue = .array(state.hasPrefix("empty") ? [] : [.object(["file": .string(["image", "image-error", "removed-image"].contains(state) ? "image.png" : "Example.swift"), "additions": .integer(binary ? 0 : state == "too-large" ? 30000 : 2), "deletions": .integer(binary ? 0 : 2), "status": .string(state == "removed-image" ? "deleted" : "modified"), "patch": .string(patch)])])
            if ["collapsed", "expanded"].contains(state) {
                files = .array(["Example.swift", "src/example.ts", "data.json", "README.md", "image.png", "binary.bin", "removed.txt"].enumerated().map { index, file in
                    .object(["file": .string(file), "patch": .string(index == 4 || index == 5 ? "" : patch), "status": .string(index == 1 ? "added" : index == 6 ? "deleted" : "modified"), "additions": .integer(index == 4 || index == 5 ? 0 : 2), "deletions": .integer(index == 4 || index == 5 ? 0 : 1)])
                })
            }
            value = .object(["location": location, "data": files])
        }
        return .init(data: try JSONEncoder().encode(value), response: try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
    }
    nonisolated func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}
#endif

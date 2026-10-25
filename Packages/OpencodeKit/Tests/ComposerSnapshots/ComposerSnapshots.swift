#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCFoundation
import OCModels
import OCDesign
@testable import OCSync
import OCPersistence
import OCNetworking
import OCSecurity
import OCRender
import FeatureTranscript
@testable import FeatureComposer

@MainActor @Suite(.serialized) struct ComposerSnapshots {
    @Test func adjacentMentionsDeleteIndividually() {
        var first = AttributedString("@file.swift"), second = AttributedString("@file.swift")
        first[MentionAttribute.self] = .init(kind: "file", value: "file.swift")
        second[MentionAttribute.self] = .init(kind: "file", value: "file.swift")
        first.append(second)
        let editor = EditorView(usingTextLayoutManager: true)
        editor.attributedText = PromptEditor.native(first, shell: false, traits: editor.traitCollection)
        editor.selectedRange = NSRange(location: 22, length: 0)
        editor.deleteBackward()
        #expect(editor.text == "@file.swift")
        #expect(PromptEditor.attributed(editor.attributedText).runs.count == 1)
    }
    @Test func dockStates() async throws {
        for state in ["idle", "typing", "context", "commands", "shell", "attachment", "stop", "alternate", "revert", "queue", "outbox", "failed", "editing", "confirmation"] {
            let writer = try PersistenceWriter(), store = ReadStore(serverID: "snapshot", cache: CacheStore(writer: writer), client: { try snapshotAPI() })
            let info = SessionInfo(raw: .object(["id": .string("s"), "agent": .string("build"), "title": .string("Composer"),
                "model": .object(["id": .string("mock-1"), "providerID": .string("mock")]), "location": .object(["directory": .string("/workspace")])]))
            store.seed(info: info, messages: [])
            let catalog = store.catalog(for: .init(directory: "/workspace"))
            catalog.models.seed([model]); catalog.providers.seed([.init(raw: .object(["id": .string("mock"), "name": .string("Fixture Mock")]))]); catalog.defaultModel.seed(model)
            catalog.agents.seed([.init(raw: .object(["id": .string("reviewer"), "name": .string("reviewer"), "mode": .string("primary"), "color": .string("#8476CA")]))])
            catalog.references.seed(.array([.object(["name": .string("docs"), "path": .string("/references/docs"), "description": .string("Project documentation")])]))
            catalog.agents.seed((catalog.agents.value ?? []) + [.init(raw: .object(["id": .string("explore"), "name": .string("explore"), "mode": .string("subagent"), "description": .string("Explore the codebase")]))])
            catalog.skills.seed(.array([.object(["id": .string("review"), "description": .string("Review the implementation")])]))
            catalog.commands.seed(.array([.object(["name": .string("check"), "description": .string("Check the supplied input")])]))
            let composer = store.composer(sessionID: "s", directory: "/workspace")
            await composer.load()
            switch state {
            case "typing":
                var text = AttributedString("Review @main.swift and preserve the existing behavior.")
                if let range = text.range(of: "@main.swift") { text[range][MentionAttribute.self] = .init(kind: "file", value: "main.swift") }
                composer.setText(text)
            case "context": composer.setText(AttributedString("@"))
            case "commands": composer.setText(AttributedString("/"))
            case "shell": composer.shellMode(true); composer.setText(AttributedString("git status"))
            case "attachment":
                composer.setText(AttributedString("Review this document"))
                await composer.addAttachment(Data("%PDF-1.4\nfixture".utf8), mime: "application/pdf", name: "Architecture.pdf")
            case "stop": store.sessions["s"]?.status = .running(since: 0)
            case "alternate": store.sessions["s"]?.status = .running(since: 0); composer.setText(AttributedString("Include a regression test"))
            case "revert": store.sessions["s"]?.info["revert"] = .object(["messageID": .string("old")]); composer.setText(AttributedString("Try a smaller change"))
            case "queue":
                store.sessions["s"]?.pending = (1...5).map { .init(raw: .object(["id": .string("q\($0)"), "type": .string("user"), "delivery": .string("queue"), "payload": .object(["text": .string("Queued follow-up \($0)")])])) }
            case "outbox": _ = try await store.sendPrompt("s", input: .init(text: "Saved until connected"))
            case "failed", "editing", "confirmation":
                let id = try await store.sendPrompt("s", input: .init(text: "Review the saved prompt before sending"))
                store.outboxEntries[id]?.state = state == "confirmation" ? "needsConfirmation" : "failed"
                if state == "editing" { try await store.restoreFailedPrompt(id) }
            default: break
            }
            await capture(VStack(spacing: OCSpacing.xs) {
                if let session = store.sessions["s"] { PendingInputPanel(store: store, session: session) }
                ComposerDock(store: store, model: composer)
            }, name: "dock-" + state)
            if state == "idle" {
                await capture(ModelPicker(model: composer, history: ["mock:mock-1"], select: { _ in }), name: "model-picker", fixedHeight: 700)
                await capture(VStack { AgentOptions(agents: catalog.agents.value ?? [], select: { _ in }) }, name: "agent-picker")
                await capture(VStack { VariantOptions(variants: model.variants, select: { _ in }) }, name: "variant-picker")
                await capture(VStack { SendOptions(alternate: "Queue", sendAlternate: {}, interrupt: {}) }, name: "send-menu")
            }
            await store.stop()
        }
    }
    @Test func newSessionSelectors() async throws {
        let record = ServerRecord(name: "Studio Mac", endpoints: [.init(url: try #require(URL(string: "http://127.0.0.1:1")), kind: .lan)])
        let server = ServerStore(record: record, connection: ServerConnection(endpoints: [], credential: nil), credentials: CredentialStore(secrets: InMemorySecretStore()), cache: CacheStore(writer: try PersistenceWriter()))
        server.readPath.client = { try snapshotAPI() }
        server.readPath.projects = [.init(raw: .object(["id": .string("project"), "canonical": .string("/workspace"), "name": .string("Design system"), "vcs": .string("git")]))]
        let catalog = server.readPath.catalog(for: .init(directory: "/workspace"))
        catalog.models.seed([model]); catalog.defaultModel.seed(model)
        await capture(NewSessionView(server: server, opened: { _ in }), name: "new-session")
        await server.dispose()
    }
    @Test func pendingTimelineStates() async throws {
        for state in ["starting", "steering", "stranded", "queued"] {
            let store = ReadStore(serverID: "snapshot")
            let prompt: JSONValue = .object(["id": .string("pending"), "type": .string("user"), "text": .string("Review @main.swift"),
                "files": .array([.object(["source": .object(["uri": .string("file:///workspace/main.swift")]),
                    "mention": .object(["start": .integer(7), "end": .integer(18), "text": .string("@main.swift")])])]),
                "time": .object(["created": .integer(1)])])
            var messages: [SessionMessage] = [.init(raw: prompt)]
            if state == "stranded" { messages.append(.init(raw: .object(["id": .string("idle"), "type": .string("idle"), "time": .object(["created": .integer(2)])]))) }
            if state == "steering" { messages.insert(.init(raw: .object(["id": .string("sent"), "type": .string("user"), "text": .string("Earlier prompt")])), at: 0) }
            let pending = InboxItem(raw: .object(["id": .string("pending"), "type": .string("user"), "delivery": .string(state == "queued" ? "queue" : "steer"),
                "time": .object(["created": .integer(1)]), "payload": prompt]))
            store.seed(info: .init(raw: .object(["id": .string("s")])), messages: messages, pending: [pending])
            let session = try #require(store.sessions["s"])
            if state == "steering" { session.status = .running(since: 0) }
            if state == "queued" { await capture(PendingInputPanel(store: store, session: session), name: "pending-queued") }
            else if let transcript = session.transcript {
                await capture(TimelineRowView(row: .init(id: "pending", kind: .userPrompt), transcript: transcript, store: store, sessionID: "s"), name: "pending-" + state)
            }
            await store.stop()
        }
    }
    @Test func sentMessageWithMentionsAndAttachments() async throws {
        let store = ReadStore(serverID: "snapshot")
        let png = UIGraphicsImageRenderer(size: CGSize(width: 58, height: 46)).pngData { context in
            UIColor(OCColor.accent).setFill(); context.fill(CGRect(x: 0, y: 0, width: 58, height: 46))
        }
        let prompt: JSONValue = .object(["id": .string("sent"), "type": .string("user"), "text": .string("Review @main.swift with this image."),
            "files": .array([
                .object(["source": .object(["uri": .string("file:///workspace/main.swift")]), "mention": .object(["start": .integer(7), "end": .integer(18), "text": .string("@main.swift")])]),
                .object(["mime": .string("image/png"), "data": .string(png.base64EncodedString()), "name": .string("Reference.png")]),
                .object(["mime": .string("text/plain"), "data": .string("SGVsbG8="), "name": .string("Notes.txt")])])])
        store.seed(info: .init(raw: .object(["id": .string("s")])), messages: [.init(raw: prompt)])
        let transcript = try #require(store.sessions["s"]?.transcript)
        await capture(TimelineRowView(row: .init(id: "sent", kind: .userPrompt), transcript: transcript, store: store, sessionID: "s"), name: "sent-prompt")
        await store.stop()
    }
    @Test func actionConfirmations() async {
        await capture(OCConfirmationSheet("Replace your draft?", message: "Your unsent text and attachments will be replaced by this prompt.",
                                    confirmTitle: "Replace", cancel: {}, confirm: {}), name: "replace-draft", fixedHeight: 900)
        await capture(VStack(alignment: .leading) { SessionMenuOptions(canRedo: true, select: { _ in }) }.buttonStyle(OCButtonStyle(.ghost)), name: "session-menu")
        await capture(OCConfirmationSheet("Delete session", message: "Delete session \"Design system\"? Its subagent sessions will be deleted too.",
                                    confirmTitle: "Delete session", cancel: {}, confirm: {}), name: "delete-confirmation", fixedHeight: 900)
        await capture(OCConfirmationSheet("Discard reverted messages?", message: "The reverted messages and their file changes will be permanently discarded when you send this prompt.",
                                    confirmTitle: "Discard and send", cancel: {}, confirm: {}), name: "revert-confirmation", fixedHeight: 900)
    }
    @Test func longConfirmationScrollsAtAccessibilitySize() async throws {
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let message = "Delete session \"" + String(repeating: "A long session title ", count: 20) + "\"?"
        let content = OCConfirmationSheet("Delete session", message: message, confirmTitle: "Delete session", cancel: {}, confirm: {})
            .environment(\.dynamicTypeSize, .accessibility5)
        let controller = UIHostingController(rootView: ConfirmationSnapshotPresentation(content: content))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { controller.dismiss(animated: false); window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400))
        let sheet = try #require(controller.presentedViewController)
        let scroll = try #require(confirmationScroll(in: sheet.view))
        #expect(sheet.view.bounds.height <= window.bounds.height)
        #expect(scroll.contentSize.height > scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
        #expect(scroll.contentOffset.y > 0)
    }
    private var model: ModelInfo {
        .init(raw: .object(["id": .string("mock-1"), "providerID": .string("mock"), "name": .string("Mock 1"), "enabled": .bool(true),
            "capabilities": .object(["input": .array([.string("text")])]), "variants": .array([.object(["id": .string("careful")])]),
            "cost": .array([.object(["input": .integer(1), "output": .integer(2)])])]))
    }
    private func capture(_ view: some View, name: String, fixedHeight: CGFloat? = nil) async {
        if let filter = ProcessInfo.processInfo.environment["OC_COMPOSER_SNAPSHOT_FILTER"],
           !filter.split(separator: ",").contains(where: { name.hasPrefix($0) }) { return }
        var defaultContentHeights: [String: CGFloat] = [:]
        for dark in [false, true] { for width: CGFloat in [393, 820] { for accessibility in [false, true] {
            let confirmation = ["replace-draft", "delete-confirmation", "revert-confirmation"].contains(name)
            let animationsEnabled = UIView.areAnimationsEnabled
            if confirmation { UIView.setAnimationsEnabled(false) }
            defer { if confirmation { UIView.setAnimationsEnabled(animationsEnabled) } }
            let sheetContent = view.environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.colorScheme, dark ? .dark : .light)
            let wrapped = confirmation ? AnyView(ConfirmationSnapshotPresentation(content: sheetContent)) : AnyView(view.padding(OCSpacing.lg))
            let content = wrapped.environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
            // Use a real viewport so measured scroll content can settle without
            // clipping the toolbar or attachment warning at an initial ideal size.
            let height = confirmation ? (width > 600 ? 1180.0 : 852.0) : fixedHeight ?? (width > 600 ? 1180 : 852)
            let controller = UIHostingController(rootView: content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.background))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            let traits = UITraitCollection { traits in
                traits.userInterfaceStyle = dark ? .dark : .light
                traits.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
                traits.horizontalSizeClass = width > 600 ? .regular : .compact
            }
            var mounted: UIWindow?
            if confirmation || ["sent-prompt", "dock-context", "dock-commands"].contains(name),
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: height)
                if confirmation {
                    window.overrideUserInterfaceStyle = dark ? .dark : .light
                    window.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
                    controller.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
                    controller.traitOverrides.horizontalSizeClass = traits.horizontalSizeClass
                }
                window.rootViewController = controller; window.makeKeyAndVisible()
                controller.view.layoutIfNeeded(); mounted = window
                // Yield the actor so SwiftUI tasks and concurrent thumbnail decoding finish.
                try? await Task.sleep(for: .milliseconds(400))
            }
            defer { mounted?.isHidden = true }
            let label = name + "-" + (dark ? "dark" : "light") + "-\(Int(width))-" + (accessibility ? "accessibility5" : "default")
            if confirmation {
                guard let window = mounted, let sheet = controller.presentedViewController else {
                    Issue.record("Confirmation sheet did not present"); continue
                }
                if !accessibility { #expect(sheet.view.bounds.height < height / 2) }
                if let scroll = confirmationScroll(in: sheet.view) {
                    #expect(scroll.isScrollEnabled)
                    let configuration = "\(dark)-\(width)"
                    if accessibility, let defaultHeight = defaultContentHeights[configuration] {
                        #expect(scroll.contentSize.height > defaultHeight * 1.5)
                    } else { defaultContentHeights[configuration] = scroll.contentSize.height }
                    print("Confirmation \(label): sheet=\(sheet.view.bounds.height), content=\(scroll.contentSize.height), viewport=\(scroll.bounds.height)")
                    if scroll.contentSize.height > scroll.bounds.height {
                        scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                        #expect(scroll.contentOffset.y > 0)
                        scroll.setContentOffset(.zero, animated: false)
                    }
                } else { Issue.record("Confirmation content must remain scrollable") }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                if ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1" {
                    if let result = verifySnapshot(of: image, as: .image, named: label, record: true),
                       !result.contains("Record mode is on") { Issue.record(Comment(rawValue: result)) }
                } else { assertSnapshot(of: image, as: .image, named: label) }
                controller.dismiss(animated: false)
                continue
            }
            // Navigation and list compositing at accessibility sizes needs a
            // real window hierarchy, rather than CALayer.render's black layers.
            // Native glass varies by a single RGB level at one shadow pixel.
        // This admits at most two phone pixels or five tablet pixels.
            let device: ViewImageConfig = width > 600 ? .iPadPro11(.portrait) : .iPhone13Pro
            let strategy: Snapshotting<UIViewController, UIImage> = .wait(for: 0.3, on: name == "model-picker"
                ? .image(on: device, drawHierarchyInKeyWindow: true, precision: 0.999999, size: CGSize(width: width, height: height), traits: traits)
                : .image(size: CGSize(width: width, height: height), traits: traits))
            if ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1" {
                if let result = verifySnapshot(of: controller as UIViewController, as: strategy, named: label, record: true),
                   !result.contains("Record mode is on") { Issue.record(Comment(rawValue: result)) }
            } else { assertSnapshot(of: controller as UIViewController, as: strategy, named: label) }
        } } }
    }
    private func confirmationScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap(confirmationScroll).first
    }
}
private struct ConfirmationSnapshotPresentation<Content: View>: View {
    let content: Content
    @State private var presented = false
    var body: some View {
        OCColor.background.sheet(isPresented: $presented) { content.ocSheet() }
            .task { presented = true }
    }
}
private actor ComposerSnapshotTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let value: JSONValue
        if request.url?.path == "/api/worktree" { value = .array([.object(["directory": .string("/worktrees/review"), "branch": .string("review")])]) }
        else {
            let data: JSONValue = request.url?.path == "/api/fs/find" ? .array([.object(["path": .string("Sources/main.swift"), "type": .string("file")])]) : .array([])
            value = .object(["location": .object(["directory": .string("/workspace")]), "data": data])
        }
        let url = try #require(request.url)
        return .init(data: try JSONEncoder().encode(value), response: try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
    }
    nonisolated func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}
nonisolated private func snapshotAPI() throws -> APIClient {
    APIClient(baseURL: try #require(URL(string: "http://127.0.0.1:1")), transport: ComposerSnapshotTransport())
}
#endif

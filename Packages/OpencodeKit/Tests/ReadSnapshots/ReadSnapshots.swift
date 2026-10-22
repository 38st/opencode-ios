#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCModels
import OCFoundation
import OCSync
import OCDesign
import OCRender
import FeatureTranscript

extension ReadPerformanceTests {
@MainActor @Suite(.serialized) struct Snapshots {
    @Test func rowKinds() async throws {
        for kind in TimelineRow.Kind.allCases {
            let transcript = TranscriptModel(messages: [Self.assistant])
            let row = TimelineRow(id: kind.rawValue, kind: kind, text: Self.text(kind),
                                  reference: [.assistantText, .reasoning, .tool, .shell, .subagent].contains(kind) ? .init(messageID: "a", index: kind == .reasoning ? 1 : kind == .tool ? 2 : kind == .shell ? 3 : kind == .subagent ? 4 : 0) : nil,
                                  children: kind == .toolGroup ? [.init(id: "read", kind: .tool, reference: .init(messageID: "a", index: 2))] : [],
                                  files: kind == .turnEnd ? ["Sources/main.swift", "Tests/mainTests.swift"] : [],
                                  badge: kind == .userPrompt ? "Voice" : nil)
            await capture(TimelineRowView(row: row, transcript: transcript, detail: .everything), name: "row-" + kind.rawValue, height: kind == .toolGroup ? 1_500 : 1_000)
        }
    }
    @Test func everyToolState() async {
        for name in ["read", "glob", "grep", "edit", "patch", "write", "shell", "subagent", "question", "skill", "webfetch", "websearch", "execute", "mcp_lookup", "unknown", "bash", "task", "apply_patch", "todowrite"] {
            for status in ["streaming", "running", "completed", "error"] {
                let presentation = ToolPresenterRegistry().presentation(Self.tool(name, status: status))
                await capture(ToolRowView(presentation: presentation, expanded: true), name: "tool-\(name)-\(status)", height: 1_400)
            }
        }
        for metadata: JSONValue in [.object(["exit": .integer(2)]), .object(["timeout": .bool(true)])] {
            var tool = Self.tool("shell", status: "completed"); tool.raw.set(["state", "metadata"], metadata)
            let presentation = ToolPresenterRegistry().presentation(tool)
            await capture(ToolRowView(presentation: presentation, expanded: true), name: presentation.badge ?? "shell-result", height: 1_000)
        }
        await capture(ToolRowView(presentation: ToolPresenterRegistry().presentation(Self.tool("unknown", status: "future-state")), expanded: true),
                name: "tool-unknown-future-state", height: 1_400)
    }
    @Test func markdownAndDiff() async throws {
        let blocks = try await StreamingMarkdown().update("# Result\n\nA **formatted** answer with [a link](https://example.com).\n\n| File | State |\n| --- | --- |\n| main.swift | Updated |\n\n```swift\nlet greeting = \"Hello\"\n```\n\n![Private image](https://example.com/private.png)", complete: true)
        await capture(VStack(alignment: .leading, spacing: OCSpacing.lg) { ForEach(blocks) { MarkdownBlockView($0) } }, name: "markdown", height: 1_700)
        await capture(DiffCardView(file: "Sources/main.swift", patch: "@@ -1 +1 @@\n-let old = 1\n+let updated = 2", additions: 1, deletions: 1, expanded: true), name: "diff", height: 600)
    }
    func capture(_ view: some View, name: String, height: CGFloat) async {
        if let filter = ProcessInfo.processInfo.environment["OC_SNAPSHOT_FILTER"],
           !filter.split(separator: ",").contains(where: { name.hasPrefix($0) }) { return }
        for dark in [false, true] {
            for width: CGFloat in [393, 820] {
                let content = view.padding(OCSpacing.lg)
                    .environment(\.dynamicTypeSize, .accessibility5).environment(\.colorScheme, dark ? .dark : .light)
                    .transaction { $0.animation = nil }.ocTheme()
                // Tool text is available synchronously; avoid recording empty space below cards.
                // Markdown rows retain their allotted height while their parser starts asynchronously.
                let fitted = name.hasPrefix("tool-") ? min(height, max(120, ceil(UIHostingController(rootView: content)
                    .sizeThatFits(in: CGSize(width: width, height: 10_000)).height))) : height
                let controller = UIHostingController(rootView: content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.background))
                controller.overrideUserInterfaceStyle = dark ? .dark : .light
                // Async diff preparation starts only after the view appears.
                var window: UIWindow?
                if name == "diff" || ["tool-edit-", "tool-patch-", "tool-apply_patch-"].contains(where: { name.hasPrefix($0) }) {
                    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                        Issue.record("Snapshots need a connected window scene"); return
                    }
                    let host = UIWindow(windowScene: scene)
                    host.frame = CGRect(x: 0, y: 0, width: width, height: fitted)
                    controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                    controller.traitOverrides.horizontalSizeClass = width > 600 ? .regular : .compact
                    host.rootViewController = controller; host.makeKeyAndVisible()
                    controller.view.layoutIfNeeded(); window = host
                    await DiffPreparation.settle()
                    try? await Task.sleep(for: .milliseconds(350))
                }
                defer { window?.isHidden = true }
                assertSnapshot(of: controller, as: .wait(for: 0.15, on: .image(size: CGSize(width: width, height: fitted),
                    traits: UITraitCollection { traits in
                        traits.userInterfaceStyle = dark ? .dark : .light
                        traits.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                        traits.horizontalSizeClass = width > 600 ? .regular : .compact
                    })), named: "\(name)-\(dark ? "dark" : "light")-\(Int(width))",
                    record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
            }
        }
    }
    private static var assistant: SessionMessage {
        .init(raw: .object(["id": .string("a"), "type": .string("assistant"), "content": .array([
            .object(["type": .string("text"), "text": .string("The implementation is complete. **Tests pass.**")]),
            .object(["type": .string("reasoning"), "text": .string("Check the parser before changing the interface.")]),
            tool("read", status: "completed").raw, tool("shell", status: "running").raw, tool("subagent", status: "completed").raw
        ])]))
    }
    private static func text(_ kind: TimelineRow.Kind) -> String {
        switch kind {
        case .userPrompt: "Voice delegation. Review the session screen and make sure it works with large text."
        case .error: "The provider could not complete this request. Please try again."
        case .retry: "The service is busy. Retrying shortly."
        case .notice: "Agent switched to Build"
        case .pendingInput: "Allow editing Sources/main.swift?"
        case .compaction: "Compacting the conversation to make room for the next turn."
        case .turnEnd: "Changed 2 files"
        case .toolGroup: "Used 3 Read, Glob, Grep"
        default: "Result"
        }
    }
    static func tool(_ name: String, status: String) -> ContentFields {
        let input: JSONValue
        switch name {
        case "read", "edit", "patch", "apply_patch": input = .object(["path": .string("main.swift")])
        case "glob", "grep": input = .object(["pattern": .string("*.swift")])
        case "write": input = .object(["path": .string("main.swift"), "content": .string("let value = 1")])
        case "shell", "bash": input = .object(["command": .string("swift test")])
        case "task", "subagent": input = .object(["agent": .string("explore"), "description": .string("Check the implementation")])
        case "question": input = .object(["questions": .array([.object(["question": .string("Which color?")])])])
        case "webfetch": input = .object(["url": .string("https://example.com/docs")])
        case "websearch": input = .object(["query": .string("Swift concurrency")])
        case "execute": input = .object(["code": .string("await read('main.swift')")])
        default: input = .object(["name": .string("review")])
        }
        let meta: JSONValue = .object(["files": .array([.object(["file": .string("main.swift"), "patch": .string("@@ -1 +1 @@\n-let a = 1\n+let a = 2"), "additions": .integer(1), "deletions": .integer(1)])]),
            "answers": .array([.array([.string("Blue")])]), "sessionID": .string("child"),
            "toolCalls": .array([.object(["name": .string("read"), "status": .string(status), "output": .string("let value = 1")])])])
        return .init(raw: .object(["type": .string("tool"), "id": .string(name), "name": .string(name), "state": .object([
            "status": .string(status), "input": input, "metadata": meta,
            "error": status == "error" ? .object(["message": .string("The tool could not complete this action.")]) : .null,
            "content": .array([.object(["type": .string("text"), "text": .string(name == "websearch" ? "Documentation https://example.com/docs" : "Completed successfully.")])])
        ])]))
    }
}
}
#endif

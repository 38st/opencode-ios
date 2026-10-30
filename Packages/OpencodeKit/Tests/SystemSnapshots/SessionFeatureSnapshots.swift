#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCDesign
import OCFoundation
import OCModels
import OCNetworking
import OCRender
import OCSecurity
@testable import OCSync
@testable import FeatureComposer
@testable import FeatureSettings

/// Answers the session feature routes with fixed data.
private final class FeatureTransport: HTTPTransport, Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let path = request.url?.path ?? ""
        let body: String
        switch path {
        case "/api/worktree":
            body = #"[{"directory":"/Users/Shared/app"},{"directory":"/Users/Shared/worktrees/app/calm-river","strategy":"git","branch":"opencode/calm-river"}]"#
        case "/api/experimental/session/stats":
            body = #"""
            {"data":{"range":{"from":1,"to":2},"sessions":12,"subagents":3,"prompts":41,"steps":187,
             "tokens":{"input":1250000,"output":86000,"reasoning":12000,"cache":{"read":900000,"write":42000}},"cost":4.37,
             "tools":{"mode":"detail","totals":{"calls":240,"succeeded":231,"failed":7,"unfinished":2},
              "usage":[{"name":"read","calls":96,"failed":0},{"name":"shell","calls":71,"failed":5},{"name":"edit","calls":52,"failed":2}]},
             "activeDays":5,"streak":3,"activity":[{"date":"2026-10-27","steps":40},{"date":"2026-10-28","steps":92}],
             "models":[{"model":{"id":"large-model","providerID":"provider-a"},"steps":150,"tokens":{"input":1000000},"cost":3.9},
                       {"model":{"id":"gpt-mini","providerID":"openai"},"steps":37,"tokens":{"input":250000},"cost":0.47}]}}
            """#
        default: body = #"{"_tag":"NotFound"}"#
        }
        let status = body.hasPrefix(#"{"_tag""#) ? 404 : 200
        let url = try #require(request.url)
        return .init(data: Data(body.utf8), response: try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                                                    headerFields: ["Content-Type": "application/json"])))
    }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

@MainActor private final class StillRecognizer: SpeechRecognizing {
    var continuation: AsyncThrowingStream<VoiceTranscript, any Error>.Continuation?
    func authorize() async -> VoiceAuthorization { .granted }
    func start(contextualStrings: [String]) async throws -> AsyncThrowingStream<VoiceTranscript, any Error> {
        let (stream, continuation) = AsyncThrowingStream<VoiceTranscript, any Error>.makeStream()
        self.continuation = continuation; return stream
    }
    func stop() async { continuation?.finish() }
}
@MainActor private final class SilentSpeaker: SpeechSpeaking {
    func speak(_ text: String) async {}
    func stopSpeaking() {}
}

/// New session-feature screens: light and dark at iPhone width, and the largest text size.
@MainActor @Suite(.serialized) struct SessionFeatureSnapshots {
    @Test func moveAndExport() async throws {
        let (server, session) = try fixture()
        await capture(MoveSessionSheet(store: server.readPath, session: session) {}, name: "move-session") { true }
        server.readPath.requestedMoves[session.id] = .pending(directory: "/Users/Shared/worktrees/app/calm-river", delivery: .queue)
        await capture(PendingMoveBanner(store: server.readPath, sessionID: session.id).padding(), name: "move-pending", height: 200)
        server.readPath.requestedMoves[session.id] = .failed(directory: "/x", message: "Not a directory: /x")
        await capture(PendingMoveBanner(store: server.readPath, sessionID: session.id).padding(), name: "move-failed", height: 200)
        let file = FileManager.default.temporaryDirectory.appending(path: "fix-the-parser.md")
        await capture(OCExportSheet(prepare: { _, _ in file }) {}, name: "export-session")
    }
    @Test func sideQuestionAndHistory() async throws {
        let (server, session) = try fixture()
        server.readPath.sideQuestions[session.id] = SideQuestion(question: "What does the parser do with tabs?", state: .answered("It expands them to **four spaces** before tokenizing, in `Lexer.normalize`."))
        await capture(SideQuestionCard(store: server.readPath, sessionID: session.id).padding(), name: "side-question", height: 400)
        server.readPath.sideQuestions[session.id] = SideQuestion(question: "Why?", state: .failed("The server could not be reached."))
        await capture(SideQuestionCard(store: server.readPath, sessionID: session.id).padding(), name: "side-question-failed", height: 300)
        let entries = [PromptHistory.Entry(text: "Fix the failing parser test and explain the cause", sessionID: session.id, created: 1_800_000_000_000),
                       PromptHistory.Entry(text: "Add a regression test for tabs", sessionID: "ses_other", created: 1_799_990_000_000)]
        await capture(PromptHistorySheet(entries: entries, current: session.id, choose: { _ in }, cancel: {}), name: "prompt-history")
    }
    @Test func statistics() async throws {
        let (server, _) = try fixture()
        await capture(NavigationStack { UsageStatisticsSection(server: server) }, name: "usage-statistics", height: 1600)
    }
    @Test func diagramsAndMath() async {
        let view = VStack(alignment: .leading, spacing: OCSpacing.lg) {
            MermaidView("flowchart TD\n  A[Prompt] --> B{Approved?}\n  B -->|yes| C(Run the tool)\n  B -->|no| D[Ask again]\n  D -.-> A")
            MermaidView("sequenceDiagram\n  participant P as Phone\n  participant S as Server\n  P->>S: prompt\n  S-->>P: events\n  Note over P,S: one turn")
            MathBlockView("\\sum_{i=1}^{n} \\frac{x_i^2}{\\sigma} = \\sqrt{\\alpha + \\beta}")
            MathBlockView("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}")
            MermaidView("gantt\n  title Release")
            StreamingMarkdownView("Inline $E = mc^2$ and $a_1 + b_1$, but $5 and $10 stay prices.")
        }.padding()
        await capture(ScrollView { view }, name: "diagrams", height: 1400)
    }
    @Test func voiceAndImages() async throws {
        let recognizer = StillRecognizer()
        let voice = VoiceModel(recognizer: recognizer, speaker: SilentSpeaker())
        voice.start(.handsFree)
        for _ in 0..<200 where voice.state != .listening { await Task.yield() }
        recognizer.continuation?.yield(.init(text: "Run the parser tests", isFinal: true))
        recognizer.continuation?.yield(.init(text: "and show failures", isFinal: false))
        for _ in 0..<200 where voice.volatile.isEmpty { await Task.yield() }
        await capture(VoicePanel(voice: voice) { _ in }, name: "voice-listening", height: 300)
        voice.stop()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            UIColor.white.setFill(); context.fill(CGRect(x: 40, y: 40, width: 120, height: 80))
        }
        let encoded = try #require(image.pngData()).base64EncodedString()
        let transcriptImage = try #require(TranscriptImage(name: "screenshot.png", mime: "image/png", base64: encoded))
        await capture(VStack(alignment: .leading) { OCTranscriptImage(transcriptImage) }.padding(), name: "transcript-image", height: 320)
    }

    private func fixture() throws -> (ServerStore, SessionModel) {
        let endpoint = EndpointRecord(url: try #require(URL(string: "https://studio.example.com")), kind: .https)
        let server = ServerStore(record: .init(name: "Studio Mac", endpoints: [endpoint], lastInfo: .init(version: "2.2.2", capabilities: .init(persistentPty: true))),
                                 connection: SnapshotConnection(), credentials: CredentialStore(secrets: InMemorySecretStore()))
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:4096")!, transport: FeatureTransport())
        server.readPath.client = { api }
        server.readPath.projects = [Project(raw: .object(["id": .string("prj"), "canonical": .string("/Users/Shared/app"), "name": .string("app"),
            "time": .object(["created": .integer(0), "updated": .integer(0)])])),
                                    Project(raw: .object(["id": .string("docs"), "canonical": .string("/Users/Shared/docs"), "time": .object(["created": .integer(0), "updated": .integer(0)])]))]
        server.readPath.seed(info: SessionInfo(raw: .object(["id": .string("ses_1"), "projectID": .string("prj"), "title": .string("Fix the parser"),
            "location": .object(["directory": .string("/Users/Shared/app")]), "time": .object(["created": .integer(1), "updated": .integer(1)])])))
        server.readPath.sessions["ses_1"]?.status = .running(since: 1)
        return (server, try #require(server.readPath.sessions["ses_1"]))
    }

    private func capture<V: View>(_ view: V, name: String, height: Double = 852, until ready: @escaping () -> Bool = { true }) async {
        for (dark, accessibility) in [(false, false), (true, false), (false, true)] {
            let size = CGSize(width: 393, height: height)
            let controller = UIHostingController(rootView: view
                .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.backgroundDeep))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            controller.traitOverrides.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
            controller.traitOverrides.horizontalSizeClass = .compact
            controller.view.frame = CGRect(origin: .zero, size: size)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                Issue.record("Snapshots need a connected window scene"); return
            }
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.frame = CGRect(origin: .zero, size: size); window.rootViewController = controller; window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            for _ in 0..<200 where !ready() { try? await Task.sleep(for: .milliseconds(20)) }
            try? await Task.sleep(for: .milliseconds(900))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let label = "\(name)-\(dark ? "dark" : "light")-393-\(accessibility ? "accessibility5" : "default")"
            let record = ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1"
            // Sheets carry the system's glass toolbar buttons and spinners, which render a little differently each time.
            // The pending banner's spinner moves between frames.
            let precision: Float = name == "move-pending" ? 0.98
                : ["move-session", "export-session", "prompt-history", "usage-statistics"].contains(name) ? 0.995 : 1
            if let result = verifySnapshot(of: image, as: .image(precision: precision, perceptualPrecision: 0.98), named: label, record: record, testName: "session"),
               !(record && result.contains("Record mode is on")) { Issue.record(Comment(rawValue: result)) }
            window.isHidden = true
        }
    }
}
#endif

import CoreSpotlight
import Foundation
import Testing
import OCShared
@testable import OCIntents
@testable import OCAppIntents

private let studio = "00000000-0000-0000-0000-0000000000A1", laptop = "00000000-0000-0000-0000-0000000000A2"
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func session(_ id: String, _ title: String, server: String = studio, status: SystemSnapshot.Status = .idle, minutes: Double,
                     request: SystemSnapshot.Request? = nil) -> SystemSnapshot.Session {
    .init(server: server, session: id, title: title, project: "opencode-ios", projectID: "prj_ios", status: status,
          activity: base.addingTimeInterval(minutes * 60), requests: request == nil ? 0 : 1, request: request)
}
private let snapshot = SystemSnapshot(writtenAt: base, servers: [.init(id: studio, name: "Studio Mac", reachability: .online), .init(id: laptop, name: "Laptop", reachability: .paused)],
    sessions: [session("ses_old", "Old idea", minutes: -90), session("ses_run", "Port the widths", status: .running, minutes: -30),
               session("ses_ask", "Fix the pairing flow", server: laptop, status: .needsYou, minutes: -60, request: .init(id: "per_1", kind: .permission)),
               session("ses_new", "Write release notes", minutes: -5)],
    projects: [.init(server: studio, project: "prj_ios", name: "opencode-ios", activity: base), .init(server: laptop, project: "prj_docs", name: "docs", activity: base.addingTimeInterval(-600))],
    lastProject: .init(server: studio, project: "prj_ios", name: "opencode-ios"))

@MainActor private final class FakeApp: IntentApp {
    var sent: [PromptRequest] = []
    var opened: [URL] = []
    /// Every call, in order: `IntentApp` has no way to answer a request, so a review can only look and open.
    var calls: [String] = []
    var approval: URL?
    var compose: URL?
    var report = SessionStatusReport(state: .running, title: "Port the widths")
    var lists = IntentDirectory()
    func send(_ request: PromptRequest) async throws -> PromptReceipt {
        calls.append("send"); sent.append(request)
        return .init(session: session("ses_run", "Port the widths", status: .running, minutes: 0), serverName: "Studio Mac", delivered: false)
    }
    func status(server: String, session: String) async throws -> SessionStatusReport { calls.append("status"); return report }
    func open(_ url: URL) { calls.append("open"); opened.append(url) }
    func nextApproval() async -> URL? { calls.append("nextApproval"); return approval }
    func newPrompt() async -> URL? { calls.append("newPrompt"); return compose }
    func directory() async -> IntentDirectory { lists }
}

/// The queries read the snapshot outside the app process; each test installs its own.
@MainActor private func useSnapshot(_ value: SystemSnapshot?) {
    IntentEnvironment.app = nil
    IntentEnvironment.snapshot = { value.map(SystemSnapshotStore.Read.snapshot) ?? .missing }
}

@Suite(.serialized) @MainActor struct IntentTests {
    @Test func sessionQueriesReadTheSnapshotInHomeOrder() async throws {
        useSnapshot(snapshot)
        let suggested = try await SessionQuery().suggestedEntities()
        #expect(suggested.map(\.session) == ["ses_ask", "ses_run", "ses_new", "ses_old"], "Needs you, running, then by last activity")
        #expect(suggested.first?.detail == "opencode-ios · Laptop")
        let found = try await SessionQuery().entities(for: [studio + ":ses_new", "nope", laptop + ":ses_ask"])
        #expect(found.map(\.title) == ["Write release notes", "Fix the pairing flow"], "Unknown identifiers resolve to nothing")
        #expect(try await SessionQuery().entities(matching: "PAIRING").map(\.session) == ["ses_ask"])
        #expect(try await SessionQuery().entities(matching: "opencode").count == 4, "The project name matches too")
        // Spotlight switched off: no title is suggested to Siri or Shortcuts, but a session can still be found and chosen.
        var off = snapshot; off.suggestsSessions = false
        useSnapshot(off)
        #expect(try await SessionQuery().suggestedEntities().isEmpty)
        #expect(try await SessionQuery().entities(matching: "PAIRING").map(\.session) == ["ses_ask"])
        let app = FakeApp()
        app.lists = IntentDirectory(sessions: [session("ses_run", "Port the widths", minutes: 0)], suggestsSessions: false)
        IntentEnvironment.app = app
        #expect(try await SessionQuery().suggestedEntities().isEmpty, "The same in the app process")
        useSnapshot(nil)
        #expect(try await SessionQuery().suggestedEntities().isEmpty, "No snapshot, no sessions")
    }
    @Test func projectAndServerQueries() async throws {
        useSnapshot(snapshot)
        #expect(try await ProjectQuery().suggestedEntities().map(\.name) == ["opencode-ios", "docs"])
        #expect(try await ProjectQuery().entities(for: [laptop + ":prj_docs"]).first?.serverName == "Laptop")
        #expect(try await ProjectQuery().entities(matching: "studio").map(\.name) == ["opencode-ios"], "A server's name finds its projects")
        let servers = try await ServerQuery().suggestedEntities()
        #expect(servers.map(\.name) == ["All servers", "Studio Mac", "Laptop"], "All servers first, for the widgets")
        #expect(await ServerQuery().defaultResult() == .all)
        #expect(try await ServerQuery().entities(for: ["all", laptop]).map(\.serverID) == [nil, laptop])
        #expect(SessionsWidgetIntent(server: .all).serverID == nil && SessionsWidgetIntent(server: nil).serverID == nil)
        #expect(SessionsWidgetIntent(server: ServerEntity(id: studio, name: "Studio Mac")).serverID == studio)
    }
    @Test func theAppProcessAnswersQueriesFromItsOwnLists() async throws {
        useSnapshot(snapshot)
        let app = FakeApp()
        app.lists = IntentDirectory(servers: [.init(id: studio, name: "Studio Mac", reachability: .online)],
                                    sessions: [session("ses_archive", "Older than the snapshot", minutes: -9000)])
        IntentEnvironment.app = app
        #expect(try await SessionQuery().entities(for: [studio + ":ses_archive"]).map(\.title) == ["Older than the snapshot"],
                "A Spotlight result older than the snapshot's rows still opens")
        IntentEnvironment.app = nil
    }
    @Test func sendGoesToTheAppAndNeverRunsInTheExtension() async throws {
        await #expect(throws: IntentError.self) { try await SendPromptIntent.send(.init(destination: .session(server: studio, session: "ses_run"), text: "Hi"), app: nil) }
        let app = FakeApp()
        let receipt = try await SendPromptIntent.send(.init(destination: .newSession(server: studio, project: "prj_ios"), text: "Start"), app: app)
        #expect(app.sent == [.init(destination: .newSession(server: studio, project: "prj_ios"), text: "Start")])
        #expect(SendPromptIntent.message(receipt) == "Saved on this device. It sends to “Port the widths” when Studio Mac can be reached.")
        var delivered = receipt; delivered.delivered = true
        #expect(SendPromptIntent.message(delivered) == "Sent to “Port the widths”.")
    }
    @Test func sendPerformValidatesItsParameters() async throws {
        let app = FakeApp()
        IntentEnvironment.app = app
        defer { IntentEnvironment.app = nil }
        let intent = SendPromptIntent()
        intent.destination = .session
        intent.session = SessionEntity(session("ses_run", "Port the widths", status: .running, minutes: 0), serverName: "Studio Mac")
        intent.prompt = "  Continue with the tests  "
        _ = try await intent.perform()
        #expect(app.sent == [.init(destination: .session(server: studio, session: "ses_run"), text: "Continue with the tests")])
        intent.prompt = "   "
        await #expect(throws: (any Error).self) { _ = try await intent.perform() }
        intent.prompt = "Go"; intent.destination = .newSession; intent.project = nil
        await #expect(throws: (any Error).self) { _ = try await intent.perform() }
        #expect(app.sent.count == 1, "Nothing is sent without a prompt and a destination")
    }
    @Test func statusMapsToHomeWordsAndAShortSummary() async throws {
        let app = FakeApp()
        app.report = SessionStatusReport(state: .running, title: "Port the widths", lastActivity: base.addingTimeInterval(-60), runningSince: base.addingTimeInterval(-240))
        let report = try await GetSessionStatusIntent.status(SessionEntity(session("ses_run", "Port the widths", minutes: 0), serverName: "Studio Mac"), app: app)
        #expect(report.label == "Running")
        #expect(report.summary(now: base, locale: Locale(identifier: "en_US")) == "Port the widths: Running. Started 4 minutes ago. Last activity 1 minute ago.")
        let fresh = SessionStatusReport(state: .finished, title: "Ship it", lastActivity: base.addingTimeInterval(2))
        #expect(fresh.summary(now: base, locale: Locale(identifier: "en_US")) == "Ship it: Finished. Last activity just now.")
        let stale = SessionStatusReport(state: .needsPermission, title: "Fix", unread: true, live: false)
        #expect(stale.summary(now: base, locale: Locale(identifier: "en_US")) == "Fix: Waiting for your approval. New output to read. This is the last known state: the server could not be reached.")
        await #expect(throws: IntentError.self) { _ = try await GetSessionStatusIntent.status(SessionEntity(session("ses_run", "x", minutes: 0), serverName: ""), app: nil) }
    }
    @Test func openAndReviewOpenLinksAndReviewNeverReplies() async throws {
        let app = FakeApp()
        let entity = SessionEntity(session("ses_ask", "Fix the pairing flow", server: laptop, minutes: 0), serverName: "Laptop")
        try OpenSessionIntent.open(entity, app: app)
        #expect(app.opened == [try #require(URL(string: "opencodeios://server/\(laptop)/session/ses_ask"))])
        app.calls = []
        app.approval = URL(string: "opencodeios://server/\(laptop)/session/ses_ask/request/per_1")
        #expect(try await ReviewNextApprovalIntent.review(app: app))
        #expect(app.opened.last == app.approval, "The request opens in the app")
        app.approval = nil
        #expect(try await ReviewNextApprovalIntent.review(app: app) == false, "Nothing waits: nothing opens")
        #expect(app.calls == ["nextApproval", "open", "nextApproval"], "Review only looks and opens; it has no way to answer")
        #expect(throws: IntentError.self) { try OpenSessionIntent.open(entity, app: nil) }
    }
    @Test func theControlsIntentsOpenTheComposerAndTheNextRequest() async throws {
        let app = FakeApp()
        app.compose = DeepLink.compose(serverID: try #require(UUID(uuidString: studio)), projectID: "prj_ios")
        try await NewPromptIntent.compose(app: app)
        #expect(app.opened == [try #require(URL(string: "opencodeios://server/\(studio)/project/prj_ios/new"))])
        app.compose = nil
        try await NewPromptIntent.compose(app: app)
        #expect(app.opened.count == 1, "Without a server there is nothing to open")
        await #expect(throws: IntentError.self) { try await NewPromptIntent.compose(app: nil) }
        await #expect(throws: IntentError.self) { _ = try await ReviewNextApprovalIntent.review(app: nil) }
    }
    @Test func spotlightGetsTitlesProjectsAndServersOnly() {
        let entity = SessionEntity(session("ses_run", "Port the widths", minutes: 0), serverName: "Studio Mac")
        let attributes = entity.attributeSet
        #expect(attributes.title == "Port the widths" && attributes.contentDescription == "opencode-ios · Studio Mac")
        #expect(attributes.keywords == ["opencode-ios", "Studio Mac"])
        #expect(attributes.textContent == nil && attributes.htmlContentData == nil, "Never conversation text")
    }
}

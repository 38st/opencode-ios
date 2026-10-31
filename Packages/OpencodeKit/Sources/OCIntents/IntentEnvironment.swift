import Foundation
import OCShared

/// A prompt for the app to send: to an existing session, or as the first prompt of a new session in a project.
public struct PromptRequest: Sendable, Equatable {
    public enum Destination: Sendable, Equatable {
        case session(server: String, session: String)
        case newSession(server: String, project: String)
    }
    public var destination: Destination
    public var text: String
    public init(destination: Destination, text: String) { self.destination = destination; self.text = text }
}

/// What the app did with a prompt. It is on this device's outbox either way; `delivered` says the server took it.
public struct PromptReceipt: Sendable, Equatable {
    public var session: SystemSnapshot.Session
    public var serverName: String
    public var delivered: Bool
    public init(session: SystemSnapshot.Session, serverName: String, delivered: Bool) {
        self.session = session; self.serverName = serverName; self.delivered = delivered
    }
}

/// A session's state for Shortcuts, in Home's terms.
public struct SessionStatusReport: Sendable, Equatable {
    public enum State: String, Sendable { case needsPermission, needsAnswer, running, retrying, failed, stopped, finished, idle }
    public var state: State
    public var title: String
    public var unread: Bool
    public var lastActivity: Date?
    public var runningSince: Date?
    /// False when the server could not be reached and this is the state the app last saw.
    public var live: Bool
    public init(state: State, title: String, unread: Bool = false, lastActivity: Date? = nil, runningSince: Date? = nil, live: Bool = true) {
        self.state = state; self.title = title; self.unread = unread; self.lastActivity = lastActivity; self.runningSince = runningSince; self.live = live
    }
    public var label: String {
        switch state {
        case .needsPermission: localized("Waiting for your approval")
        case .needsAnswer: localized("Waiting for your answer")
        case .running: localized("Running", comment: "Session status")
        case .retrying: localized("Retrying", comment: "Session status")
        case .failed: localized("Failed", comment: "Session status")
        case .stopped: localized("Stopped", comment: "Session status")
        case .finished: localized("Finished", comment: "Session status")
        case .idle: localized("Idle", comment: "Session status")
        }
    }
    /// The status and a short account of the last activity.
    public func summary(now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale; formatter.unitsStyle = .full
        // The server's clock can be a little ahead of the device's: within a minute, or later, is "just now".
        let relative = { (date: Date) in date.timeIntervalSince(now) > -60 ? localized("just now", comment: "Relative time: less than a minute ago") : formatter.localizedString(for: date, relativeTo: now) }
        var parts = [localized("\(title): \(label).", comment: "First %@ is a session title, second its status")]
        if let runningSince, [.running, .retrying].contains(state) { parts.append(localized("Started \(relative(runningSince)).", comment: "%@ is a relative time, like 5 minutes ago")) }
        if let lastActivity { parts.append(localized("Last activity \(relative(lastActivity)).", comment: "%@ is a relative time, like 5 minutes ago")) }
        if unread { parts.append(localized("New output to read.")) }
        if !live { parts.append(localized("This is the last known state: the server could not be reached.")) }
        return parts.joined(separator: " ")
    }
}

/// What the intents read and do in the app process. The app sets `IntentEnvironment.app` at launch; in the Widgets
/// extension it stays nil, so an intent there reads the snapshot and never reaches a server.
@MainActor public protocol IntentApp: AnyObject {
    /// Admits the prompt to the outbox and tries to deliver it; once admitted it never throws.
    func send(_ request: PromptRequest) async throws -> PromptReceipt
    func status(server: String, session: String) async throws -> SessionStatusReport
    /// Opens a link in the app's windows.
    func open(_ url: URL)
    /// The next waiting permission or question, in Home's order. It never answers one.
    func nextApproval() async -> URL?
    /// The new-session composer in the last used project.
    func newPrompt() async -> URL?
    /// Every server, project and session the app knows, for the entity queries; a cold start loads them first.
    func directory() async -> IntentDirectory
}

/// The servers, projects and sessions the entity queries choose from.
public struct IntentDirectory: Sendable, Equatable {
    public var servers: [SystemSnapshot.Server]
    public var projects: [SystemSnapshot.Project]
    public var sessions: [SystemSnapshot.Session]
    /// The Spotlight switch: when off, no session title is offered to Siri's and Shortcuts' suggestions.
    public var suggestsSessions: Bool
    public init(servers: [SystemSnapshot.Server] = [], projects: [SystemSnapshot.Project] = [], sessions: [SystemSnapshot.Session] = [],
                suggestsSessions: Bool = true) {
        self.servers = servers; self.projects = projects; self.sessions = sessions; self.suggestsSessions = suggestsSessions
    }
    public init(_ snapshot: SystemSnapshot?) {
        self.init(servers: snapshot?.servers ?? [], projects: snapshot?.projects ?? [], sessions: snapshot?.sessions ?? [],
                  suggestsSessions: snapshot?.suggestsSessions ?? true)
    }
    public func server(_ id: String) -> SystemSnapshot.Server? { servers.first { $0.id == id } }
}

public enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The intent ran outside the app process, where nothing can reach a server.
    case appUnavailable
    case sessionNotFound
    case projectNotFound
    case emptyPrompt
    case subagentSession
    case revertStaged
    case serverUnavailable
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appUnavailable: LocalizedStringResource("Open the app, then try again.", bundle: .module)
        case .sessionNotFound: LocalizedStringResource("That session is no longer on your servers.", bundle: .module)
        case .projectNotFound: LocalizedStringResource("That project is no longer on your servers.", bundle: .module)
        case .emptyPrompt: LocalizedStringResource("The prompt is empty.", bundle: .module)
        case .subagentSession: LocalizedStringResource("A subagent session is read only. Send to its parent session instead.", bundle: .module)
        case .revertStaged: LocalizedStringResource("This session has an undo waiting to be confirmed. Open it in the app first.", bundle: .module)
        case .serverUnavailable: LocalizedStringResource("The server is not saved in the app.", bundle: .module)
        }
    }
}

@MainActor public enum IntentEnvironment {
    public static var app: (any IntentApp)?
    /// The snapshot the queries read outside the app process.
    public static var snapshot: @Sendable () -> SystemSnapshotStore.Read = {
        (try? SystemSnapshotStore.appGroup())?.read() ?? .missing
    }
    /// The app's own lists in the app process, else the snapshot's.
    public static func directory() async -> IntentDirectory {
        if let app { return await app.directory() }
        return IntentDirectory(snapshot().snapshot)
    }
}

/// Which process ran an intent, and what it answered: evidence for the UI tests that the work happened in the app.
package enum IntentTrace {
    package static func record(_ intent: String) {
        #if DEBUG
        let process = Bundle.main.bundleURL.pathExtension == "appex" ? "extension" : "app"
        try? SystemSnapshotStore.appGroup().recordIntent(intent + " process=" + process)
        #endif
    }
    package static func result(_ intent: String, _ text: String) {
        #if DEBUG
        try? SystemSnapshotStore.appGroup().recordIntent(intent + " result=" + text)
        #endif
    }
}

// Sources: packages/app/src/session/session-panel-width.ts, shell/state/layout.tsx and shell/shell.tsx (widths).
import Foundation

/// Panel widths in points. The chat panel and the review pane share the space beside Home: the review pane keeps
/// a minimum and the chat panel takes the rest, up to its saved width.
public enum WorkspaceWidths {
    public static let chatMinimum = 450.0
    public static let chatDefault = 600.0
    public static let reviewMinimum = 480.0
    public static let reviewMinimumSplit = 800.0
    /// The desktop's vertical tabs go to 520; below 220 Home's rows stop being legible.
    public static let homeMinimum = 220.0
    public static let homeDefault = 256.0
    public static let homeMaximum = 520.0
    public static let reviewTreeMinimum = 200.0
    public static let reviewTreeDefault = 240.0
    public static let reviewTreeMaximum = 480.0
    public static func chatMaximum(available: Double, split: Bool) -> Double {
        max(chatMinimum, available - (split ? reviewMinimumSplit : reviewMinimum))
    }
    /// Before the layout is measured the stored width is used as it is, avoiding a first-frame snap.
    public static func clampChat(_ width: Double, available: Double?, split: Bool) -> Double {
        guard let available else { return width }
        return min(width, chatMaximum(available: available, split: split))
    }
    public static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

/// One window's workspace, saved in its scene storage so each window restores on its own.
public struct WindowState: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version = WindowState.currentVersion
    /// The storage namespace that wrote it; state from another namespace is never restored.
    public var owner: String
    public var path: [SessionRef] = []
    public var server: ServerID?
    public var project: String?
    public var homeOpen = true
    public var reviewOpen = false
    public var reviewTab: String?
    public var chatWidth = WorkspaceWidths.chatDefault
    public var homeWidth = WorkspaceWidths.homeDefault
    public var reviewTreeWidth = WorkspaceWidths.reviewTreeDefault
    public init(owner: String) { self.owner = owner }
    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    /// Saved state that still applies: another version or namespace, or unreadable data, restores nothing; sessions
    /// and filters of servers that are no longer saved are dropped; widths are brought back into range.
    public static func restore(_ data: Data?, owner: String, servers: Set<ServerID>) -> WindowState? {
        guard let data, var state = try? JSONDecoder().decode(WindowState.self, from: data),
              state.version == currentVersion, state.owner == owner else { return nil }
        if state.path.contains(where: { !servers.contains($0.serverID) }) { state.path = [] }
        state.path = state.path.map { SessionRef(serverID: $0.serverID, sessionID: $0.sessionID) }
        if let server = state.server, !servers.contains(server) { state.server = nil; state.project = nil }
        if let project = state.project, !servers.contains(where: { project.hasPrefix($0.rawValue.uuidString + ":") }) { state.project = nil }
        if let tab = state.reviewTab, !["Changes", "Files", "Terminal", "Context"].contains(tab) { state.reviewTab = nil }
        state.chatWidth = WorkspaceWidths.clamp(state.chatWidth, WorkspaceWidths.chatMinimum...10_000)
        state.homeWidth = WorkspaceWidths.clamp(state.homeWidth, WorkspaceWidths.homeMinimum...WorkspaceWidths.homeMaximum)
        state.reviewTreeWidth = WorkspaceWidths.clamp(state.reviewTreeWidth, WorkspaceWidths.reviewTreeMinimum...WorkspaceWidths.reviewTreeMaximum)
        return state
    }
}

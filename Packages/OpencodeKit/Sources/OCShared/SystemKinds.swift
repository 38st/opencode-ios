import Foundation

/// The widget kinds the Widgets extension declares and the app reloads. Every widget a person adds keeps its kind, so
/// these never change.
public enum WidgetKind: String, CaseIterable, Sendable { case needsYou = "needs-you", running, recent }
public enum ControlKind: String, CaseIterable, Sendable { case newPrompt = "new-prompt", reviewApproval = "review-approval" }
/// A timeline or control to reload after the snapshot changed.
public enum SystemReload: Hashable, Sendable { case widget(WidgetKind), control(ControlKind) }

/// The integration's defaults, in one place so they are easy to change.
public enum SystemDefaults {
    /// Session titles, project and server names go to Spotlight unless the user turns it off in Settings.
    public static let spotlightEnabled = true
    /// The rows of a server that is not online turn stale this long after its last sync.
    public static let staleAfter: TimeInterval = 15 * 60
    /// Any snapshot this old is stale, even one written while online: the app stopped without saying so.
    public static let abandonedAfter: TimeInterval = 60 * 60
    public static let needsYouLimit = 20
    public static let runningLimit = 20
    public static let recentLimit = 20
    public static let projectLimit = 50
}

public extension SystemSnapshot {
    /// The widgets and controls whose content differs between two snapshots; all of them for the first one, or when
    /// the servers changed (a server removed or renamed, or its reachability).
    static func reloads(from old: SystemSnapshot?, to new: SystemSnapshot) -> Set<SystemReload> {
        let all = Set(WidgetKind.allCases.map(SystemReload.widget) + ControlKind.allCases.map(SystemReload.control))
        guard let old, old.servers == new.servers else { return all }
        var reloads: Set<SystemReload> = []
        if old.needsYou() != new.needsYou() { reloads.formUnion([.widget(.needsYou), .control(.reviewApproval)]) }
        if old.running() != new.running() { reloads.insert(.widget(.running)) }
        if old.recent().prefix(SystemDefaults.recentLimit) != new.recent().prefix(SystemDefaults.recentLimit) { reloads.insert(.widget(.recent)) }
        if old.lastProject != new.lastProject { reloads.insert(.control(.newPrompt)) }
        return reloads
    }
}

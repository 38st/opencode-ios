import Foundation
import Observation
import OCIntents
import OCModels
import OCNetworking
import OCShared

/// The app's system surfaces: the App Group snapshot that widgets, controls and intents read, and Spotlight.
@MainActor @Observable public final class SystemIntegration {
    /// Session titles, project and server names in Spotlight; on by default.
    public private(set) var spotlightEnabled: Bool
    /// New prompt's project: where a session was last opened or sent to.
    @ObservationIgnored public private(set) var lastProject: SystemSnapshot.ProjectRef?
    @ObservationIgnored private(set) var publisher: SystemSnapshotPublisher?
    @ObservationIgnored let spotlight: SpotlightIndexer
    @ObservationIgnored private let store: SystemSnapshotStore?
    @ObservationIgnored private let clock: NetworkClock
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let reload: @MainActor (Set<SystemReload>) -> Void
    @ObservationIgnored private let shortcutsChanged: @MainActor () -> Void
    @ObservationIgnored private weak var registry: ServerRegistry?
    /// Servers seen online at the last build, and when each was last seen online, for the widgets' staleness.
    @ObservationIgnored private var online: Set<String> = []
    @ObservationIgnored private var lastSeen: [String: Date] = [:]
    /// The snapshot written before this launch: what the app knew of each server's requests and runs until it syncs.
    @ObservationIgnored private let launch: SystemSnapshot?
    public static let spotlightKey = "spotlightIndexing"

    public init(store: SystemSnapshotStore?, index: any SpotlightIndexing, manifest: URL?, defaults: UserDefaults?, clock: NetworkClock = .init(),
                reload: @escaping @MainActor (Set<SystemReload>) -> Void, shortcutsChanged: @escaping @MainActor () -> Void = {}) {
        self.store = store; self.clock = clock; self.defaults = defaults; self.reload = reload; self.shortcutsChanged = shortcutsChanged
        let enabled = defaults?.object(forKey: Self.spotlightKey) as? Bool ?? SystemDefaults.spotlightEnabled
        spotlightEnabled = enabled
        spotlight = SpotlightIndexer(index: index, manifest: manifest, enabled: enabled, clock: clock)
        let previous = store?.read().snapshot
        launch = previous
        lastProject = previous?.lastProject
        for server in previous?.servers ?? [] {
            lastSeen[server.id] = server.reachability == .online ? previous?.writtenAt : server.syncedAt
        }
    }
    /// What the snapshot last said, for answers that come before the servers have synced.
    public var snapshot: SystemSnapshot? { publisher?.last ?? store?.read().snapshot }

    /// Starts writing the snapshot and indexing once the registry has loaded its servers.
    func start(_ registry: ServerRegistry) {
        guard publisher == nil else { return }
        self.registry = registry
        let publisher = SystemSnapshotPublisher(store: store, clock: clock, build: { [weak self] now in
            self?.build(now) ?? SystemSnapshot(writtenAt: now)
        }, reload: reload, written: { [weak self] old, new in
            // Siri's parameter phrases follow the sessions the snapshot offers.
            if Set(old?.sessions.map(\.id) ?? []) != Set(new.sessions.map(\.id)) { self?.shortcutsChanged() }
        })
        self.publisher = publisher
        publisher.start()
        spotlight.start { [weak registry] in SpotlightIndexer.items(registry?.servers ?? []) }
    }
    func stop() { publisher?.stop(); spotlight.stop() }
    public func setSpotlight(_ enabled: Bool) async {
        guard enabled != spotlightEnabled else { return }
        spotlightEnabled = enabled
        defaults?.set(enabled, forKey: Self.spotlightKey)
        // Siri's parameter phrases are session titles too: they follow the switch.
        shortcutsChanged()
        await spotlight.setEnabled(enabled)
    }
    /// Indexes every session again, as after the cache was reset.
    public func rebuildSpotlight() async { await spotlight.rebuild() }
    /// A removed server's sessions leave the snapshot, the widgets and Spotlight at once.
    func remove(_ server: ServerID) async {
        let id = server.rawValue.uuidString
        if lastProject?.server == id { lastProject = nil }
        online.remove(id); lastSeen[id] = nil
        publisher?.flush()
        await spotlight.removeServer(id)
    }
    /// Writes now: the app is going to the background, and the widgets should show the servers paused.
    func flush() { publisher?.flush() }
    /// The user opened or sent to a session: New prompt starts in its project.
    func used(_ server: ServerStore, sessionID: String) {
        guard let session = server.sessions[sessionID], session.info.parentID == nil, !session.info.projectID.isEmpty else { return }
        let next = SystemSnapshot.ProjectRef(server: server.id.rawValue.uuidString, project: session.info.projectID,
                                             name: SessionSummary(server: server, session: session).projectName)
        guard next != lastProject else { return }
        lastProject = next
        publisher?.changed()
    }
    private func build(_ now: Date) -> SystemSnapshot {
        SystemSnapshotBuilder.build(registry?.servers ?? [], phase: registry?.phase ?? .active, lastProject: lastProject, carried: carried(),
                                    suggestsSessions: spotlightEnabled,
                                    syncedAt: { [self] server, reachability in syncedAt(server, reachability, now: now) }, now: now)
    }
    /// After a cold launch the cache has no requests, so until a server has fetched them its sessions would read idle:
    /// they keep the waiting or running state the last snapshot gave them, which also goes stale as it should.
    func carried() -> [String: SystemSnapshot.Session] {
        let unsynced = Set((registry?.servers ?? []).filter { !$0.readPath.requestsSynced }.map { $0.id.rawValue.uuidString })
        guard let launch, !unsynced.isEmpty else { return [:] }
        let rows = launch.sessions.filter { unsynced.contains($0.server) && [.needsYou, .running, .retrying].contains($0.status) }
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    /// Nil while online; otherwise when the app last saw the server online, or its last sync.
    private func syncedAt(_ server: ServerStore, _ reachability: SystemSnapshot.Reachability, now: Date) -> Date? {
        let id = server.id.rawValue.uuidString
        if reachability == .online { online.insert(id); return nil }
        if online.remove(id) != nil { lastSeen[id] = now }
        return lastSeen[id] ?? server.readPath.lastStatusSync
    }
}

#if os(iOS)
import WidgetKit

/// The live reloads: WidgetKit timelines and controls, and Siri's parameter phrases.
@MainActor enum SystemReloads {
    static func apply(_ reloads: Set<SystemReload>) {
        for reload in reloads {
            switch reload {
            case .widget(let kind): WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
            case .control(let kind): ControlCenter.shared.reloadControls(ofKind: kind.rawValue)
            }
        }
    }
    /// The app's App Shortcuts provider lives in the app target, which sets this.
    static func shortcutsChanged() { ApplicationServices.appShortcutsChanged() }
}
#endif

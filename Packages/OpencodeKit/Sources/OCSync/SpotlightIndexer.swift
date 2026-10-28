import Foundation
import Observation
import OCIntents
import OCModels
import OCNetworking
import OCShared

/// One session in Spotlight: its title, project and server name, never its conversation.
nonisolated public struct SpotlightItem: Hashable, Sendable {
    public var server: String
    public var session: String
    public var title: String
    public var project: String
    public var serverName: String
    /// The day of the last activity.
    public var day: Date
    public init(server: String, session: String, title: String, project: String, serverName: String, day: Date) {
        self.server = server; self.session = session; self.title = title; self.project = project; self.serverName = serverName; self.day = day
    }
    /// The item's identifier, which is also its session entity's: `<server>:<session>`.
    public var id: String { server + ":" + session }
    /// One domain per server, so removing a server removes all of its items at once.
    public var domain: String { SpotlightItem.domain(server) }
    public static func domain(_ server: String) -> String { "server." + server }
    public var entity: SessionEntity { .init(server: server, session: session, title: title, project: project, serverName: serverName, activity: day) }
    /// What a change must touch for the item to be indexed again.
    var fingerprint: String { [title, project, serverName, String(day.timeIntervalSince1970)].joined(separator: "\u{1F}") }
}

/// Where the items go: Core Spotlight in the app, a recorder in tests.
nonisolated public protocol SpotlightIndexing: Sendable {
    func index(_ items: [SpotlightItem]) async throws
    func delete(ids: [String]) async throws
    func delete(domains: [String]) async throws
    func deleteAll() async throws
}

/// Keeps Spotlight's items equal to the cached root sessions. Changes are applied incrementally against a manifest of
/// what was indexed, kept beside the cache; a missing or older manifest, or switching indexing on, rebuilds it all.
@MainActor final class SpotlightIndexer {
    private struct Manifest: Codable {
        static let currentVersion = 1
        var version = Manifest.currentVersion
        var items: [String: String] = [:]
    }
    private let index: any SpotlightIndexing
    private let manifestURL: URL?
    private let clock: NetworkClock
    private let delay: Duration
    private(set) var enabled: Bool
    private var manifest: Manifest?
    private var items: (@MainActor () -> [SpotlightItem])?
    private var work: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    init(index: any SpotlightIndexing, manifest: URL?, enabled: Bool, clock: NetworkClock = .init(), delay: Duration = .seconds(2)) {
        self.index = index; self.manifestURL = manifest; self.enabled = enabled; self.clock = clock; self.delay = delay
        if let manifest, let data = try? Data(contentsOf: manifest), let value = try? JSONDecoder().decode(Manifest.self, from: data),
           value.version == Manifest.currentVersion { self.manifest = value }
    }
    deinit { work?.cancel(); pending?.cancel() }
    /// Indexes what the app has and follows its changes. Switched off, it deletes whatever a switch-off that failed,
    /// or that the app did not live to finish, left in Spotlight.
    func start(items: @escaping @MainActor () -> [SpotlightItem]) {
        self.items = items
        if enabled { sync() } else { enqueue { indexer in await indexer.purge() } }
    }
    func stop() { items = nil; pending?.cancel(); pending = nil }
    /// Switching off removes every item; switching on indexes everything again.
    func setEnabled(_ value: Bool) async {
        guard value != enabled else { return }
        enabled = value
        if !value { pending?.cancel(); pending = nil }
        enqueue { indexer in
            if value { indexer.manifest = nil; await indexer.apply() }
            else { await indexer.purge() }
        }
        await work?.value
    }
    /// Deletes every item. The manifest goes only once Spotlight has done it; a failure is retried at the next launch.
    private func purge() async {
        do { try await index.deleteAll(); save(nil) } catch {}
    }
    /// Indexes everything again, as after the cache was reset.
    func rebuild() async {
        enqueue { indexer in indexer.manifest = nil; await indexer.apply() }
        await work?.value
    }
    /// A removed server's items go at once, by its domain.
    func removeServer(_ id: String) async {
        enqueue { indexer in
            guard indexer.enabled else { return }
            try? await indexer.index.delete(domains: [SpotlightItem.domain(id)])
            if var manifest = indexer.manifest {
                manifest.items = manifest.items.filter { !$0.key.hasPrefix(id + ":") }
                indexer.save(manifest)
            }
        }
        await work?.value
    }
    /// Waits for the work already queued.
    func settle() async { await work?.value }
    private func sync() {
        enqueue { indexer in await indexer.apply() }
    }
    private func changed() {
        guard items != nil, enabled else { return }
        pending?.cancel()
        pending = Task { [weak self, clock, delay] in
            do { try await clock.sleep(delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.sync()
        }
    }
    private func enqueue(_ operation: @escaping @MainActor (SpotlightIndexer) async -> Void) {
        let previous = work
        work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }
    /// Brings the index in line with the current items: everything after a missing manifest, else what changed.
    private func apply() async {
        guard enabled, let source = items else { return }
        let current = withObservationTracking { source() } onChange: { [weak self] in
            Task { @MainActor in self?.changed() }
        }
        let wanted = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        do {
            if let manifest {
                let changed = wanted.values.filter { manifest.items[$0.id] != $0.fingerprint }
                let removed = manifest.items.keys.filter { wanted[$0] == nil }
                if !removed.isEmpty { try await index.delete(ids: removed.sorted()) }
                if !changed.isEmpty { try await index.index(changed.sorted { $0.id < $1.id }) }
                if changed.isEmpty && removed.isEmpty { return }
            } else {
                try await index.deleteAll()
                if !wanted.isEmpty { try await index.index(wanted.values.sorted { $0.id < $1.id }) }
            }
            save(Manifest(items: wanted.mapValues(\.fingerprint)))
        } catch {
            // Rebuild next time: the index may hold part of this pass.
            save(nil)
        }
    }
    private func save(_ value: Manifest?) {
        manifest = value
        guard let manifestURL else { return }
        if let value, let data = try? JSONEncoder().encode(value) {
            try? FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: manifestURL, options: .atomic)
        } else { try? FileManager.default.removeItem(at: manifestURL) }
    }
    /// Every cached root session the app shows: not hidden, not archived.
    static func items(_ servers: [ServerStore]) -> [SpotlightItem] {
        servers.flatMap { server in
            server.sessions.values.compactMap { session -> SpotlightItem? in
                guard session.info.parentID == nil, session.info.time.archived == nil,
                      server.readPath.localMeta[session.id]?.hidden != true else { return nil }
                let summary = SessionSummary(server: server, session: session)
                return SpotlightItem(server: server.id.rawValue.uuidString, session: session.id, title: session.info.title ?? "Untitled session",
                                     project: summary.projectName, serverName: server.record.name,
                                     day: Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: summary.activity / 1_000)))
            }
        }
    }
}

#if os(iOS)
import AppIntents
import CoreSpotlight

/// Core Spotlight, in a named index whose files are only readable while the device is unlocked.
nonisolated public struct CoreSpotlightIndex: SpotlightIndexing {
    let name: String
    public init(name: String = "sessions") { self.name = name }
    private var searchable: CSSearchableIndex { CSSearchableIndex(name: name, protectionClass: .complete) }
    public func index(_ items: [SpotlightItem]) async throws {
        let values = items.map { item in
            let attributes = item.entity.attributeSet
            // A tap on the result can then run Open a session for this entity.
            attributes.associateAppEntity(item.entity, priority: 0)
            let value = CSSearchableItem(uniqueIdentifier: item.id, domainIdentifier: item.domain, attributeSet: attributes)
            // Items otherwise expire after 30 days; the app removes them itself.
            value.expirationDate = .distantFuture
            return value
        }
        try await searchable.indexSearchableItems(values)
    }
    public func delete(ids: [String]) async throws { try await searchable.deleteSearchableItems(withIdentifiers: ids) }
    public func delete(domains: [String]) async throws { try await searchable.deleteSearchableItems(withDomainIdentifiers: domains) }
    public func deleteAll() async throws { try await searchable.deleteAllSearchableItems() }
}
#endif

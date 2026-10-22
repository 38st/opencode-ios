import Foundation
import Observation
import OCModels
import OCNetworking
import OCSecurity
import OCPersistence

public enum AppScenePhase: Sendable { case active, inactive, background }

@MainActor @Observable public final class ServerRegistry {
    public private(set) var servers: [ServerStore] = []
    public private(set) var isLoaded = false
    public private(set) var isLoading = false
    public private(set) var error: String?
    public private(set) var localNetworkExplained: Bool
    public private(set) var requiresLocalNetworkExplanation = false
    public private(set) var phase: AppScenePhase = .inactive
    @ObservationIgnored private let records: any ServerRecordStore
    @ObservationIgnored private let residency = TranscriptResidency()
    @ObservationIgnored private let cache: CacheStore?
    public let drafts: DraftStore?
    @ObservationIgnored private let credentials: CredentialStore
    @ObservationIgnored private let clock: NetworkClock
    @ObservationIgnored private let background: any BackgroundTaskProviding
    @ObservationIgnored private let pathMonitor: (any NetworkPathMonitoring)?
    @ObservationIgnored private let factory: @Sendable (ServerRecord, Credential?, [String: String]) -> any ConnectionControlling
    @ObservationIgnored private let fetchInfo: (@Sendable (URL, Credential?, [String: String]) async throws -> ServerInfo)?
    @ObservationIgnored private let rememberLocalNetwork: @MainActor () -> Void
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, any Error>?
    @ObservationIgnored private var lastPath: NetworkPathStatus?
    @ObservationIgnored private var pathChanged = false
    @ObservationIgnored private var pathGeneration = 0

    public init(records: any ServerRecordStore, credentials: CredentialStore, cache: CacheStore? = nil, clock: NetworkClock = .init(),
                background: (any BackgroundTaskProviding)? = nil,
                pathMonitor: (any NetworkPathMonitoring)? = NetworkPathMonitor(),
                localNetworkExplained: Bool = false, rememberLocalNetwork: @escaping @MainActor () -> Void = {},
                fetchInfo: (@Sendable (URL, Credential?, [String: String]) async throws -> ServerInfo)? = nil,
                factory: (@Sendable (ServerRecord, Credential?, [String: String]) -> any ConnectionControlling)? = nil) {
        self.cache = cache; self.drafts = cache.map { DraftStore(writer: $0.writer) }
        self.records = records; self.credentials = credentials; self.clock = clock
        self.background = background ?? SystemBackgroundTaskProvider(); self.pathMonitor = pathMonitor
        self.localNetworkExplained = localNetworkExplained; self.rememberLocalNetwork = rememberLocalNetwork
        self.fetchInfo = fetchInfo
        // The OS cannot establish that a Wi-Fi network is trusted. Prefer TLS by default.
        self.factory = factory ?? { record, credential, headers in
            ServerConnection(endpoints: record.endpoints, credential: credential, headers: headers,
                             clock: clock, pathMonitor: nil, prefersHTTPS: true, allowsLocalNetwork: localNetworkExplained)
        }
    }
    #if DEBUG
    @ObservationIgnored public private(set) var uiTestDefaults: UserDefaults?
    public var connectionDiagnostics: String {
        (["loaded=\(isLoaded) phase=\(phase) localNetworkExplained=\(localNetworkExplained) explanationRequired=\(requiresLocalNetworkExplanation)"] + servers.map {
            "server=\($0.id.rawValue) state=\($0.state.diagnosticName)\n" + $0.diagnosticsExport()
        }).joined(separator: "\n\n")
    }
    #endif
    public static func live() async throws -> ServerRegistry {
        #if DEBUG
        if let storage = UITestStorage(environment: ProcessInfo.processInfo.environment, arguments: ProcessInfo.processInfo.arguments) {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
            let secrets = KeychainStore(service: storage.service)
            guard let defaults = UserDefaults(suiteName: storage.service) else { throw CocoaError(.fileWriteUnknown) }
            try await storage.reset(in: directory, defaults: defaults) { try await secrets.resetForUITesting() }
            let cacheDirectory = directory.appending(path: "UITests/" + storage.id)
            if storage.resetsOnLaunch, FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
            let writer = try PersistenceWriter(url: cacheDirectory.appending(path: "cache.sqlite"))
            await FileCache.shared.relocate(to: cacheDirectory.appending(path: "files"))
            let registry = ServerRegistry(records: JSONServerRecordStore(url: storage.recordsURL(in: directory)),
                                  credentials: CredentialStore(secrets: secrets), cache: CacheStore(writer: writer),
                                  localNetworkExplained: defaults.bool(forKey: storage.explanationKey),
                                  rememberLocalNetwork: { defaults.set(true, forKey: storage.explanationKey) })
            registry.uiTestDefaults = defaults
            return registry
        }
        #endif
        let writer = try PersistenceWriter.applicationSupport()
        let legacy = try JSONServerRecordStore.applicationSupport()
        return ServerRegistry(records: GRDBServerRecordStore(writer: writer, legacyURL: legacy.url),
                       credentials: CredentialStore(secrets: KeychainStore()), cache: CacheStore(writer: writer),
                       localNetworkExplained: UserDefaults.standard.bool(forKey: "localNetworkExplained"),
                       rememberLocalNetwork: { UserDefaults.standard.set(true, forKey: "localNetworkExplained") })
    }
    deinit { pathTask?.cancel(); debounceTask?.cancel(); lifecycleTask?.cancel(); saveTask?.cancel() }

    public func load() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await records.load()
            var stores: [ServerStore] = []
            for record in loaded { stores.append(try await makeStore(record)) }
            servers = stores
            isLoaded = true
            error = nil
            if phase == .active {
                for server in servers where mayConnect(server) { await server.start() }
            }
            if let pathMonitor {
                pathTask = Task { [weak self] in
                    for await path in pathMonitor.updates() {
                        guard !Task.isCancelled else { return }
                        self?.networkPathChanged(path)
                    }
                }
            }
        } catch { self.error = "Could not load saved servers or their Keychain credentials. Try again." }
    }
    private func makeStore(_ record: ServerRecord) async throws -> ServerStore {
        let credential = try await credentials.credential(for: record.id)
        let headers = try await credentials.headers(for: record.id)
        let connection = factory(record, credential, headers)
        if localNetworkExplained { await connection.allowLocalNetwork() }
        let store = ServerStore(record: record, connection: connection, credentials: credentials,
                           clock: clock, cache: cache, residency: residency, drafts: drafts, background: background, fetchInfo: fetchInfo, canConnect: { [weak self] in
                               guard let self, self.phase == .active,
                                     let store = self.servers.first(where: { $0.id == record.id }) else { return false }
                               return self.mayConnect(store)
                           }, recordChanged: { [weak self] in try await self?.persist() })
        try await store.readPath.loadCache()
        return store
    }
    public func persist() async throws {
        if !localNetworkExplained && servers.contains(where: { $0.record.endpoints.contains(where: { $0.kind == .lan }) }) {
            requiresLocalNetworkExplanation = true
        }
        let snapshot = servers.map(\.record), previous = saveTask
        let next = Task { [records] in
            _ = try? await previous?.value
            try Task.checkCancellation()
            try await records.save(snapshot)
        }
        saveTask = next
        try await next.value
    }
    @discardableResult public func add(_ record: ServerRecord, credential: Credential) async throws -> ServerStore {
        guard isLoaded else { throw ServerSetupError.notLoaded }
        guard !servers.contains(where: { $0.id == record.id }) else { throw ServerSetupError.duplicateServer }
        for endpoint in record.endpoints { try EndpointPolicy.validate(endpoint.url) }
        guard !record.endpoints.isEmpty else { throw ServerSetupError.invalidURL }
        try await credentials.save(credential, for: record.id)
        let store: ServerStore
        do { store = try await makeStore(record) }
        catch { try? await credentials.delete(for: record.id); throw error }
        servers.append(store)
        do { try await persist() }
        catch {
            servers.removeAll { $0.id == record.id }; await store.dispose()
            try? await credentials.delete(for: record.id)
            throw error
        }
        if phase == .active && mayConnect(store) {
            if let lastPath { await store.connection.setNetworkPath(lastPath) }
            await store.start()
        }
        return store
    }
    public func rename(_ server: ServerStore, to name: String) async throws { try await server.rename(name) }
    public func remove(_ server: ServerStore) async throws {
        await server.suspend()
        // Delete the secret first: a failed file write can leave a repairable record, never an orphaned secret.
        do { try await credentials.delete(for: server.id) }
        catch {
            if phase == .active && mayConnect(server) { await server.start() }
            throw error
        }
        await server.dispose()
        await FileCache.shared.removeServer(server.readPath.serverID)
        servers.removeAll { $0.id == server.id }
        try await persist()
    }
    public func acknowledgeLocalNetwork() async {
        localNetworkExplained = true; requiresLocalNetworkExplanation = false; rememberLocalNetwork()
        for server in servers {
            await server.connection.allowLocalNetwork()
            if phase == .active && server.record.autoConnect { await server.start() }
        }
    }
    public func needsLocalNetworkExplanation(address: String, pairing: Bool) -> Bool {
        guard !localNetworkExplained else { return false }
        let urls = pairing ? (try? PairingParser.parse(address).urls) ?? [] : [PairingParser.serverAddress(address)].compactMap { $0 }
        return urls.contains { EndpointPolicy.classify($0) == .lan }
    }
    private func mayConnect(_ server: ServerStore) -> Bool {
        if !localNetworkExplained && server.record.endpoints.contains(where: { $0.kind == .lan }) {
            requiresLocalNetworkExplanation = true; return false
        }
        return server.record.autoConnect
    }
    public func setScenePhase(_ next: AppScenePhase) async {
        let previous = lifecycleTask
        let task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.transition(to: next)
        }
        lifecycleTask = task
        await task.value
    }
    private func transition(to next: AppScenePhase) async {
        let previous = phase
        phase = next
        switch next {
        case .background:
            debounceTask?.cancel(); debounceTask = nil
            let lease = BackgroundLease(provider: background)
            lease.begin()
            defer { lease.end() }
            do { for server in servers { try await server.readPath.flushComposers() }; try await drafts?.flush() } catch { self.error = "Could not save drafts before pausing." }
            do { try await persist() } catch { self.error = "Could not save servers before pausing." }
            for server in servers {
                await server.readPath.flushWrites()
                await server.suspend()
            }
        case .active:
            guard previous != .active else { return }
            let generation = pathGeneration
            for server in servers where mayConnect(server) {
                if let lastPath { await server.connection.setNetworkPath(lastPath) }
                await server.resume(pathChanged: pathChanged)
            }
            if generation == pathGeneration { pathChanged = false }
        case .inactive:
            do { for server in servers { try await server.readPath.flushComposers() }; try await drafts?.flush() } catch { self.error = "Could not save drafts." }
        }
    }
    public func networkPathChanged(_ path: NetworkPathStatus) {
        // NWPath can change routes without changing this coarse interface summary.
        let initial = lastPath == nil
        lastPath = path
        guard !initial else {
            debounceTask = Task { [weak self] in
                guard let self else { return }
                for server in self.servers { await server.connection.setNetworkPath(path) }
            }
            return
        }
        pathGeneration += 1
        let generation = pathGeneration
        pathChanged = true
        debounceTask?.cancel()
        guard phase == .active else { return }
        debounceTask = Task { [weak self, clock] in
            do { try await clock.sleep(.milliseconds(500)); try Task.checkCancellation() } catch { return }
            guard let self, self.phase == .active else { return }
            for server in self.servers where self.mayConnect(server) {
                await server.connection.setNetworkPath(path)
                await server.reconnect(reason: .networkPathChanged)
            }
            if !Task.isCancelled && generation == self.pathGeneration { self.pathChanged = false }
        }
    }
    public func refresh() async {
        for server in servers where mayConnect(server) { await server.reconnect() }
    }
    public func shutdown() async {
        pathTask?.cancel(); debounceTask?.cancel()
        await lifecycleTask?.value
        for server in servers { await server.dispose() }
        _ = try? await saveTask?.value
    }
}

@MainActor final class BackgroundLease {
    let provider: any BackgroundTaskProviding
    var id: Int?
    init(provider: any BackgroundTaskProviding) { self.provider = provider }
    func begin(expiration: @escaping @MainActor @Sendable () -> Void = {}) {
        id = provider.begin { [weak self] in expiration(); self?.end() }
    }
    func end() {
        guard let id else { return }
        self.id = nil
        if id != -1 { provider.end(id) }
    }
}

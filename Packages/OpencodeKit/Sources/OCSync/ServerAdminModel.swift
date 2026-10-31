// One server's settings: providers and accounts, MCP servers, saved permissions, the agent, command, skill, plugin and
// reference catalogs, projects, configuration, booted locations and worktrees. Location-scoped reads use the chosen
// project's directory. Nothing here is persisted: credentials never reach the device beyond one connect request.
import Foundation
import Observation
import OCFoundation
import OCModels
import OCNetworking

@MainActor @Observable public final class ServerAdminModel {
    /// The project whose location answers location-scoped reads.
    public var directory: String? {
        didSet { if oldValue != directory { invalidateLocation() } }
    }
    public let integrations = Revalidating<[IntegrationInfo]>()
    public let plugins = Revalidating<[PluginInfo]>()
    public let config = Revalidating<[ConfigEntry]>()
    public let shells = Revalidating<[ShellOption]>()
    public let locations = Revalidating<[Location]>()
    public let archivedProjects = Revalidating<[Project]>()
    public private(set) var savedPermissions: [String: Revalidating<[SavedPermission]>] = [:]
    public private(set) var worktrees: [String: Revalidating<[WorktreeInfo]>] = [:]
    public private(set) var connect: ConnectFlow?
    /// `installation.update-available`, while this app runs.
    public private(set) var availableUpdate: String?
    public private(set) var busy: Set<String> = []
    public var error: String?
    /// A short confirmation of the last action ("Mock connected").
    public var notice: String?
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored let clock: any Clock<Duration>
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let log: @Sendable (RedactedLogMessage) -> Void

    init(store: ReadStore, clock: any Clock<Duration> = ContinuousClock(), now: @escaping @Sendable () -> Date = Date.init,
         log: @escaping @Sendable (RedactedLogMessage) -> Void = { OCLog.sync.info($0) }) {
        self.store = store; self.clock = clock; self.now = now; self.log = log
    }

    /// Projects by recent activity, archived ones hidden.
    public var projects: [Project] {
        (store?.projects ?? []).filter { $0.time.archived == nil }.sorted { ($0.time.active ?? 0) > ($1.time.active ?? 0) }
    }
    public var project: Project? { projects.first { $0.canonical == directory } }
    public var catalog: LocationCatalog? { directory.flatMap { store?.catalog(for: .init(directory: $0)) } }
    /// Picks the most recently active project when none is chosen or the chosen one disappeared.
    public func appear() {
        if directory == nil || !projects.contains(where: { $0.canonical == directory }) { directory = projects.first?.canonical }
    }
    public func isBusy(_ key: String) -> Bool { busy.contains(key) }
    func belongs(to other: ReadStore) -> Bool { store === other }

    // MARK: Loading
    public func loadIntegrations() async {
        guard let directory else { return }
        await load(integrations) { api in try await api.send(AdminEndpoints.integrations(directory)).data.values }
    }
    public func loadCatalogs() async {
        guard let directory, let store else { return }
        do { try await store.refreshCatalogs(directory) } catch { report(error) }
    }
    public func loadPlugins() async {
        guard let directory else { return }
        await load(plugins) { api in try await api.send(AdminEndpoints.plugins(directory)).data.values }
    }
    public func loadConfig() async {
        guard let directory else { return }
        await load(config) { api in try await api.send(AdminEndpoints.config(directory)).values }
        await load(shells) { api in try await api.send(TerminalEndpoints.shells).values }
    }
    public func loadLocations() async {
        await load(locations) { api in try await api.send(AdminEndpoints.bootedLocations).values }
    }
    public func loadArchivedProjects() async {
        await load(archivedProjects) { api in try await api.send(AdminEndpoints.archivedProjects).values }
    }
    public func savedPermissions(for projectID: String) -> Revalidating<[SavedPermission]> {
        if let value = savedPermissions[projectID] { return value }
        let value = Revalidating<[SavedPermission]>(); savedPermissions[projectID] = value; return value
    }
    public func loadSavedPermissions(projectID: String) async {
        await load(savedPermissions(for: projectID)) { api in
            try await api.send(AdminEndpoints.savedPermissions(projectID: projectID)).data.values.sorted { $0.created > $1.created }
        }
    }
    public func worktrees(for projectID: String) -> Revalidating<[WorktreeInfo]> {
        if let value = worktrees[projectID] { return value }
        let value = Revalidating<[WorktreeInfo]>(); worktrees[projectID] = value; return value
    }
    public func loadWorktrees(projectID: String) async {
        await load(worktrees(for: projectID)) { api in try await api.send(ComposerEndpoints.worktrees(projectID: projectID)).values }
    }

    // MARK: Providers and accounts
    /// Sends the key once; the caller's field is cleared whatever the outcome.
    public func connectKey(_ integration: IntegrationInfo, key: String, answers: JSONValue?, label: String?) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let directory, !key.isEmpty else { return false }
        log("Connecting an integration with an API key")
        let succeeded = await perform("connect:" + integration.id) { api in
            try await api.send(AdminEndpoints.connectKey(integration.id, directory: directory, key: key, answers: answers, label: label))
        }
        if succeeded { notice = localized("\(integration.name) connected", comment: "%@ is a provider or integration name"); integrations.invalidate(); await loadIntegrations() }
        return succeeded
    }
    /// Starts an OAuth or command sign-in; the flow reports back through `connect`.
    public func beginConnect(_ integration: IntegrationInfo, method: IntegrationMethod, answers: JSONValue? = nil) {
        guard let directory, let client = store?.client else { return }
        connect?.cancel()
        log("Starting a sign-in")
        connect = ConnectFlow(integration: integration, method: method, directory: directory, answers: answers, client: client,
                              clock: clock, now: now) { [weak self] phase in
            guard let self else { return }
            if phase == .complete {
                self.notice = localized("\(integration.name) connected", comment: "%@ is a provider or integration name")
                self.integrations.invalidate(); self.catalog?.mcp.invalidate()
                self.owned { await $0.loadIntegrations() }
            }
        }
    }
    public func endConnect() { connect?.cancel(); connect = nil }
    public func rename(_ account: IntegrationConnection, label: String) async -> Bool {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return false }
        return await accountAction(account) { try AdminEndpoints.renameCredential(account.credentialID, label: label) }
    }
    public func activate(_ account: IntegrationConnection) async -> Bool {
        await accountAction(account) { AdminEndpoints.activateCredential(account.credentialID) }
    }
    public func remove(_ account: IntegrationConnection) async -> Bool {
        await accountAction(account) { AdminEndpoints.removeCredential(account.credentialID) }
    }
    private func accountAction(_ account: IntegrationConnection, _ endpoint: @escaping @Sendable () throws -> Endpoint<Void>) async -> Bool {
        let succeeded = await perform("account:" + account.credentialID) { api in try await api.send(endpoint()) }
        if succeeded { integrations.invalidate(); await loadIntegrations() }
        return succeeded
    }

    // MARK: MCP
    /// Runtime only: the server forgets it when it restarts.
    public func setMCP(_ name: String, connected: Bool) async {
        guard let directory else { return }
        let succeeded = await perform("mcp:" + name) { api in
            try await api.send(connected ? AdminEndpoints.mcpConnect(name, directory: directory) : AdminEndpoints.mcpDisconnect(name, directory: directory))
        }
        if succeeded { catalog?.mcp.invalidate(); await loadCatalogs() }
    }

    // MARK: Saved permissions
    public func deleteSavedPermission(_ rule: SavedPermission) async -> Bool {
        let succeeded = await perform("saved:" + rule.id, notFoundIsSuccess: true) { api in
            try await api.send(AdminEndpoints.deleteSavedPermission(rule.id))
        }
        if succeeded {
            let list = savedPermissions(for: rule.projectID)
            list.seed((list.value ?? []).filter { $0.id != rule.id }); list.invalidate()
        }
        return succeeded
    }

    // MARK: Plugins
    public func checkPlugins() async {
        guard let directory else { return }
        _ = await perform("plugins:check") { [plugins] api in
            plugins.seed(try await api.send(AdminEndpoints.checkPlugins(directory)).data.values)
        }
    }
    public func updatePlugins(_ targets: [String]) async {
        guard let directory, !targets.isEmpty else { return }
        let done = await perform("plugins:update") { api in try await api.send(AdminEndpoints.updatePlugins(directory, targets: targets)) }
        if done {
            notice = targets.count == 1 ? localized("Updating \(targets[0])", comment: "%@ is a plugin name") : localized("Updating \(targets.count) plugins", comment: "%lld is a number of plugins")
            plugins.invalidate(); await loadPlugins()
        }
    }

    // MARK: Projects
    public func updateProject(_ project: Project, name: String?, color: String?, iconOverride: String?, startCommand: String?) async -> Bool {
        var icon: JSONValue?
        if color != nil || iconOverride != nil {
            var value = project.icon?.raw ?? .object([:])
            if let color { value.set("color", .string(color)) }
            if let iconOverride { value.set("override", .string(iconOverride)) }
            icon = value
        }
        return await perform("project:" + project.id) { [weak store] api in
            let updated = try await api.send(AdminEndpoints.updateProject(project.id, name: name, icon: icon, startCommand: startCommand))
            store?.projects.removeAll { $0.id == updated.id }; store?.projects.append(updated)
        }
    }

    // MARK: Configuration
    public func setShell(_ path: String?) async -> Bool {
        let succeeded = await perform("shell") { api in try await api.send(AdminEndpoints.setShell(path)) }
        if succeeded { config.invalidate(); await loadConfig() }
        return succeeded
    }
    /// The effective shell: the highest-precedence document that sets one.
    public var configuredShell: String? {
        (config.value ?? []).reversed().lazy.compactMap { $0.info?["shell"]?.stringValue }.first
    }

    // MARK: Administration
    public func evict(_ location: Location) async {
        let done = await perform("evict:" + location.directory) { api in try await api.send(AdminEndpoints.evictLocation(location.directory)) }
        if done {
            locations.seed((locations.value ?? []).filter { $0.directory != location.directory }); locations.invalidate()
            await loadLocations()
        }
    }
    public func reloadLocations() async {
        let done = await perform("reload") { api in try await api.send(AdminEndpoints.reloadLocations) }
        if done {
            notice = localized("Configuration reloaded")
            integrations.invalidate(); plugins.invalidate(); config.invalidate(); catalog?.invalidate()
        }
    }

    // MARK: Worktrees
    public func createWorktree(projectID: String, name: String?) async -> WorktreeInfo? {
        var created: WorktreeInfo?
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = await perform("worktree:create") { api in
            created = try await api.send(AdminEndpoints.createWorktree(projectID: projectID, name: name?.isEmpty == false ? name : nil))
        }
        if done {
            worktrees(for: projectID).invalidate(); await loadWorktrees(projectID: projectID)
        }
        return created
    }
    public func refreshWorktrees(projectID: String) async {
        let done = await perform("worktree:refresh") { api in try await api.send(AdminEndpoints.refreshWorktrees(projectID: projectID)) }
        if done {
            worktrees(for: projectID).invalidate(); await loadWorktrees(projectID: projectID)
        }
    }
    /// The uncommitted changes a removal would lose; `nil` when they could not be read.
    public func uncommittedChanges(in worktree: WorktreeInfo) async -> [FileDiff]? {
        guard let api = try? await store?.client?() else { return nil }
        return try? await api.send(AdminEndpoints.vcsStatus(worktree.directory)).data.values
    }
    public enum WorktreeRemoval: Equatable, Sendable { case removed, forceRequired(String), failed }
    /// Without `force`, a worktree the server finds dirty is kept and answers `forceRequired`.
    public func removeWorktree(_ worktree: WorktreeInfo, projectID: String, force: Bool) async -> WorktreeRemoval {
        let key = "worktree:" + worktree.directory
        guard let client = store?.client, !busy.contains(key) else { return .failed }
        busy.insert(key); defer { busy.remove(key) }
        do {
            try await client().send(AdminEndpoints.removeWorktree(projectID: projectID, directory: worktree.directory, force: force))
        } catch APIError.server(_, _, let body) where WorktreeFailure(raw: body).forceRequired && !force {
            return .forceRequired(WorktreeFailure(raw: body).message)
        } catch { report(error); return .failed }
        let list = worktrees(for: projectID)
        list.seed((list.value ?? []).filter { $0.directory != worktree.directory }); list.invalidate()
        await loadWorktrees(projectID: projectID)
        return .removed
    }

    // MARK: Events
    /// Lists a screen has loaded reload when the server says they changed.
    func handle(type: String, payload: JSONValue) {
        switch type {
        case "integration.updated", "credential.updated", "credential.switched":
            integrations.invalidate(); if integrations.value != nil { owned { await $0.loadIntegrations() } }
        case "plugin.updated": plugins.invalidate(); if plugins.value != nil { owned { await $0.loadPlugins() } }
        case "config.updated": config.invalidate(); if config.value != nil { owned { await $0.loadConfig() } }
        case "location.shutdown": locations.invalidate()
        case "worktree.updated", "worktree.resolved":
            for (projectID, list) in worktrees {
                list.invalidate(); if list.value != nil { owned { await $0.loadWorktrees(projectID: projectID) } }
            }
        case "installation.update-available": availableUpdate = payload["version"]?.stringValue
        case "installation.updated": availableUpdate = nil
        default: return
        }
    }
    /// The app went to the background. A sign-in keeps its attempt: on iPhone, opening its link leaves the app.
    func suspend() {
        for task in tasks.values { task.cancel() }
        tasks = [:]; connect?.pause()
    }
    func resume() { connect?.resume() }

    // MARK: Plumbing
    /// A load still running for the previous project must not land under the new one.
    private func invalidateLocation() {
        integrations.stop(); plugins.stop(); config.stop()
    }
    private func load<Value: Sendable>(_ cell: Revalidating<Value>, _ fetch: @escaping @MainActor (APIClient) async throws -> Value) async {
        guard let client = store?.client else { return }
        do { _ = try await cell.load { try await fetch(try await client()) } } catch { report(error) }
    }
    /// Runs one action, marks `key` busy meanwhile, and reports a failure in `error`.
    @discardableResult
    func perform(_ key: String, notFoundIsSuccess: Bool = false, _ action: @escaping @MainActor (APIClient) async throws -> Void) async -> Bool {
        guard let client = store?.client, !busy.contains(key) else { return false }
        busy.insert(key); defer { busy.remove(key) }
        do { try await action(try await client()); return true }
        catch APIError.server(_, 404, _) where notFoundIsSuccess { return true }
        catch { report(error); return false }
    }
    private func report(_ error: any Error) {
        guard !WriteErrorMessage.isCancellation(error) else { return }
        self.error = WriteErrorMessage.message(error)
    }
    private func owned(_ work: @escaping @MainActor (ServerAdminModel) async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            await work(self)
            self.tasks.removeValue(forKey: id)
        }
    }
}

extension ReadStore {
    /// A settings model outside any window (previews and snapshots), kept for the life of the server's store.
    public var admin: ServerAdminModel {
        if let admin = adminModel { return admin }
        let admin = makeAdmin(); adminModel = admin; return admin
    }
    /// A new settings model with its own project choice, sign-in, errors and notices.
    public func makeAdmin() -> ServerAdminModel {
        let admin = ServerAdminModel(store: self); register(admin); return admin
    }
}

struct WeakAdminModel { weak var model: ServerAdminModel? }

/// One window's settings models, one per server: two windows on the same server never share a pending sign-in, a
/// project choice, an error or a notice, while sections opened one after another in a window keep them.
@MainActor public final class ServerAdminScope {
    private var models: [String: ServerAdminModel] = [:]
    public init() {}
    public func model(for store: ReadStore) -> ServerAdminModel {
        // A server removed and added again gets a new store; a model of the old one would read nothing.
        if let model = models[store.serverID], model.belongs(to: store) { return model }
        let model = store.makeAdmin(); models[store.serverID] = model; return model
    }
}

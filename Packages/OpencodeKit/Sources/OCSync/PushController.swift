#if os(iOS)
import Foundation
import Observation
import OCActivity
import OCFoundation
import OCIntents
import OCModels
import OCNetworking
import OCPushCore
import OCSecurity
import OCShared
import UIKit
import UserNotifications

@MainActor @Observable public final class PushController {
    public let registration: PushRegistration
    public private(set) var permission = localized("Not requested", comment: "Notification permission status")
    public private(set) var preferences: PushPreferences
    public private(set) var audit: [NotificationAuditEntry] = []
    public private(set) var error: String?
    public var incomingURL: URL?
    #if DEBUG
    @ObservationIgnored var debugDriver: DebugPushDriver?
    #endif
    @ObservationIgnored weak var registry: ServerRegistry?
    @ObservationIgnored private var changeTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var removing: Set<String> = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private lazy var presence = PresenceCoordinator { [weak self] foreground in await self?.sendPresence(foreground) }
    @ObservationIgnored lazy var activities = LiveActivityCoordinator { [weak self] attributes, ref, token, expires in
        guard let self, let server = self.server(attributes.serverID) else { return }
        try await self.registration.registerActivity(token: token, ref: ref, expiresAt: expires,
            server: server.id, sessionID: attributes.sessionID, rpc: self.rpc(server))
    }
    @ObservationIgnored private var actionHandler: NotificationActionHandler?
    var handler: NotificationActionHandler {
        if let actionHandler { return actionHandler }
        let value = NotificationActionHandler(store: registration.store, clock: NetworkClock(), connect: { [weak self] ref in
        guard let self, let server = self.server(ref), let registry = self.registry else { throw CancellationError() }
        let connection = try await registry.directActions(for: server).connect()
        return .init(fetch: { try await connection.request(path: $0) }, reply: { _ = try await connection.request(path: $0, method: .post, body: $1) })
    }, queue: { [weak self] shown, text in
        guard let server = self?.server(shown.server) else { throw CancellationError() }
        return try await server.readPath.queueNotificationReply(shown, text: text)
        })
        actionHandler = value
        return value
    }

    init(registry: ServerRegistry, store: PushSnapshotStore, keys: PushKeyStore, secrets: any SecretStore) {
        self.registry = registry
        let url = Self.relayURL
        let relay = PushRelayClient(url: url)
        registration = PushRegistration(relayURL: url, keys: keys, store: store, secrets: secrets) { method, path, secret, body in
            try await relay.request(method, path: path, secret: secret, body: body)
        }
        preferences = (try? store.preferences()) ?? .init()
        audit = (try? store.audit()) ?? []
    }
    deinit { for task in tasks.values { task.cancel() }; for task in changeTasks.values { task.cancel() } }
    static var relayURL: URL {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["OC_TEST_RELAY_URL"], let url = URL(string: raw),
           ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""), url.scheme == "http" { return url }
        #endif
        return PushContract.shared.relay.defaultURL
    }
    public var health: [PushServerHealth] { registration.health.values.sorted { $0.name < $1.name } }
    public var installCommand: String { "opencode plugin add " + PushContract.shared.names.package }
    func server(_ ref: String) -> ServerStore? { registry?.servers.first { $0.id.rawValue.uuidString == ref } }
    func rpc(_ server: ServerStore) -> PushRegistration.RPC {
        { method, input in
            guard let api = try await server.readPath.client?() else { throw CancellationError() }
            return try await api.send(PushRPC.endpoint(namespace: PushContract.shared.names.rpc, method: method, input: input))
        }
    }
    func own(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in await operation(); self?.tasks.removeValue(forKey: id) }
    }
    public func refresh() async {
        await registration.loadPendingRevocations()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: permission = localized("Not requested", comment: "Notification permission status")
        case .denied: permission = localized("Off in system settings")
        case .authorized: permission = localized("Allowed", comment: "Notification permission status")
        case .provisional: permission = localized("Quiet delivery")
        case .ephemeral: permission = localized("Temporary permission")
        @unknown default: permission = localized("Unknown", comment: "Notification permission status")
        }
        for server in registry?.servers ?? [] {
            await registration.register(server: server.id, name: server.record.name, rpc: rpc(server))
        }
        audit = (try? registration.store.audit()) ?? audit
    }
    public func enable() async {
        do {
            if try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
                #if !targetEnvironment(simulator)
                UIApplication.shared.registerForRemoteNotifications()
                #else
                if !registration.isRelayRegistered { registration.unavailable() }
                #endif
            }
            await refresh()
        } catch { self.error = localized("Could not request notification permission") }
    }
    func reloadAudit() { audit = (try? registration.store.audit()) ?? audit }
    public func setApprovals(_ value: Bool) {
        preferences.lockScreenApprovals = value; savePreferences()
    }
    public func setLiveActivities(_ value: Bool) {
        preferences.liveActivities = value; savePreferences()
        for server in registry?.servers ?? [] { changed(server) }
    }
    public func setNotifications(_ kind: String, enabled: Bool) {
        if enabled { preferences.silencedKinds.remove(kind) } else { preferences.silencedKinds.insert(kind) }
        savePreferences()
    }
    public func isMuted(server: String, sessionID: String) -> Bool {
        preferences.mutedSessions.contains(PushPreferences.muteKey(server: server, session: sessionID))
    }
    public func setMuted(_ muted: Bool, server: String, sessionID: String) {
        let key = PushPreferences.muteKey(server: server, session: sessionID)
        if muted { preferences.mutedSessions.insert(key) } else { preferences.mutedSessions.remove(key) }
        savePreferences()
    }
    public func setQuietHours(_ value: QuietHours?) { preferences.quietHours = value; savePreferences() }
    /// UI tests that do not drive the push harness never start an activity: one left on the simulator outlives the
    /// test, and when the next install ends it iOS launches the app in the background without the test environment.
    private var startsLiveActivities: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["OPENCODE_UI_TEST_ID"] != nil && environment["OC_TEST_PUSH_CONTROL_URL"] == nil { return false }
        #endif
        return preferences.liveActivities
    }
    private func savePreferences() {
        do { try registration.store.save(preferences: preferences); error = nil }
        catch { self.error = localized("Could not save notification settings") }
    }
    public func test(server ref: String) async {
        guard let server = server(ref) else { return }
        do {
            guard let key = try await registration.keys.existingKey(for: server.id) else { error = localized("Register notifications first"); return }
            _ = try await rpc(server)("test", .object(["keyID": .string(key.keyID)]))
            await refresh()
        } catch { self.error = localized("Could not send the test push") }
    }
    func registered(token: Data) async {
        do {
            let environment = Bundle.main.object(forInfoDictionaryKey: "OCAPNSEnvironment") as? String == "production" ? "production" : "sandbox"
            try await registration.registerToken(token.map { String(format: "%02x", $0) }.joined(),
                bundleID: Bundle.main.bundleIdentifier ?? "", environment: environment)
            await refresh()
            await activities.retryRegistrations()
            await presence.setForeground(registry?.phase == .active)
        } catch { self.error = localized("Could not register notifications") }
    }
    func connected(_ server: ServerStore) {
        guard !removing.contains(server.id.rawValue.uuidString) else { return }
        own { [weak self] in
            guard let self else { return }
            await self.registration.register(server: server.id, name: server.record.name, rpc: self.rpc(server))
            await self.sendPresence(self.registry?.phase == .active)
        }
    }
    func phase(_ phase: AppScenePhase) async { await presence.setForeground(phase == .active) }
    /// Never blocks or fails the registry's removal; see `PushRegistration.unregister`.
    func remove(_ server: ServerStore) async {
        let ref = server.id.rawValue.uuidString
        removing.insert(ref)
        changeTasks.removeValue(forKey: ref)?.cancel()
        await registration.unregister(server: server.id, rpc: rpc(server))
        await activities.removeServer(ref)
        if let badge = try? registration.store.badge() { try? await UNUserNotificationCenter.current().setBadgeCount(badge) }
    }
    private func sendPresence(_ foreground: Bool) async {
        for server in registry?.servers ?? [] {
            guard !Task.isCancelled else { return }
            if foreground, case .connected = server.state {} else if foreground { continue }
            guard let key = try? await registration.keys.existingKey(for: server.id) else { continue }
            var input: [String: JSONValue] = ["keyID": .string(key.keyID), "foreground": .bool(foreground)]
            // The most recently opened session; with two open on iPad, the one the user touched last.
            if let session = server.readPath.lru.last(where: { server.readPath.openSessions.contains($0) }) { input["sessionID"] = .string(session) }
            let send = rpc(server), payload = JSONValue.object(input)
            _ = try? await withActionDeadline(seconds: .seconds(3)) { try await send("setPresence", payload) }
            if foreground { changed(server) }
        }
    }
    func changed(_ server: ServerStore) {
        let ref = server.id.rawValue.uuidString
        guard changeTasks[ref] == nil else { return }
        changeTasks[ref] = Task { [weak self, weak server] in
            defer { self?.changeTasks.removeValue(forKey: ref) }
            do { try await Task.sleep(for: .milliseconds(50)); try Task.checkCancellation() } catch { return }
            guard let self, let server, !self.removing.contains(server.id.rawValue.uuidString), self.registry?.servers.contains(where: { $0.id == server.id }) == true else { return }
            do {
                let pending = server.permissions.values.reduce(0) { $0 + $1.count } + server.forms.values.reduce(0) { $0 + $1.count }
                let badge = try self.registration.store.setPending(pending, server: server.id.rawValue.uuidString)
                try await UNUserNotificationCenter.current().setBadgeCount(badge)
            } catch { self.error = localized("Could not update the app badge") }
            for session in server.sessions.values { await self.updateActivity(server, session: session, start: false) }
        }
    }
    func promptSent(_ server: ServerStore, sessionID: String) {
        own { [weak self] in
            guard let self, let session = server.sessions[sessionID] else { return }
            await self.updateActivity(server, session: session, start: true)
        }
    }
    private func updateActivity(_ server: ServerStore, session: SessionModel, start: Bool) async {
        let now = Date().timeIntervalSince1970
        let phase: String
        if start { phase = "running" }
        else if session.attention > 0 && session.status.isRunning { phase = "needsInput" }
        else if case .retrying = session.status { phase = "retrying" }
        else if session.status.isRunning { phase = "running" }
        else { phase = server.readPath.activityProgress.states[session.id]?.phase ?? "running" }
        var state = server.readPath.activityProgress.states[session.id] ?? .init(startedAt: now, updatedAt: now)
        state.phase = phase; state.updatedAt = now
        if start { server.readPath.activityProgress.states[session.id] = state }
        await activities.update(attributes: .init(serverID: server.id.rawValue.uuidString, sessionID: session.id,
            title: session.info.title ?? localized("Session", comment: "Live Activity title when a session has none"), project: URL(fileURLWithPath: session.info.location.directory).lastPathComponent),
            state: state, enabled: startsLiveActivities,
            foreground: registry?.phase == .active, start: start)
    }
}
#endif

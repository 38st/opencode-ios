import Foundation
import Observation
import OCModels
import OCShared

/// The app's windows. It is the only caller of the registry's scene phase, so backgrounding one window never pauses
/// the servers another window shows; it sends each deep link to one window; and it names the key window, the one in
/// use, which alone presents app-wide prompts such as Settings for a server that needs repair.
@MainActor @Observable public final class WindowCoordinator {
    public struct Window: Equatable, Sendable {
        public var path: [SessionRef] = []
        public var phase: AppScenePhase = .inactive
        /// Higher is more recently in use.
        public var activated = 0
    }
    public private(set) var windows: [UUID: Window] = [:]
    /// Links waiting for their window to take them.
    public private(set) var routes: [UUID: DeepLink] = [:]
    @ObservationIgnored private var activators: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private var counter = 0
    @ObservationIgnored private var registrations = 0
    @ObservationIgnored private var applied: AppScenePhase?
    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    /// Set once the registry exists; the current aggregate phase is applied at once.
    @ObservationIgnored public var applyPhase: (@MainActor (AppScenePhase) async -> Void)? { didSet { applyIfNeeded() } }
    public init() {}

    /// Returns true for the first window of this process.
    @discardableResult public func register(_ id: UUID, activate: @escaping @MainActor () -> Void) -> Bool {
        activators[id] = activate
        if windows[id] == nil { counter += 1; windows[id] = Window(activated: counter) }
        registrations += 1
        return registrations == 1
    }
    public func unregister(_ id: UUID) {
        windows.removeValue(forKey: id); activators.removeValue(forKey: id); routes.removeValue(forKey: id)
        applyIfNeeded()
    }
    public func update(_ id: UUID, path: [SessionRef]) {
        guard windows[id] != nil, windows[id]?.path != path else { return }
        windows[id]?.path = path
    }
    /// A window that turns active has come forward, so it is the one in use.
    public func update(_ id: UUID, phase: AppScenePhase) {
        guard let previous = windows[id]?.phase else { return }
        if previous != phase {
            windows[id]?.phase = phase
            if phase == .active { focused(id) }
        }
        applyIfNeeded()
    }
    /// The window took a touch or came forward. iPadOS keeps a key window per scene, so every window stays key in its
    /// own scene and UIKit's key-window changes cannot tell which one is in use.
    public func focused(_ id: UUID) {
        guard windows[id] != nil, current != id else { return }
        activated(id)
    }
    /// Active while any window is; background only when every window is.
    public var phase: AppScenePhase {
        let phases = windows.values.map(\.phase)
        if phases.contains(.active) { return .active }
        if phases.contains(.inactive) { return .inactive }
        return .background
    }
    /// The key window: the one most recently brought forward or touched.
    public var current: UUID? { windows.max { $0.value.activated < $1.value.activated }?.key }
    public func isKey(_ id: UUID) -> Bool { current == id }
    /// The window showing a session, as its root or deeper in its path.
    public func window(showing ref: SessionRef) -> UUID? {
        windows.first { $0.value.path.contains { $0.serverID == ref.serverID && $0.sessionID == ref.sessionID } }?.key
    }
    /// Sends a link to the window already showing its session or that session's root, else to the key window, else
    /// to the window it arrived in. That window comes forward when it is not the key window.
    @discardableResult public func route(_ link: DeepLink, root: SessionRef? = nil, from source: UUID? = nil) -> UUID? {
        let server = ServerID(rawValue: link.serverID)
        let exact = link.sessionID.flatMap { window(showing: SessionRef(serverID: server, sessionID: $0)) }
        let byRoot = root.flatMap { root in windows.first { $0.value.path.first.map { $0.serverID == root.serverID && $0.sessionID == root.sessionID } ?? false }?.key }
        guard let target = exact ?? byRoot ?? current ?? source else { return nil }
        routes[target] = link
        if target != current { bringForward(target) }
        return target
    }
    public func take(_ id: UUID) -> DeepLink? { routes.removeValue(forKey: id) }
    /// Links for a window that is not connected yet, keyed by its scene's persistent identifier; it takes them
    /// when it connects.
    @ObservationIgnored private var parked: [String: DeepLink] = [:]
    public func park(_ link: DeepLink, scene: String) { parked[scene] = link }
    public func takeParked(scene: String) -> DeepLink? { parked.removeValue(forKey: scene) }
    public func bringForward(_ id: UUID) { activators[id]?() }
    /// A line per window, for the UI-test inventory.
    public var diagnostics: String {
        windows.sorted { $0.value.activated < $1.value.activated }.map { id, window in
            "window=\(id.uuidString) key=\(isKey(id)) phase=\(window.phase) path=" + window.path.map(\.sessionID).joined(separator: ",")
        }.joined(separator: "\n")
    }
    private func activated(_ id: UUID) { counter += 1; windows[id]?.activated = counter }
    private func applyIfNeeded() {
        guard let applyPhase, !windows.isEmpty || applied != nil else { return }
        let next = phase
        guard applied != next else { return }
        applied = next
        let previous = phaseTask
        phaseTask = Task { await previous?.value; await applyPhase(next) }
    }
}

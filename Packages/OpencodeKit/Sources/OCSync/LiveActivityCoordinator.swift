import Foundation
import OCActivity
import OCNetworking

/// Pure lifecycle decisions are shared by the platform adapter and host tests.
public struct LiveActivityLifecycle: Sendable {
    public enum Decision: Sendable, Equatable { case start, update, end(Date), restart, none }
    public private(set) var createdAt: Date?
    public private(set) var ended = false
    public init(createdAt: Date? = nil) { self.createdAt = createdAt }
    public mutating func advance(enabled: Bool, foreground: Bool, state: SessionActivityAttributes.ContentState, now: Date) -> Decision {
        guard enabled else { if createdAt != nil && !ended { ended = true; return .end(now) }; return .none }
        guard !ended else { return .none }
        if state.isFinal { guard createdAt != nil else { return .none }; ended = true; return .end(now.addingTimeInterval(900)) }
        guard createdAt != nil else { createdAt = now; return .start }
        if let createdAt, now.timeIntervalSince(createdAt) >= 7.5 * 3600 { self.createdAt = now; return .restart }
        return foreground ? .update : .none
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

// ActivityKit serializes updates in its service. This immutable handle bridges its legacy
// non-Sendable class; no mutable app state crosses the boundary.
private nonisolated struct ActivityHandle: @unchecked Sendable {
    let value: Activity<SessionActivityAttributes>
    func update(_ content: ActivityContent<SessionActivityAttributes.ContentState>) async { await value.update(content) }
    func end(_ content: ActivityContent<SessionActivityAttributes.ContentState>, dismissal: ActivityUIDismissalPolicy) async {
        await value.end(content, dismissalPolicy: dismissal)
    }
}

@MainActor public final class LiveActivityCoordinator {
    public typealias Register = @MainActor @Sendable (SessionActivityAttributes, String, String, Date) async throws -> Void
    private var activities: [String: ActivityHandle] = [:]
    private var tokens: [String: Task<Void, Never>] = [:]
    private var lifecycles: [String: LiveActivityLifecycle] = [:]
    private let register: Register
    public private(set) var error: String?
    /// Activity IDs that received an ActivityKit push token.
    public private(set) var pushTokens: Set<String> = []
    /// Tokens that arrived before the device was registered with the relay; sent once it is.
    private var unregistered: [String: (attributes: SessionActivityAttributes, id: String, token: String)] = [:]
    public init(register: @escaping Register) {
        self.register = register
        for activity in Activity<SessionActivityAttributes>.activities {
            let key = activity.attributes.serverID + ":" + activity.attributes.sessionID
            activities[key] = ActivityHandle(value: activity)
            lifecycles[key] = .init(createdAt: activity.attributes.createdAt)
            observeToken(activity, key: key)
        }
    }
    deinit { for task in tokens.values { task.cancel() } }
    public func update(attributes: SessionActivityAttributes, state: SessionActivityAttributes.ContentState,
                       enabled: Bool, foreground: Bool, start: Bool = false, now: Date = .now) async {
        let key = attributes.serverID + ":" + attributes.sessionID
        guard start || activities[key] != nil else { return }
        var lifecycle = lifecycles[key] ?? .init()
        let decision = lifecycle.advance(enabled: enabled, foreground: foreground, state: state, now: now)
        lifecycles[key] = lifecycle
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(300))
        switch decision {
        case .start, .restart:
            if let existing = activities.removeValue(forKey: key) { await existing.end(content, dismissal: .immediate) }
            tokens.removeValue(forKey: key)?.cancel()
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { lifecycles.removeValue(forKey: key); error = "Live Activities are unavailable"; return }
            do {
                let activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
                activities[key] = ActivityHandle(value: activity); observeToken(activity, key: key); error = nil
            } catch { lifecycles.removeValue(forKey: key); self.error = "Could not start the Live Activity" }
        case .update: await activities[key]?.update(content)
        case .end(let dismissal):
            await activities.removeValue(forKey: key)?.end(content, dismissal: .after(dismissal))
            tokens.removeValue(forKey: key)?.cancel(); unregistered.removeValue(forKey: key)
            lifecycles.removeValue(forKey: key)
        case .none: break
        }
    }
    /// Sends the tokens that arrived before the device was registered with the relay.
    public func retryRegistrations() async {
        for (key, pending) in unregistered where activities[key] != nil {
            let expires = (lifecycles[key]?.createdAt ?? .now).addingTimeInterval(7.5 * 3600)
            do { try await register(pending.attributes, pending.id, pending.token, expires); unregistered.removeValue(forKey: key); error = nil }
            catch { self.error = "Live Activity remote updates unavailable" }
        }
    }
    public func removeServer(_ serverID: String) async {
        for key in activities.keys.filter({ activities[$0]?.value.attributes.serverID == serverID }) {
            tokens.removeValue(forKey: key)?.cancel(); unregistered.removeValue(forKey: key)
            lifecycles.removeValue(forKey: key)
            if let activity = activities.removeValue(forKey: key) {
                var state = activity.value.content.state
                state.phase = "interrupted"; state.updatedAt = Date().timeIntervalSince1970
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissal: .immediate)
            }
        }
    }
    private func observeToken(_ activity: Activity<SessionActivityAttributes>, key: String) {
        tokens[key]?.cancel()
        tokens[key] = Task { [weak self, register] in
            for await bytes in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                self?.pushTokens.insert(activity.id)
                let expires = (self?.lifecycles[key]?.createdAt ?? .now).addingTimeInterval(7.5 * 3600)
                let token = bytes.map { String(format: "%02x", $0) }.joined()
                var delay = 2
                while !Task.isCancelled && Date.now < expires {
                    do {
                        try await register(activity.attributes, activity.id, token, expires)
                        self?.error = nil; self?.unregistered.removeValue(forKey: key)
                        break
                    } catch PushRegistrationError.deviceNotRegistered {
                        // No relay identity yet: nothing to retry until a token registration creates one.
                        self?.unregistered[key] = (activity.attributes, activity.id, token); break
                    } catch {
                        self?.error = "Live Activity remote updates unavailable"
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                        delay = min(60, delay * 2)
                    }
                }
            }
        }
    }
}
#endif

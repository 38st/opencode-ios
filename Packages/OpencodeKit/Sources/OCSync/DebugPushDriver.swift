#if DEBUG && os(iOS)
import Foundation
import ActivityKit
import OCActivity
import OCModels
import OCFoundation
import OCIntents
import OCNetworking
import OCPushCore
import OCShared
import UserNotifications

/// Simulator-only harness transport. It bypasses APNs token issuance, system NSE launch, and
/// (when requested) SpringBoard action gestures. Encryption, Keychain, storage and actions are real.
@MainActor final class DebugPushDriver {
    private let url: URL
    private weak var controller: PushController?
    private var task: Task<Void, Never>?
    private var tokenTask: Task<Void, Never>?
    /// Runs ordinary commands one at a time, in order. The fetch loop never waits for it.
    private var worker: Task<Void, Never>?
    private var queue: AsyncStream<JSONValue>.Continuation?
    /// Cleanup commands run at once, outside the queue, so a hung command cannot hold back a teardown.
    private var cleanups: [UUID: Task<Void, Never>] = [:]
    init?(controller: PushController) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPENCODE_UI_TEST_ID"]?.hasPrefix("ui-") == true,
              let raw = environment["OC_TEST_PUSH_CONTROL_URL"], let url = URL(string: raw),
              url.scheme == "http", ["127.0.0.1", "localhost"].contains(url.host ?? "") else { return nil }
        self.url = url; self.controller = controller
    }
    deinit {
        task?.cancel(); tokenTask?.cancel(); worker?.cancel(); queue?.finish()
        for cleanup in cleanups.values { cleanup.cancel() }
    }
    func stop() {
        task?.cancel(); task = nil; tokenTask?.cancel(); tokenTask = nil
        worker?.cancel(); worker = nil; queue?.finish(); queue = nil
        for cleanup in cleanups.values { cleanup.cancel() }
        cleanups = [:]
    }
    func start() {
        let (commands, queue) = AsyncStream.makeStream(of: JSONValue.self)
        self.queue = queue
        worker = Task { [weak self] in
            for await command in commands {
                guard !Task.isCancelled else { return }
                await self?.execute(command)
            }
        }
        task = Task { [weak self] in
            guard let self else { return }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                try? controller?.registration.store.resetUITestState()
                controller?.setApprovals(true)
                controller?.setLiveActivities(true)
                controller?.reloadAudit()
                for server in Set(Activity<SessionActivityAttributes>.activities.map(\.attributes.serverID)) {
                    await controller?.activities.removeServer(server)
                }
            }
            // Commands are served while the relay registration runs: its outcome is a report the harness
            // waits for (id "token"), never a precondition for answering any other command.
            if let token = ProcessInfo.processInfo.environment["OC_TEST_APNS_TOKEN"], let bytes = Self.hex(token) {
                tokenTask = Task { [weak self] in
                    await self?.controller?.registered(token: bytes)
                    let state = self?.controller?.registration.relayState ?? ""
                    await self?.report(.object(["id": .string("token"), "event": .string("tokenRegistered"),
                        "registered": .bool(self?.controller?.registration.isRelayRegistered == true), "relayState": .string(state),
                        "at": .double(Date().timeIntervalSince1970 * 1000)]))
                }
            }
            while !Task.isCancelled {
                do {
                    var request = URLRequest(url: url.appending(path: "next")); request.timeoutInterval = 2
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if (response as? HTTPURLResponse)?.statusCode == 200 {
                        dispatch(try JSONDecoder().decode(JSONValue.self, from: data))
                    }
                    try await Task.sleep(for: .milliseconds(100))
                } catch { if Task.isCancelled { return }; try? await Task.sleep(for: .milliseconds(250)) }
            }
        }
    }
    private func dispatch(_ command: JSONValue) {
        guard command["operation"]?.stringValue == "activityClear" else { queue?.yield(command); return }
        let id = UUID()
        cleanups[id] = Task { [weak self] in
            await self?.execute(command)
            self?.cleanups[id] = nil
        }
    }
    private func execute(_ command: JSONValue) async {
        guard let controller else { return }
        let id = command["id"]?.stringValue ?? ""
        var output: [String: JSONValue] = ["id": .string(id)]
        switch command["operation"]?.stringValue {
        case "render":
            let envelope = command["payload"]?["oc"] ?? .null
            let presentation = await NotificationContentBuilder.process(envelope: envelope,
                generic: .init(body: command["payload"]?["aps"]?["alert"]?["body"]?.stringValue ?? "Generic alert"),
                store: controller.registration.store, keys: controller.registration.keys)
            let content = UNMutableNotificationContent()
            presentation.apply(to: content)
            if presentation.clearsBadge { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
            content.userInfo["oc"] = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope))
            let delay = max(1, command["delay"]?.doubleValue ?? 2)
            do {
                let identifier = presentation.shownID.map { "push." + $0 } ?? id
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
                try await UNUserNotificationCenter.current().add(.init(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
                output["body"] = .string(presentation.body); output["shownID"] = presentation.shownID.map(JSONValue.string)
                output["category"] = .string(presentation.category); output["receipt"] = presentation.receipt.map(JSONValue.string)
                output["silenced"] = .bool(presentation.silenced); output["interruption"] = presentation.interruption.map { .string($0.rawValue) } ?? .null
            } catch { output["error"] = .string("Local notification failed") }
        case "action":
            let action = NotificationAction.ID(rawValue: command["action"]?.stringValue ?? "") ?? .open
            let result = await controller.handler.handle(shownID: command["shownID"]?.stringValue ?? "", receipt: command["receipt"]?.stringValue, action: action, text: command["text"]?.stringValue)
            output["result"] = .string(result)
            let content = UNMutableNotificationContent(); content.title = "Opencode"; content.body = result; content.categoryIdentifier = "OPEN_ONLY"
            let identifier = "push." + (command["shownID"]?.stringValue ?? id)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            try? await UNUserNotificationCenter.current().add(.init(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
        case "delivered":
            output["nseInvocation"] = (try? controller.registration.store.nseInvocation()).map(JSONValue.double) ?? .null
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            output["notifications"] = .array(delivered.map { .object([
                "id": .string($0.request.identifier), "title": .string($0.request.content.title),
                "body": .string($0.request.content.body), "category": .string($0.request.content.categoryIdentifier),
                "shownID": ($0.request.content.userInfo["shownID"] as? String).map(JSONValue.string) ?? .null,
                "receipt": ($0.request.content.userInfo["shownReceipt"] as? String).map(JSONValue.string) ?? .null]) })
        case "activityStop":
            // The Lock Screen button cannot be tapped by XCUITest. The intent itself runs here, in the app process.
            if let server = command["serverID"]?.stringValue, let session = command["sessionID"]?.stringValue {
                do { _ = try await StopSessionIntent(server: server, session: session).perform(); output["stopped"] = .bool(true) }
                catch { output["error"] = .string("Stop intent failed") }
            }
        case "activityClear":
            // An activity left on the device outlives the test: when the next install ends it, iOS launches the app
            // in the background without the test environment, and XCUITest can adopt that process.
            for server in Set(Activity<SessionActivityAttributes>.activities.map(\.attributes.serverID)) {
                await controller.activities.removeServer(server)
            }
            for activity in Activity<SessionActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            output["remaining"] = .integer(Int64(Activity<SessionActivityAttributes>.activities.filter { $0.activityState != .dismissed }.count))
        case "activityState":
            output["activities"] = .array(Activity<SessionActivityAttributes>.activities.map { .object([
                "id": .string($0.id), "serverID": .string($0.attributes.serverID), "sessionID": .string($0.attributes.sessionID),
                "url": $0.attributes.url.map { .string($0.absoluteString) } ?? .null,
                "phase": .string($0.content.state.phase), "step": .integer(Int64($0.content.state.step)),
                "pushToken": .bool(controller.activities.pushTokens.contains($0.id))]) })
            output["error"] = controller.activities.error.map(JSONValue.string) ?? .null
        case "foregroundState":
            output["badge"] = .integer(Int64((try? controller.registration.store.badge()) ?? -1))
            let pending = controller.registry?.servers.reduce(0) { sum, server in
                sum + server.permissions.values.reduce(0) { $0 + $1.count } + server.forms.values.reduce(0) { $0 + $1.count }
            } ?? 0
            output["pending"] = .integer(Int64(pending))
        case "health":
            await controller.refresh()
            output["registered"] = .bool(controller.health.contains { $0.isRegistered })
            output["server"] = controller.registry?.servers.first.map { .string($0.id.rawValue.uuidString) } ?? .null
        default: output["error"] = .string("Unknown harness operation")
        }
        output["at"] = .double(Date().timeIntervalSince1970 * 1000)
        await report(.object(output))
    }
    private func report(_ json: JSONValue) async {
        var request = URLRequest(url: url.appending(path: "report")); request.httpMethod = "POST"
        request.httpBody = try? JSONEncoder().encode(json); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }
    private static func hex(_ text: String) -> Data? {
        guard text.count == 64 else { return nil }
        var bytes = Data(), cursor = text.startIndex
        while cursor < text.endIndex {
            let end = text.index(cursor, offsetBy: 2)
            guard let byte = UInt8(text[cursor..<end], radix: 16) else { return nil }
            bytes.append(byte); cursor = end
        }
        return bytes
    }
}
#endif

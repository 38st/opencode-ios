import Foundation
import XCTest
import UIKit

nonisolated final class PushSmokeTests: SmokeTestCase {
    @MainActor func testSimulatorPushPath() async throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        for name in ["OC_TEST_RELAY_URL", "OC_TEST_PUSH_CONTROL_URL", "OC_TEST_APNS_TOKEN"] {
            app.launchEnvironment[name] = try XCTUnwrap(env[name])
        }
        try launchFreshApp(suffix: "-push")
        // Runs before the app is terminated, also after a failure: no activity may outlive the test. The app runs
        // this command at once, outside its command queue, so a command still in progress cannot delay it.
        addTeardownBlock { @MainActor [self] in
            try await command(["operation": "activityClear", "id": "activity-clear-teardown"])
            let cleared = try await waitReport("activity-clear-teardown", timeout: 15) { _ in true }
            XCTAssertEqual(cleared["remaining"] as? Int, 0, "The test must not leave a Live Activity on the device")
        }
        app.buttons["addFirstServer"].tap()
        let pair = try await api("/api/pair", method: "POST")
        let link = try XCTUnwrap(env["OPENCODE_UI_URL"]) + "/auth/connect/" + XCTUnwrap(pair["code"] as? String)
        XCTAssertTrue(app.textFields["pairingLink"].waitForExistence(timeout: 5))
        app.textFields["pairingLink"].tap(); app.textFields["pairingLink"].typeText(link)
        connect(explainingLocalNetwork: true); waitForConnections()
        app.buttons["notificationSettings"].tap()
        XCTAssertTrue(app.buttons["enableNotifications"].waitForExistence(timeout: 10))
        let monitor = addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }; return false
        }
        app.buttons["enableNotifications"].tap(); app.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 2) { springboard.alerts.buttons["Allow"].tap() }
        removeUIInterruptionMonitor(monitor)
        // Simulator has no APNs token issuer. The DEBUG driver registers a random mock token and reports the
        // relay's answer; the relay client gives up after 30 s, so this wait is bounded.
        let token = try await waitReport("token", timeout: 45) { _ in true }
        XCTAssertEqual(token["registered"] as? Bool, true, "Relay registration: \(token["relayState"] as? String ?? "none")")
        try await command(["operation": "health", "id": "health"])
        let health = try await waitReport("health") { $0["registered"] as? Bool == true }
        let serverRef = try XCTUnwrap(health["server"] as? String)
        screenshot("push-settings")

        XCUIDevice.shared.press(.home)
        let started = Date()
        let approvedSession = try await trigger("approve")
        let alert = try await waitAlert(kind: "permission", after: 0)
        XCTAssertEqual((alert["payload"] as? [String: Any])?["aps"] as? NSDictionary != nil, true)
        let alertIndex = try XCTUnwrap(alert["index"] as? Int)
        try await waitBridge(index: alertIndex)
        // The untouched simctl alert is inspected before the shared NSE builder is invoked in-app.
        try await Task.sleep(for: .seconds(2))
        showNotifications(springboard)
        screenshot("push-raw-simctl")
        app.activate()
        try await command(["operation": "delivered", "id": "raw-delivered"])
        let raw = try await waitReport("raw-delivered") { _ in true }
        let notifications = raw["notifications"] as? [[String: Any]] ?? []
        XCTAssertFalse(notifications.isEmpty, "simctl must deliver the untouched remote notification")
        let decryptedNSE = notifications.contains { $0["category"] as? String == "PERMISSION" }
        try await control("/report", body: ["event": "simctlNSE", "runsExtension": raw["nseInvocation"] is Double, "decrypted": decryptedNSE])
        let rendered: [String: Any]
        if decryptedNSE {
            rendered = try XCTUnwrap(notifications.first { $0["category"] as? String == "PERMISSION" })
        } else {
            rendered = try await render(alert, id: "approved-visible")
        }
        let shownID = try XCTUnwrap(rendered["shownID"] as? String)
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(3))
        showNotifications(springboard)
        XCTAssertTrue(springboard.staticTexts["Allow edit?"].waitForExistence(timeout: 10), "The decrypted title must be visible")
        screenshot("push-decrypted")
        try await control("/report", body: ["event": "notificationShown", "requestID": shownID, "index": alertIndex, "scenarioToShownMS": Date().timeIntervalSince(started) * 1000])
        springboard.staticTexts["Allow edit?"].firstMatch.press(forDuration: 1)
        let allow = springboard.buttons["Allow once"]
        let nativeAction = allow.waitForExistence(timeout: 3)
        try await control("/report", body: ["event": "notificationActionAutomation", "nativeButtonAvailable": nativeAction])
        if !nativeAction { app.activate() }
        let actionAt = Date()
        if nativeAction {
            allow.tap()
        } else {
            try await command(["operation": "action", "id": "approve-action", "shownID": shownID, "receipt": try XCTUnwrap(rendered["receipt"]), "action": "ALLOW_ONCE"])
            let approved = try await waitReport("approve-action") { _ in true }
            XCTAssertEqual(approved["result"] as? String, "Approved")
        }
        let until = actionAt.addingTimeInterval(5)
        var ran = false
        repeat {
            let response = try await request("/state")
            if (response["sample"] as? String)?.hasPrefix("edited") == true { ran = true; break }
            try await Task.sleep(for: .milliseconds(50))
        } while Date() < until
        XCTAssertTrue(ran)
        try await control("/report", body: ["event": "actionReply", "requestID": shownID, "startedAt": actionAt.timeIntervalSince1970 * 1000, "milliseconds": Date().timeIntervalSince(actionAt) * 1000, "hook": nativeAction ? "none; SpringBoard Allow once" : "notification action UI bypassed; production handler used"])
        XCTAssertLessThan(Date().timeIntervalSince(actionAt), 5)
        app.activate()
        try await waitIdle(approvedSession)

        let changedBefore = try await alertCount()
        XCUIDevice.shared.press(.home)
        let changedSession = try await trigger("changed")
        let changedAlert = try await waitAlert(kind: "permission", after: changedBefore)
        app.activate()
        let changedShown = try await render(changedAlert, id: "changed-visible")
        let changedID = try XCTUnwrap(changedShown["shownID"] as? String)
        try await control("/change", body: ["requestID": changedID])
        try await command(["operation": "action", "id": "changed-action", "shownID": changedID, "receipt": try XCTUnwrap(changedShown["receipt"]), "action": "ALLOW_ONCE"])
        let changedResult = try await waitReport("changed-action") { _ in true }
        XCTAssertEqual(changedResult["result"] as? String, "The request changed. Open the app to review")
        let pending = try await api("/api/session/\(changedSession)/permission/\(changedID)")
        XCTAssertEqual((pending["data"] as? [String: Any])?["id"] as? String, changedID)
        XCUIDevice.shared.press(.home); try await Task.sleep(for: .seconds(3)); showNotifications(springboard)
        XCTAssertTrue(springboard.staticTexts["The request changed. Open the app to review"].waitForExistence(timeout: 10))
        screenshot("push-request-changed")
        _ = try await api("/api/session/\(changedSession)/interrupt", method: "POST")
        try await waitIdle(changedSession)
        app.activate()

        let before = try await alertCount()
        XCUIDevice.shared.press(.home)
        let second = try await trigger("desktop")
        let desktopAlert = try await waitAlert(kind: "permission", after: before)
        app.activate()
        let desktop = try await render(desktopAlert, id: "desktop-visible")
        let requestID = try XCTUnwrap(desktop["shownID"] as? String)
        XCUIDevice.shared.press(.home)
        _ = try await api("/api/session/\(second)/permission/\(requestID)/reply", method: "POST", body: ["decision": "reject"])
        let replacement = try await waitAlert(kind: "resolved", after: before, collapse: try XCTUnwrap(desktopAlert["collapse"] as? String))
        app.activate(); _ = try await render(replacement, id: "replacement-visible")
        XCUIDevice.shared.press(.home); try await Task.sleep(for: .seconds(3)); showNotifications(springboard)
        XCTAssertTrue(springboard.staticTexts["Answered on another device"].firstMatch.waitForExistence(timeout: 10))
        screenshot("push-answered-elsewhere")
        app.activate()
        // The delivered list can lag what SpringBoard shows right after the app comes back, so ask again briefly.
        var matching: [[String: Any]] = []
        for attempt in 0..<10 {
            try await command(["operation": "delivered", "id": "replacement-verify-\(attempt)"])
            let replacements = try await waitReport("replacement-verify-\(attempt)") { _ in true }
            matching = (replacements["notifications"] as? [[String: Any]] ?? []).filter { $0["shownID"] as? String == requestID }
            if !matching.isEmpty { break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?["body"] as? String, "Answered on another device")
        XCTAssertEqual(matching.first?["category"] as? String, "OPEN_ONLY")

        app.activate(); try await Task.sleep(for: .seconds(2))
        try await waitIdle(second)
        let foregroundBefore = try await alertCount()
        let foreground = try await trigger("foreground")
        try await Task.sleep(for: .seconds(6))
        let foregroundAfter = try await alertCount()
        XCTAssertEqual(foregroundAfter, foregroundBefore, "Foreground presence must suppress pushes")
        try await command(["operation": "foregroundState", "id": "foreground-state"])
        let foregroundState = try await waitReport("foreground-state") { _ in true }
        XCTAssertEqual(foregroundState["pending"] as? Int, 1)
        XCTAssertEqual(foregroundState["badge"] as? Int, 1)
        _ = try await api("/api/session/\(foreground)/interrupt", method: "POST")
        screenshot("push-foreground")
        try await waitIdle(foreground)

        // Live Activity, the phone path: a prompt sent from the composer starts it, and the root's end keeps the final state.
        try await control("/scenario", body: ["name": "activity", "plain": true])
        let created = try await api("/api/session", method: "POST", body: ["title": "Push activity", "location": ["directory": try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])], "model": ["providerID": "mock", "id": "mock-1"]])
        let activitySession = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        dismissSettings()
        let route = "opencodeios://server/" + serverRef + "/session/" + activitySession
        app.open(try XCTUnwrap(URL(string: route)))
        let editor = app.textViews["promptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap(); editor.typeText("Start the activity check"); app.buttons["composerSend"].tap()
        let running = try await waitActivity(activitySession) { ["running", "succeeded"].contains($0["phase"] as? String ?? "") }
        XCTAssertEqual(running["url"] as? String, route, "Open must deep-link to the session")
        try await control("/report", body: ["event": "activityStarted", "sessionID": activitySession, "pushToken": running["pushToken"] as? Bool ?? false])
        try await waitIdle(activitySession)
        let finished = try await waitActivity(activitySession) { $0["phase"] as? String == "succeeded" }
        XCTAssertEqual(finished["phase"] as? String, "succeeded", "The final state stays after the run")
        screenshot("push-activity-finished")

        // Stop: the LiveActivityIntent interrupts the session in the app process. Only the Lock Screen tap is bypassed.
        try await control("/scenario", body: ["name": "activity-hold", "hold": true])
        editor.tap(); editor.typeText("Hold for the stop check"); app.buttons["composerSend"].tap()
        let held = try await waitActivity(activitySession) { $0["phase"] as? String == "running" }
        XCTAssertNotEqual(held["id"] as? String, finished["id"] as? String, "A new prompt starts a new activity")
        try await command(["operation": "activityStop", "id": "activity-stop", "serverID": serverRef, "sessionID": activitySession])
        let stopped = try await waitReport("activity-stop") { _ in true }
        XCTAssertEqual(stopped["stopped"] as? Bool, true)
        try await waitIdle(activitySession)
        _ = try await waitActivity(activitySession) { $0["phase"] as? String == "interrupted" && $0["id"] as? String == held["id"] as? String }
        screenshot("push-activity-stopped")

        // Whether simctl can deliver an ActivityKit update is recorded in results.json, not asserted.
        try await control("/activity-probe", body: [:])
        try await Task.sleep(for: .seconds(2))
        try await command(["operation": "activityState", "id": "activity-after-simctl"])
        let probed = try await waitReport("activity-after-simctl") { _ in true }
        XCTAssertFalse((probed["activities"] as? [[String: Any]] ?? []).isEmpty, "The ended activity still exists within its dismissal window")
        try await command(["operation": "activityClear", "id": "activity-clear"])
        let cleared = try await waitReport("activity-clear") { _ in true }
        XCTAssertEqual(cleared["remaining"] as? Int, 0, "The test must not leave a Live Activity on the device")
    }
    @MainActor private func dismissSettings() {
        if !app.buttons["closeSettings"].exists {
            let back = app.navigationBars.buttons.firstMatch
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 5)); app.buttons["closeSettings"].tap()
    }
    @MainActor private func waitActivity(_ session: String, timeout: TimeInterval = 30, _ predicate: ([String: Any]) -> Bool) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        // Each call asks under IDs of its own: waitReport takes the newest report with an ID, which would otherwise be
        // an earlier call's answer until the driver replies.
        let call = UUID().uuidString.prefix(8)
        var attempt = 0
        repeat {
            attempt += 1
            let id = "activity-\(session)-\(call)-\(attempt)"
            try await command(["operation": "activityState", "id": id])
            let report = try await waitReport(id) { _ in true }
            if let found = (report["activities"] as? [[String: Any]] ?? []).first(where: { $0["sessionID"] as? String == session && predicate($0) }) { return found }
            try await Task.sleep(for: .milliseconds(500))
        } while Date() < deadline
        XCTFail("Live Activity for \(session) did not reach the expected state"); throw URLError(.timedOut)
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func trigger(_ name: String) async throws -> String {
        try await control("/scenario", body: ["name": name])
        let directory = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENCODE_UI_DIRECTORY"])
        let result = try await api("/api/session", method: "POST", body: ["title": "Push " + name, "location": ["directory": directory], "model": ["providerID": "mock", "id": "mock-1"]])
        let session = try XCTUnwrap((result["data"] as? [String: Any])?["id"] as? String)
        _ = try await api("/api/session/\(session)/prompt", method: "POST", body: ["text": "Run the push check."])
        return session
    }
    @MainActor private func waitIdle(_ session: String) async throws {
        let deadline = Date().addingTimeInterval(20)
        repeat {
            let active = try await api("/api/session/active")["data"] as? [String: Any] ?? [:]
            if active[session] == nil { return }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("Session did not finish before replacing the mock script"); throw URLError(.timedOut)
    }
    @MainActor private func render(_ alert: [String: Any], id: String) async throws -> [String: Any] {
        try await command(["operation": "render", "id": id, "payload": try XCTUnwrap(alert["payload"]), "delay": 2])
        let result = try await waitReport(id) { _ in true }
        XCTAssertNotEqual(result["category"] as? String, nil)
        return result
    }
    @MainActor private func showNotifications(_ springboard: XCUIApplication) {
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        start.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
    }
    @MainActor private func command(_ body: [String: Any]) async throws { try await control("/command", body: body) }
    @MainActor private func control(_ path: String, body: [String: Any]) async throws { _ = try await request(path, body: body) }
    @MainActor private func request(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let base = try XCTUnwrap(ProcessInfo.processInfo.environment["OC_TEST_PUSH_CONTROL_URL"])
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + path)))
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    @MainActor private func waitBridge(index: Int) async throws {
        let deadline = Date().addingTimeInterval(25)
        repeat {
            let deliveries = try await request("/state")["deliveries"] as? [[String: Any]] ?? []
            if let delivered = deliveries.first(where: { $0["index"] as? Int == index }) {
                XCTAssertNil(delivered["error"])
                XCTAssertNotNil(delivered["forwardedAt"])
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("simctl did not forward the accepted push"); throw URLError(.timedOut)
    }
    @MainActor private func waitReport(_ id: String, timeout: TimeInterval = 20, predicate: ([String: Any]) -> Bool) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let reports = try await request("/state")["reports"] as? [[String: Any]] ?? []
            if let found = reports.last(where: { $0["id"] as? String == id && predicate($0) }) { return found }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("Missing report " + id); throw URLError(.timedOut)
    }
    @MainActor private func alertCount() async throws -> Int { (try await request("/state")["alerts"] as? [Any])?.count ?? 0 }
    @MainActor private func waitAlert(kind: String, after: Int, collapse: String? = nil) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(25)
        repeat {
            let alerts = try await request("/state")["alerts"] as? [[String: Any]] ?? []
            if let found = alerts.dropFirst(after).first(where: { (($0["payload"] as? [String: Any])?["oc"] as? [String: Any])?["kind"] as? String == kind && (collapse == nil || $0["collapse"] as? String == collapse) }) { return found }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("Missing alert " + kind); throw URLError(.timedOut)
    }
}

import Foundation
import XCTest
import UIKit

nonisolated final class ReadSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor func testReadScreens() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        let screensData = Data(try XCTUnwrap(env["OPENCODE_UI_READ_SCREENS"]).utf8)
        let screens = try JSONDecoder().decode([String: String].self, from: screensData)
        let live = try XCTUnwrap(screens["live"]), timeline = try XCTUnwrap(screens["timeline"])
        let agent = try XCTUnwrap(screens["agent"]), unread = try XCTUnwrap(screens["unread"])
        try launchFreshApp(suffix: "-read")
        try await addServer()
        if app.buttons["closeSettings"].exists { app.buttons["closeSettings"].tap() }
        if UIDevice.current.userInterfaceIdiom == .pad { rotate(to: .landscapeLeft) }
        setHome(open: true)
        XCTAssertTrue(app.textFields["sessionSearch"].waitForExistence(timeout: 10))
        let unreadRow = homeSessionRow(unread)
        XCTAssertTrue(unreadRow.exists)
        let sessionList = app.collectionViews["homeSessions"]
        for _ in 0..<10 where !app.buttons["projectPicker"].isHittable { sessionList.swipeDown() }
        screenshot("inbox")
        app.buttons["projectPicker"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-option-")).firstMatch.tap()
        screenshot("session-list")
        app.buttons["projectPicker"].tap(); app.buttons["All projects"].tap()
        for _ in 0..<8 {
            if unreadRow.isHittable && sessionList.frame.insetBy(dx: 0, dy: 8).contains(unreadRow.frame) { break }
            sessionList.swipeUp()
        }
        XCTAssertTrue(sessionList.frame.insetBy(dx: 0, dy: 8).contains(unreadRow.frame))
        // A full swipe commits immediately in the narrow iPad sidebar.
        unreadRow.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: unreadRow.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)))
        XCTAssertTrue(app.buttons["Mark read"].waitForExistence(timeout: 3))
        app.buttons["Mark read"].tap()
        try await Task.sleep(for: .seconds(1))
        let viewed = try await api("/api/session/" + unread)
        let time = ((viewed["data"] as? [String: Any])?["time"] as? [String: Any]) ?? [:]
        XCTAssertGreaterThanOrEqual((time["viewed"] as? Double) ?? 0, (time["idle"] as? Double) ?? 1)

        let formatted = "# Stream summary\n\nA **formatted** paragraph with `inline code` and [a link](https://example.com).\n\n- **Read** the files\n- Checked `main.swift`\n\n> A quoted result.\n\n| File | Status |\n| --- | --- |\n| main.swift | Checked |\n\n```swift\nlet complete = true\n```\n\nSTREAM FINISHED"
        let deltas: [[String: Any]] = (1...45).map { ["text": "Live update \($0). The transcript is receiving text from the sandbox.\n\n", "delayMs": 250] } + [["text": formatted, "delayMs": 250]]
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "read-ui-stream", "script": ["calls": [["deltas": deltas]]]], mock: true)
        _ = try await api("/api/session/\(live)/prompt", method: "POST", body: ["text": "Stream a long response for the UI smoke test."])
        homeSessionRow(live).tap()
        chooseDetail("Compact")
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Live update")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15))
        try await Task.sleep(for: .seconds(3))
        let scroll = app.descendants(matching: .any).matching(identifier: "transcriptScroll").firstMatch
        scroll.swipeDown(); scroll.swipeDown()
        XCTAssertTrue(app.buttons["jumpToLatest"].waitForExistence(timeout: 5))
        app.buttons["jumpToLatest"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "STREAM FINISHED")).firstMatch.waitForExistence(timeout: 25))
        screenshot("transcript-live")
        let header = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessionHeader-")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let serverID = String(header.identifier.dropFirst("sessionHeader-".count))
        XCTAssertNotNil(UUID(uuidString: serverID))
        let prefix = "opencodeios://server/" + serverID
        app.open(try XCTUnwrap(URL(string: prefix + "/session/" + live)))
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        app.open(try XCTUnwrap(URL(string: prefix + "/session/" + timeline)))
        XCTAssertTrue(app.staticTexts["Design system"].waitForExistence(timeout: 10))
        let exploration = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Used 3 Read, Glob, Grep")).firstMatch
        for _ in 0..<8 {
            if exploration.isHittable { break }
            scroll.swipeDown()
        }
        XCTAssertTrue(exploration.isHittable)
        exploration.tap()
        XCTAssertEqual(exploration.value as? String, "Expanded")
        let glob = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Glob")).firstMatch
        let grep = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Grep")).firstMatch
        for _ in 0..<6 {
            if glob.isHittable && grep.isHittable { break }
            let upward = !glob.exists || glob.frame.minY >= scroll.frame.minY
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.7 : 0.3))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        screenshot("transcript-tools")
        XCTAssertTrue(glob.isHittable)
        XCTAssertTrue(grep.isHittable)
        chooseDetail("Everything")
        app.open(try XCTUnwrap(URL(string: prefix + "/session/" + agent)))
        XCTAssertTrue(app.buttons["openSubagent"].waitForExistence(timeout: 10))
        app.buttons["openSubagent"].tap()
        XCTAssertTrue(app.staticTexts["Subagent · read only"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture child result")).firstMatch.waitForExistence(timeout: 10))
        screenshot("subagent")
        if UIDevice.current.userInterfaceIdiom == .pad {
            screenshot("ipad-split")
            rotate(to: .portrait)
            screenshot("ipad-portrait")
        }
    }
    @MainActor private func chooseDetail(_ title: String) {
        app.buttons["timelineDetail"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", title, "timelineDetail")).firstMatch.tap()
    }
    @MainActor private func addServer() async throws {
        app.buttons["addFirstServer"].tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            let pair = try await api("/api/pair", method: "POST")
            let link = try XCTUnwrap(env["OPENCODE_UI_URL"]) + "/auth/connect/" + XCTUnwrap(pair["code"] as? String)
            XCTAssertTrue(app.textFields["pairingLink"].waitForExistence(timeout: 5))
            app.textFields["pairingLink"].tap()
            app.textFields["pairingLink"].typeText(link)
        } else {
            XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5))
            app.buttons["Use password"].tap()
            XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
            app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Read sandbox")
            app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
            app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        }
        connect(explainingLocalNetwork: true)
        waitForConnections()
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

extension ReadSmokeTests {
    @MainActor func testApprovals() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        try launchFreshApp(suffix: "-approvals")
        try await addServer()
        if app.buttons["closeSettings"].exists { app.buttons["closeSettings"].tap() }
        if UIDevice.current.userInterfaceIdiom == .pad { rotate(to: .landscapeLeft) }
        setHome(open: true)
        let directory = try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])
        var createdSessions: [String] = []
        for flow in ["once", "question", "reject"] {
            let calls: [[String: Any]] = flow == "question" ? [
                ["tools": [["name": "question", "arguments": ["questions": [["header": "Color", "question": "Which color?", "options": [["label": "Blue", "description": "Use blue"], ["label": "Green", "description": "Use green"]]]]]]]],
                ["deltas": [["text": "Question flow completed."]]],
            ] : [
                ["tools": [["name": "shell", "arguments": ["command": "printf 'approval-smoke\\n'"]]]],
                ["deltas": [["text": "Permission flow completed."]]],
            ]
            _ = try await api("/admin/scenario", method: "POST", body: ["name": "approval-ui-" + flow, "script": ["calls": calls]], mock: true)
            let created = try await api("/api/session", method: "POST", body: ["title": "Approval UI " + flow,
                "location": ["directory": directory], "model": ["providerID": "mock", "id": "mock-1"],
                "permissions": [["action": "shell", "resource": "*", "effect": "ask"]]])
            let id = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
            createdSessions.append(id)
            _ = try await api("/api/session/\(id)/prompt", method: "POST", body: ["text": "Run the UI approval flow."])
            if flow == "once" {
                let row = homeSessionRow(id)
                XCTAssertTrue(row.isHittable); row.tap()
            } else {
                let header = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessionHeader-")).firstMatch
                let serverID = String(header.identifier.dropFirst("sessionHeader-".count))
                app.open(try XCTUnwrap(URL(string: "opencodeios://server/" + serverID + "/session/" + id)))
            }
            let dock = app.descendants(matching: .any).matching(identifier: "approvalDock").firstMatch
            XCTAssertTrue(dock.waitForExistence(timeout: 15))
            if flow == "once" {
                let allow = dock.buttons["dockAllowOnce"].firstMatch
                XCTAssertTrue(allow.waitForExistence(timeout: 10))
                screenshot("permission-dock")
                allow.tap()
                let timing = app.descendants(matching: .any).matching(identifier: "approvalTiming").firstMatch
                XCTAssertTrue(timing.waitForExistence(timeout: 10))
                let elapsed = try XCTUnwrap(Double(try XCTUnwrap(timing.value as? String)))
                XCTAssertLessThan(elapsed, 1, "Allow once must reach the running shell within one second")
                let attachment = XCTAttachment(string: "{\"allow_once_to_shell_running_seconds\":\(elapsed)}")
                attachment.name = "approval-latency"; attachment.lifetime = .keepAlways; add(attachment)
                print("APPROVAL_ROUND_TRIP_SECONDS=\(elapsed)")
            } else if flow == "question" {
                dock.buttons["answerQuestion"].firstMatch.tap()
                XCTAssertTrue(app.buttons["formOption-q0-Blue"].waitForExistence(timeout: 10))
                screenshot("question-sheet")
                app.buttons["formOption-q0-Blue"].tap()
                app.buttons["reviewAnswers"].tap()
                screenshot("question-review")
                app.buttons["submitAnswers"].tap()
                let timing = app.descendants(matching: .any).matching(identifier: "answerTiming").firstMatch
                XCTAssertTrue(timing.waitForExistence(timeout: 10))
                let elapsed = try XCTUnwrap(Double(try XCTUnwrap(timing.value as? String)))
                XCTAssertLessThan(elapsed, 1)
                let measurement = XCTAttachment(string: "{\"answer_to_form_replied_seconds\":\(elapsed)}")
                measurement.name = "answer-latency"; measurement.lifetime = .keepAlways; add(measurement)
                print("ANSWER_ROUND_TRIP_SECONDS=\(elapsed)")
            } else {
                dock.buttons["reviewPermission"].firstMatch.tap()
                XCTAssertTrue(app.buttons["rejectPermission"].waitForExistence(timeout: 10))
                screenshot("permission-sheet")
                app.buttons["rejectPermission"].tap()
                let field = app.textFields["permissionNote"].exists ? app.textFields["permissionNote"] : app.textViews["permissionNote"]
                XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Use a read-only inspection instead.")
                screenshot("permission-reject")
                app.buttons["confirmReject"].tap()
            }
            _ = try await api("/api/experimental/session/\(id)/wait", method: "POST")
            let permissions = try await api("/api/session/\(id)/permission")
            let forms = try await api("/api/session/\(id)/form")
            XCTAssertEqual((permissions["data"] as? [Any])?.count, 0)
            XCTAssertEqual((forms["data"] as? [Any])?.count, 0)
            let messages = try await api("/api/session/\(id)/message?order=asc&limit=200")
            let tools = (messages["data"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "tool" }
            XCTAssertTrue(tools.contains { ($0["state"] as? [String: Any])?["status"] as? String == (flow == "reject" ? "error" : "completed") })
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", flow == "question" ? "Question flow completed." : "Permission flow completed.")).firstMatch.waitForExistence(timeout: 10))
        }
        for id in createdSessions { _ = try await api("/api/session/" + id, method: "DELETE") }
    }
}

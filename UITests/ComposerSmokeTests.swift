import Foundation
import XCTest
import UIKit

nonisolated final class ComposerSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var editor: XCUIElement { app.textViews["promptEditor"] }
    @MainActor private func setup(_ suffix: String) async throws -> (String, String) {
        try launchFreshApp(suffix: suffix)
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Composer sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_PROXY_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()
        app.buttons["closeSettings"].tap()
        if UIDevice.current.userInterfaceIdiom == .pad { rotate(to: .landscapeLeft) }
        let created = try await api("/api/session", method: "POST", body: ["title": "Composer smoke", "location": ["directory": try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])], "model": ["providerID": "mock", "id": "mock-1"]])
        let id = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        setHome(open: true)
        let row = homeSessionRow(id)
        XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let header = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessionHeader-")).firstMatch
        let serverID = String(header.identifier.dropFirst("sessionHeader-".count))
        return (id, serverID)
    }
    @MainActor private func open(_ id: String, server: String) throws {
        app.open(try XCTUnwrap(URL(string: "opencodeios://server/" + server + "/session/" + id)))
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
    }
    @MainActor private func type(_ text: String) { editor.tap(); editor.typeText(text) }
    @MainActor private func clear() {
        editor.tap(); editor.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap(); editor.typeText(XCUIKeyboardKey.delete.rawValue) }
        else {
            let count = (editor.value as? String ?? "").count
            editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
    }
    @MainActor private func attachImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24))
        UIPasteboard.general.image = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24)) }
        app.buttons["composerAdd"].tap()
        let paste = app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 3)); paste.tap()
        let allow = app.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 1) { allow.tap() }
        XCTAssertTrue(app.buttons["Remove attachment"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor private func chooseVision() {
        app.buttons["composerModel"].tap()
        XCTAssertTrue(app.switches["Show all models"].waitForExistence(timeout: 5))
        app.switches["Show all models"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let model = app.buttons["model-mock:mock-vision"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5)); model.tap()
    }
    @MainActor private func fault(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: try XCTUnwrap(env["OPENCODE_UI_PROXY_URL"]) + "/__fault")))
        request.httpMethod = "POST"; request.setValue(try XCTUnwrap(env["OPENCODE_UI_PROXY_TOKEN"]), forHTTPHeaderField: "x-fault-token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    @MainActor private func messages(_ id: String) async throws -> [[String: Any]] { (try await api("/api/session/\(id)/message?limit=200&order=asc"))["data"] as? [[String: Any]] ?? [] }
    @MainActor private func exactlyOnce(_ text: String, session: String) async throws {
        _ = try await api("/api/experimental/session/\(session)/wait", method: "POST")
        let users = try await messages(session).filter { $0["type"] as? String == "user" && $0["text"] as? String == text }
        XCTAssertEqual(users.count, 1)
        let inbox = try await api("/api/session/\(session)/inbox")
        XCTAssertEqual((inbox["data"] as? [[String: Any]] ?? []).filter { ($0["payload"] as? [String: Any])?["text"] as? String == text }.count, 0)
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 15))
        if let id = users.first?["id"] as? String {
            XCTAssertEqual(app.otherElements.matching(identifier: "timeline-userPrompt-" + id).count, 1)
        }
    }
    @MainActor func testComposerDurabilityAndSends() async throws {
        continueAfterFailure = false; executionTimeAllowance = 300
        let (backgroundSessionID, serverID) = try await setup("-composer")
        var id = backgroundSessionID
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "plain-text"], mock: true)
        for background in [true, false] {
            if !background {
                let created = try await api("/api/session", method: "POST", body: ["title": "Debounced draft", "location": ["directory": try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])], "model": ["providerID": "mock", "id": "mock-1"]])
                id = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
                try open(id, server: serverID)
            }
            let draftText = background ? "Draft background 😀" : "Draft debounce 😀"
            type(draftText + " @sam")
            let suggestion = app.buttons["suggestion-file:sample.txt"]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
            attachImage(); chooseVision()
            if background { XCUIDevice.shared.press(.home) }
            else { try await Task.sleep(for: .milliseconds(500)) }
            app.terminate(); app.launch(); try open(id, server: serverID)
            XCTAssertTrue((editor.value as? String ?? "").contains(draftText + " @sample.txt"))
            XCTAssertTrue(app.buttons["Remove attachment"].firstMatch.exists)
            XCTAssertTrue((app.buttons["composerModel"].value as? String ?? "").contains("Mock Vision"))
            app.buttons["composerSend"].tap()
            try await Task.sleep(for: .seconds(1))
            _ = try await api("/api/experimental/session/\(id)/wait", method: "POST")
            let sentMessages = try await messages(id)
            let prompt = try XCTUnwrap(sentMessages.first { ($0["text"] as? String)?.contains(draftText) == true })
            let files = try XCTUnwrap(prompt["files"] as? [[String: Any]])
            XCTAssertEqual(files.count, 2)
            XCTAssertTrue(files.contains { $0["mention"] != nil })
            XCTAssertTrue(files.contains { ($0["mime"] as? String)?.hasPrefix("image/") == true })
            let info = try await api("/api/session/\(id)")["data"] as? [String: Any] ?? [:]
            XCTAssertEqual((info["model"] as? [String: Any])?["id"] as? String, "mock-vision")
            let evidence = XCTAttachment(string: "Fresh draft restored text, mention token, image attachment and Mock Vision after \(background ? "background and kill" : "500 ms debounce and kill without backgrounding"); server received the mention, image and selected model.")
            evidence.name = "composer-draft-" + (background ? "background" : "debounce")
            evidence.lifetime = .keepAlways; add(evidence)
        }
        screenshot("composer-sent")

        // Three separate faults use the real Send control and SQLite-backed relaunch.
        for mode in ["offline", "lost-response", "immediate-kill"] {
            _ = try await api("/admin/scenario", method: "POST", body: ["name": "plain-text"], mock: true)
            let text = "Durability \(mode)"
            _ = try await fault(["reset": true, "blocked": mode == "offline", "dropPrompts": mode == "lost-response" ? 1 : 0, "pauseEvents": mode == "lost-response"])
            type(text); app.buttons["composerSend"].tap()
            if mode == "lost-response" { try await Task.sleep(for: .seconds(3)) }
            app.terminate()
            let trace = try await fault(["blocked": false, "pauseEvents": false])
            app.launch(); try open(id, server: serverID)
            try await Task.sleep(for: .seconds(2))
            try await exactlyOnce(text, session: id)
            if mode == "lost-response" {
                let admissions = trace["admissions"] as? [[String: Any]] ?? []
                XCTAssertGreaterThanOrEqual(admissions.count, 2)
                XCTAssertEqual(Set(admissions.compactMap { $0["id"] as? String }).count, 1)
                XCTAssertEqual(Set(admissions.compactMap { $0["sha256"] as? String }).count, 1)
            }
            let evidence = XCTAttachment(string: "\(mode): exactly one server message, empty inbox, one transcript prompt; \(trace)")
            evidence.name = "composer-durability-" + mode; evidence.lifetime = .keepAlways; add(evidence)
        }
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "plain-text"], mock: true)
        type("/check fixture"); app.buttons["composerSend"].tap()
        try await Task.sleep(for: .seconds(1))
        _ = try await api("/api/experimental/session/\(id)/wait", method: "POST")
        let commandMessages = try await messages(id)
        XCTAssertTrue(commandMessages.contains { ($0["text"] as? String)?.contains("Check this input: fixture") == true })
        type("!"); type("printf 'composer-shell'"); app.buttons["composerSend"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "composer-shell")).firstMatch.waitForExistence(timeout: 10))
        type("/model"); XCTAssertTrue(app.buttons["suggestion-client:model"].waitForExistence(timeout: 5)); app.buttons["suggestion-client:model"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        _ = try await api("/api/session/\(id)", method: "DELETE")
        _ = try await api("/api/session/\(backgroundSessionID)", method: "DELETE")
    }
    @MainActor private func sessionAction(_ title: String) {
        app.buttons["sessionActions"].tap()
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
    }
    @MainActor private func openFixtureProject() throws {
        app.buttons["newSessionProject"].tap(); app.buttons["Open project…"].tap()
        let directory = app.textFields["Absolute directory path"]
        XCTAssertTrue(directory.waitForExistence(timeout: 5))
        app.buttons["Parent directory"].tap()
        let browser = app.collectionViews["directoryBrowser"]
        let fixtureFolder = browser.buttons["composer-worktree-project"]
        for _ in 0..<4 where !fixtureFolder.exists || !fixtureFolder.isHittable { browser.swipeUp() }
        XCTAssertTrue(fixtureFolder.waitForExistence(timeout: 5)); fixtureFolder.tap()
        XCTAssertEqual(directory.value as? String, try XCTUnwrap(env["OPENCODE_UI_WORKTREE_DIRECTORY"]))
        app.buttons["Open"].tap()
    }
    @MainActor private func settle(_ id: String) async throws {
        _ = try await api("/api/experimental/session/\(id)/wait", method: "POST")
        try await Task.sleep(for: .milliseconds(300))
    }
    @MainActor private func expectPending(_ id: String, text: String, delivery: String?) async throws {
        for _ in 0..<50 {
            let response = try await api("/api/session/\(id)/inbox")
            let items = (response["data"] as? [[String: Any]] ?? []).filter { ($0["payload"] as? [String: Any])?["text"] as? String == text }
            if let delivery {
                if items.count == 1 && items.first?["delivery"] as? String == delivery { return }
            } else if items.isEmpty { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The server did not acknowledge the pending-input action")
    }
    @MainActor func testComposerQueueAndSessionActions() async throws {
        continueAfterFailure = false; executionTimeAllowance = 300
        let (id, serverID) = try await setup("-composer-actions")
        _ = try await api("/admin/scenario", method: "POST", body: ["script": ["calls": [
            ["deltas": [["text": "Starting composer run."]], "waitForAbort": true],
            ["deltas": [["text": "Steering received."]]], ["deltas": [["text": "Next reply."]]], ["deltas": [["text": "Another reply."]]],
            ["deltas": [["text": "Workspace session reply."]]], ["deltas": [["text": "Final fixture reply."]]]
        ]]], mock: true)
        type("Start queue scenario"); app.buttons["composerSend"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        type("Queued with attachment"); attachImage()
        XCTAssertTrue(app.buttons["alternateDelivery"].waitForExistence(timeout: 5)); app.buttons["alternateDelivery"].tap()
        XCTAssertTrue(app.buttons["Undo"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("Queued with attachment"))
        XCTAssertTrue(app.buttons["Remove attachment"].firstMatch.exists)
        try await expectPending(id, text: "Queued with attachment", delivery: nil)
        app.buttons["alternateDelivery"].tap()
        screenshot(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-composer-queue" : "composer-queue")
        XCTAssertTrue(app.buttons["Steer"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Steer"].firstMatch.tap()
        try await expectPending(id, text: "Queued with attachment", delivery: "steer")
        app.terminate(); app.launch(); try open(id, server: serverID)
        XCTAssertTrue(app.buttons["Move to queue"].waitForExistence(timeout: 10)); app.buttons["Move to queue"].tap()
        try await expectPending(id, text: "Queued with attachment", delivery: "queue")
        app.buttons["composerSend"].tap(); try await settle(id)
        XCTAssertTrue(app.buttons["Send"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Send"].firstMatch.tap()
        try await settle(id)
        chooseVision()
        app.buttons["composerVariant"].tap(); app.buttons["careful"].firstMatch.tap()
        app.buttons["composerAgent"].tap(); app.buttons["reviewer"].firstMatch.tap()
        type("Apply the selected model and agent"); app.buttons["composerSend"].tap(); try await settle(id)
        let changed = try await api("/api/session/\(id)")
        let info = try XCTUnwrap(changed["data"] as? [String: Any])
        XCTAssertEqual(info["agent"] as? String, "reviewer")
        XCTAssertEqual((info["model"] as? [String: Any])?["id"] as? String, "mock-vision")
        XCTAssertEqual((info["model"] as? [String: Any])?["variant"] as? String, "careful")
        // The header names the server's selection by its catalog display name, as the composer does. While the
        // keyboard is up the session uses compact chrome: the header is hidden and the same metadata is in the
        // Session information menu. The chrome can switch while the keyboard animates, so retry either view.
        let header = app.otherElements["sessionHeader-" + serverID]
        var shown = false
        for _ in 0..<5 where !shown {
            if header.staticTexts["Mock Vision"].waitForExistence(timeout: 1) { shown = true; break }
            let information = app.buttons["sessionInformation"]
            guard information.exists, information.isHittable else { continue }
            information.tap()
            let model = app.descendants(matching: .any)["Model: Mock Vision"].firstMatch
            shown = model.waitForExistence(timeout: 2)
            // An outside tap only dismisses an open menu; it never reaches the view behind it. The status bar does not
            // count as outside, so tap the empty trailing end of the session's navigation bar.
            if model.exists {
                app.navigationBars["Composer smoke"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                XCTAssertTrue(model.waitForNonExistence(timeout: 5))
            }
        }
        XCTAssertTrue(shown, "The session header or Session information menu must name the selected model")
        sessionAction("Rename")
        let title = app.alerts.textFields.firstMatch; title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (title.value as? String ?? "").count) + "Renamed composer")
        app.alerts.buttons["Save"].tap()
        type("Keep this unsent draft"); attachImage()
        sessionAction("Undo last message")
        XCTAssertTrue(app.staticTexts["Replace your draft?"].waitForExistence(timeout: 5))
        screenshot("composer-replace-draft")
        app.buttons["Cancel"].tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("Keep this unsent draft"))
        XCTAssertTrue(app.buttons["Remove attachment"].firstMatch.exists)
        let cancelledUndo = try await api("/api/session/\(id)")
        XCTAssertNil((cancelledUndo["data"] as? [String: Any])?["revert"] as? [String: Any])
        sessionAction("Undo last message")
        XCTAssertTrue(app.staticTexts["Replace your draft?"].waitForExistence(timeout: 5))
        app.buttons["Replace"].tap()
        XCTAssertTrue(app.buttons["Redo"].waitForExistence(timeout: 10))
        let recovered = editor.value as? String
        sessionAction("Redo last message")
        XCTAssertEqual(editor.value as? String, recovered)
        sessionAction("Undo last message")
        XCTAssertTrue(app.buttons["Redo"].waitForExistence(timeout: 10))
        app.buttons["composerSend"].tap()
        XCTAssertTrue(app.staticTexts["Discard reverted messages?"].waitForExistence(timeout: 5))
        screenshot("composer-revert-confirmation")
        app.buttons["Discard and send"].tap(); try await settle(id)
        sessionAction("Compact session"); try await settle(id)
        sessionAction("Fork from message")
        XCTAssertTrue(app.navigationBars["Fork from message"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Apply the selected model")).firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue((editor.value as? String ?? "").contains("Apply the selected model"))
        XCTAssertFalse(app.buttons["Back to parent"].exists)
        sessionAction("Delete session")
        XCTAssertTrue(app.staticTexts["Delete session"].waitForExistence(timeout: 5)); screenshot("composer-delete")
        app.buttons["Delete session"].tap()
        setHome(open: true)
        XCTAssertTrue(app.buttons["newSession"].waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .pad { app.typeKey("n", modifierFlags: .command) }
        else { app.buttons["newSession"].tap() }
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        try openFixtureProject()
        let populatedModel = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value CONTAINS %@", "composerModel", "Mock"))
        XCTAssertTrue(populatedModel.firstMatch.waitForExistence(timeout: 10))
        // The current project's relative "./" entry sorts below the parent entries on the shorter iPad sheet.
        try openFixtureProject()
        XCTAssertFalse(app.staticTexts["Could not load project choices."].exists)
        screenshot(UIDevice.current.userInterfaceIdiom == .pad ? "ipad-composer-new" : "composer-new")
        let previousSessions = try await api("/api/session")["data"] as? [[String: Any]] ?? []
        let previousIDs = Set(previousSessions.compactMap { $0["id"] as? String })
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "plain-text"], mock: true)
        type("New session from workspace"); app.buttons["composerSend"].tap()
        XCTAssertTrue(app.buttons["sessionActions"].waitForExistence(timeout: 10))
        var admittedSession: String?
        for _ in 0..<50 {
            let sessions = try await api("/api/session")["data"] as? [[String: Any]] ?? []
            admittedSession = sessions.compactMap { $0["id"] as? String }.first { !previousIDs.contains($0) }
            if admittedSession != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let createdID = try XCTUnwrap(admittedSession)
        try await exactlyOnce("New session from workspace", session: createdID)
        if UIDevice.current.userInterfaceIdiom == .pad {
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(app.staticTexts["New session"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["sessionActions"].exists)
        }
        _ = try await api("/api/session/\(id)", method: "DELETE")
    }
    @MainActor func testInterruptAndNewWorktree() async throws {
        continueAfterFailure = false; executionTimeAllowance = 180
        let (id, _) = try await setup("-composer-worktree")
        _ = try await api("/admin/scenario", method: "POST", body: ["script": ["calls": [
            ["deltas": [["text": "Starting interrupt test."]], "waitForAbort": true],
            ["deltas": [["text": "Interrupted and resumed."]]], ["deltas": [["text": "Worktree created."]]]
        ]]], mock: true)
        type("Start interrupt scenario"); app.buttons["composerSend"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        type("Interrupting follow-up"); app.buttons["composerSend"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Interrupt and send"].waitForExistence(timeout: 3)); screenshot("composer-send-menu")
        app.buttons["Interrupt and send"].tap()
        let admitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", ""), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [admitted], timeout: 5), .completed)
        try await settle(id)
        let prompts = try await messages(id).filter { $0["type"] as? String == "user" }
        XCTAssertEqual(prompts.count, 2)
        XCTAssertEqual(prompts.last?["text"] as? String, "Interrupting follow-up")
        sessionAction("Delete session"); XCTAssertTrue(app.staticTexts["Delete session"].waitForExistence(timeout: 5)); app.buttons["Delete session"].tap()
        setHome(open: true)
        XCTAssertTrue(app.buttons["newSession"].waitForExistence(timeout: 10)); app.buttons["newSession"].tap()
        type("New worktree from composer"); attachImage(); chooseVision()
        try openFixtureProject()
        XCTAssertTrue((editor.value as? String ?? "").contains("New worktree from composer"))
        XCTAssertTrue(app.buttons["Remove attachment"].firstMatch.exists)
        XCTAssertTrue((app.buttons["composerModel"].value as? String ?? "").contains("Mock Vision"))
        XCTAssertTrue(app.buttons["newSessionWorktree"].waitForExistence(timeout: 10)); app.buttons["newSessionWorktree"].tap()
        app.buttons["New worktree"].firstMatch.tap()
        let before = try await api("/api/session?limit=100")
        let oldIDs = Set((before["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        app.buttons["composerSend"].tap()
        XCTAssertTrue(app.buttons["sessionActions"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        var created: [String: Any]?
        for _ in 0..<50 {
            let sessions = try await api("/api/session?limit=100")
            created = (sessions["data"] as? [[String: Any]] ?? []).first { ($0["id"] as? String).map { !oldIDs.contains($0) } == true }
            if created != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let createdID = try XCTUnwrap(created?["id"] as? String)
        XCTAssertNotEqual((created?["location"] as? [String: Any])?["directory"] as? String, env["OPENCODE_UI_DIRECTORY"])
        try await exactlyOnce("New worktree from composer", session: createdID)
        screenshot("composer-worktree")
        _ = try await api("/api/session/\(createdID)", method: "DELETE")
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

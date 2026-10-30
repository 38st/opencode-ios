import Foundation
import XCTest
import UIKit

/// Session features against the sandbox: statistics, Mermaid and LaTeX in a reply, prompt recall, a side question,
/// the export share sheet and moving the session into a new worktree of its Git project.
nonisolated final class SessionSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var editor: XCUIElement { app.textViews["promptEditor"] }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private static let reply = """
    Here is the flow:

    ```mermaid
    flowchart TD
      A[Prompt] --> B{Approved?}
      B -->|yes| C[Run]
    ```

    The cost is

    $$\\frac{n^2}{2}$$
    """

    @MainActor func testSessionFeatures() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        try launchFreshApp(suffix: "-session")
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Session sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()

        // Statistics: the sandbox's seeded sessions over the last 7 days.
        app.buttons["serverRow"].firstMatch.tap()
        let usage = app.buttons["serverSettings-usage"]
        XCTAssertTrue(usage.waitForExistence(timeout: 10))
        for _ in 0..<8 where !usage.isHittable { app.swipeUp() }
        usage.tap()
        let prompts = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Prompts")).firstMatch
        XCTAssertTrue(prompts.waitForExistence(timeout: 20), "Statistics show the prompts sent")
        XCTAssertFalse(element("statsEmpty").exists, "The sandbox has activity in the last 7 days")
        screenshot("session-stats")
        for _ in 0..<2 where !app.buttons["closeSettings"].exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 5)); app.buttons["closeSettings"].tap()

        // A reply with a diagram and a formula, then a side answer.
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "session-features", "script": ["calls": [
            ["deltas": [["text": Self.reply]]], ["deltas": [["text": "Side answer."]]],
        ]]], mock: true)
        let directory = try XCTUnwrap(env["OPENCODE_UI_WORKTREE_DIRECTORY"])
        let created = try await api("/api/session", method: "POST", body: ["title": "Session features", "location": ["directory": directory], "model": ["providerID": "mock", "id": "mock-1"]])
        let id = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        _ = try await api("/api/session/\(id)/prompt", method: "POST", body: ["text": "Draw the approval flow"])
        _ = try await api("/api/experimental/session/\(id)/wait", method: "POST")
        setHome(open: true)
        let row = homeSessionRow(id)
        XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        // Timeline rows name their content for automation, so the drawings are found by their spoken summaries.
        let labelled = { [app] (prefix: String) in app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch }
        XCTAssertTrue(labelled("Flowchart: Prompt to Approved?").waitForExistence(timeout: 15), "The Mermaid fence is drawn")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "n²/2")).firstMatch.waitForExistence(timeout: 5), "The display formula is drawn")
        XCTAssertFalse(labelled("mermaid").exists, "The diagram does not fall back to its source")
        screenshot("session-diagrams")

        // Prompt history: recall the prompt, ready to edit and send again.
        app.buttons["composerAdd"].tap()
        let history = app.buttons["promptHistory"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let entry = app.buttons["historyEntry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(NSPredicate(format: "value == %@", "Draw the approval flow").evaluate(with: editor) ||
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Draw the approval flow"), object: editor)], timeout: 5) == .completed,
            "The recalled prompt is in the editor")
        editor.tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Draw the approval flow".count))

        // Side question: an answer card, and no new message in the session.
        let before = ((try await api("/api/session/\(id)/message?limit=200"))["data"] as? [Any])?.count
        editor.typeText("/btw what does B decide?")
        app.buttons["composerSend"].tap()
        let answer = element("sideAnswer")
        XCTAssertTrue(answer.waitForExistence(timeout: 20), "The side answer appears")
        XCTAssertTrue(app.staticTexts["Side answer."].firstMatch.waitForExistence(timeout: 5))
        let after = ((try await api("/api/session/\(id)/message?limit=200"))["data"] as? [Any])?.count
        XCTAssertEqual(before, after, "A side question never enters the history")
        screenshot("session-side-question")
        app.buttons["dismissSideQuestion"].tap()
        XCTAssertFalse(element("sideQuestionCard").waitForExistence(timeout: 2))

        // Export: Markdown through the share sheet.
        app.buttons["sessionActions"].tap()
        XCTAssertTrue(app.buttons["Export session…"].waitForExistence(timeout: 5)); app.buttons["Export session…"].tap()
        let share = app.buttons["exportShare"]
        XCTAssertTrue(share.waitForExistence(timeout: 20), "The export is prepared")
        XCTAssertTrue(share.label.hasSuffix(".md"))
        share.tap()
        let sheet = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label == %@ OR label == %@", "ActivityListView", "Copy", "Save to Files")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "The share sheet opens")
        screenshot("session-export-share")
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() } else { app.swipeDown(velocity: .fast) }
        let done = app.buttons["closeExport"]
        XCTAssertTrue(done.waitForExistence(timeout: 10)); done.tap()

        // Move: into a new worktree of the project, applied while the session is idle.
        app.buttons["sessionActions"].tap()
        XCTAssertTrue(app.buttons["Move session…"].waitForExistence(timeout: 5)); app.buttons["Move session…"].tap()
        let target = app.buttons["moveTarget-new"]
        XCTAssertTrue(target.waitForExistence(timeout: 20), "The worktree list loads"); target.tap()
        let banner = element("pendingMove")
        XCTAssertTrue(banner.waitForExistence(timeout: 60))
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Moved to"), object: banner)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 90), .completed, "The move is applied: \(banner.label)")
        let info = try await api("/api/session/\(id)")["data"] as? [String: Any]
        let moved = try XCTUnwrap((info?["location"] as? [String: Any])?["directory"] as? String)
        XCTAssertNotEqual(moved, directory, "The session lives in the worktree now")
        XCTAssertTrue(banner.label.contains(URL(fileURLWithPath: moved).lastPathComponent), "The banner names the worktree")
        screenshot("session-moved")
    }
}

import Foundation
import XCTest
import UIKit

/// iPhone: the switcher from Home's toolbar button, without a hardware keyboard, and the context sheet.
nonisolated final class SwitcherSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testSwitcherAndContext() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        try launchFreshApp(suffix: "-switcher")
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Switcher sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForNonExistence(timeout: 10))
        let directory = try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])
        var ids: [String] = []
        for title in ["Switcher first", "Switcher target"] {
            let created = try await api("/api/session", method: "POST", body: ["title": title, "location": ["directory": directory], "model": ["providerID": "mock", "id": "mock-1"]])
            ids.append(try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String))
        }
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "switcher-usage", "script": ["calls": [["deltas": [["text": "Context for the sheet."]]]]]], mock: true)
        _ = try await api("/api/session/\(ids[0])/prompt", method: "POST", body: ["text": "Give this session some usage."])
        _ = try await api("/api/experimental/session/\(ids[0])/wait", method: "POST")
        XCTAssertTrue(homeSessionRow(ids[0]).exists)
        // The toolbar button opens the switcher; a tap opens a result.
        let button = app.buttons["openCommandPalette"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        let search = app.textFields["paletteSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["palette-command:session.new"].waitForExistence(timeout: 5), "The palette opens with the desktop's commands")
        search.typeText("first")
        let row = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ":" + ids[0])).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        screenshot("palette-iphone")
        row.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Switcher first"].waitForExistence(timeout: 10), "The switcher opened the session")
        // The header's context label opens the same content as iPad's Context tab, as a sheet.
        let context = app.buttons["sessionContext"]
        XCTAssertTrue(context.waitForExistence(timeout: 10)); context.tap()
        XCTAssertTrue(app.descendants(matching: .any)["contextPanel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["contextMeter"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Total Tokens")).firstMatch.exists, "The stats grid is shown")
        screenshot("context-sheet")
        app.buttons["closeContext"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["contextPanel"].waitForNonExistence(timeout: 5))
    }
}

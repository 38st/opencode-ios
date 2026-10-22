import Foundation
import XCTest

nonisolated final class ServerSmokeTests: SmokeTestCase {
    @MainActor private var explainedLocalNetwork = false
    private var values: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor func testServerFlows() async throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(values["OPENCODE_UI_URL"])
        let password = try XCTUnwrap(values["OPENCODE_UI_PASSWORD"])
        let v1 = try XCTUnwrap(values["OPENCODE_UI_V1_URL"])
        let v1Password = try XCTUnwrap(values["OPENCODE_UI_V1_PASSWORD"])
        try launchFreshApp(suffix: "-servers")
        XCTAssertTrue(app.buttons["addFirstServer"].waitForExistence(timeout: 10))
        screenshot("onboarding")
        addManual(url, password: password, name: "Studio Mac")
        waitForConnections()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.textFields["sessionSearch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["serverSwitcher"].exists)
        screenshot("home")
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.buttons["serverRow"].waitForExistence(timeout: 5))
        screenshot("server-list")
        app.buttons.matching(identifier: "serverRow").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Studio Mac"].waitForExistence(timeout: 5))
        screenshot("server-detail")
        app.buttons["Connection diagnostics"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 5))
        screenshot("diagnostics")
        app.navigationBars.buttons["Studio Mac"].tap()
        app.navigationBars.buttons["Settings"].tap()

        openAddServer()
        XCTAssertTrue(app.textFields["pairingLink"].waitForExistence(timeout: 5))
        app.textFields["pairingLink"].tap()
        let pair = try await api("/api/pair", method: "POST")
        let pairing = url + "/auth/connect/" + (try XCTUnwrap(pair["code"] as? String))
        app.textFields["pairingLink"].typeText(pairing)
        app.buttons["connectServer"].tap()
        XCTAssertTrue(app.navigationBars["Add server"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["addServer"].isHittable)
        waitForConnections(2)

        addManual(url, password: "deliberately-wrong", name: "Needs pairing")
        XCTAssertTrue(app.navigationBars["Re-pair server"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Needs re-pairing"].exists)
        screenshot("re-pair")
        app.buttons["Cancel"].tap()

        addManual(v1, password: v1Password, name: "Legacy server")
        XCTAssertTrue(app.navigationBars["Add server"].waitForNonExistence(timeout: 20))
        // A transient timeout can settle setup before the retry identifies V1.
        let legacyRow = app.buttons.matching(identifier: "serverRow")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Legacy server")).firstMatch
        if legacyRow.exists { legacyRow.tap() }
        XCTAssertTrue(app.staticTexts["updateTitle"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["opencode upgrade"].exists)
        XCTAssertTrue(app.staticTexts["opencode upgrade --major"].exists)
        screenshot("update")
        app.buttons["Check again"].tap()
        XCTAssertTrue(app.staticTexts["updateTitle"].waitForExistence(timeout: 15))
    }
    @MainActor private func addManual(_ url: String, password: String, name: String) {
        openAddServer()
        screenshot("add-server")
        XCTAssertTrue(app.buttons["copyPairCommand"].exists)
        app.buttons["copyPairCommand"].tap()
        XCTAssertTrue(app.buttons["copyPairCommand"].exists)
        app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        screenshot("add-server-password")
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText(name)
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(url)
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(password)
        if !explainedLocalNetwork {
            app.buttons["connectServer"].tap()
            XCTAssertTrue(app.buttons["localNetworkContinue"].waitForExistence(timeout: 20))
            screenshot("local-network"); app.buttons["localNetworkContinue"].tap()
            explainedLocalNetwork = true
        } else { connect(explainingLocalNetwork: false) }
    }
    @MainActor private func openAddServer() {
        app.activate()
        let add = app.buttons["addFirstServer"].exists ? app.buttons["addFirstServer"] : app.buttons["addServer"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        // Another simulator app can steal focus between activation and the tap.
        if !app.navigationBars["Add server"].waitForExistence(timeout: 5) {
            app.activate()
            add.tap()
        }
        XCTAssertTrue(app.navigationBars["Add server"].waitForExistence(timeout: 5))
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}

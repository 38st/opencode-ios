import Foundation
import XCTest
import UIKit

/// A server's settings against the sandbox: a provider connected with a clearly fake API key, MCP servers, a saved
/// permission, the redacted configuration and a worktree that must not be deleted without confirming its changes.
/// Everything runs in the fixture's own project (`OPENCODE_UI_ADMIN`), whose MCP servers are registered at runtime in
/// that location only.
nonisolated final class AdminSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var ipad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private struct Fixture: Decodable { let directory: String; let mcpFixture: String }
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(try XCTUnwrap(env["OPENCODE_UI_ADMIN"]).utf8))
    }
    private func location(_ directory: String) -> String {
        "location%5Bdirectory%5D=" + (directory.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
    }
    private var projectName: String { (try? fixture().directory).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "admin-project" }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = (ipad ? "ipad-" : "") + name
        attachment.lifetime = .keepAlways; add(attachment)
    }

    /// Pairs the sandbox by password; Settings stays open on the server list.
    @MainActor private func setup(_ suffix: String) throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        try launchFreshApp(suffix: suffix)
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Admin sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()
    }
    /// From the server list: the server's detail, then one settings section in the fixture's project.
    @MainActor private func openSection(_ section: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["serverRow"].firstMatch
        if row.exists && row.isHittable { row.tap() }
        let link = app.buttons["serverSettings-" + section]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Missing settings link " + section, file: file, line: line)
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()
        chooseProject()
    }
    @MainActor private func chooseProject() {
        let picker = app.buttons["adminProjectPicker"]
        guard picker.waitForExistence(timeout: 5) else { return }
        if (picker.label as String).hasSuffix(projectName) { return }
        picker.tap()
        let item = app.buttons[projectName].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The project menu lists the fixture project"); item.tap()
        XCTAssertTrue(NSPredicate(format: "label ENDSWITH %@", projectName).evaluate(with: picker))
    }
    @MainActor private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    @MainActor private func wait(_ element: XCUIElement, label: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "Expected \(label), got \(element.exists ? element.label : "nothing")", file: file, line: line)
    }
    @MainActor private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    @MainActor func testProvidersAndMCP() async throws {
        let admin = try fixture(), here = location(admin.directory)
        _ = try await api("/api/experimental/mcp/fixture?" + here, method: "PUT", body: ["config": ["type": "local", "command": ["node", admin.mcpFixture]]])
        _ = try await api("/api/experimental/mcp/broken?" + here, method: "PUT", body: ["config": ["type": "local", "command": ["/nonexistent/broken-mcp"]]])
        try setup("-providers")
        openSection("providers")
        let mock = app.buttons["provider-mock"]
        XCTAssertTrue(mock.waitForExistence(timeout: 20)); scrollTo(mock); mock.tap()
        XCTAssertTrue(app.buttons["connectMethod-key"].waitForExistence(timeout: 10)); app.buttons["connectMethod-key"].tap()
        // A clearly fake value: the mock provider ignores keys.
        let account = "UI smoke " + String(UUID().uuidString.prefix(4))
        let key = app.secureTextFields["providerAPIKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 5)); key.tap(); key.typeText("fake-test-key-not-a-secret")
        app.textFields["providerAccountLabel"].tap(); app.textFields["providerAccountLabel"].typeText(account)
        screenshot("admin-provider-key")
        app.buttons["submitProviderKey"].tap()
        let menu = app.buttons["accountMenu-" + account]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "The new account is listed")
        let mockInfo = try await api("/api/integration/mock?" + here)
        let labels = ((mockInfo["data"] as? [String: Any])?["connections"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
        XCTAssertEqual(labels.first, account, "The newest account is the active one")
        screenshot("admin-provider-accounts")
        // Removing asks first.
        menu.tap()
        XCTAssertTrue(app.buttons["Remove"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Remove"].firstMatch.tap()
        let confirm = app.buttons["confirmRemoveAccount"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 20))
        back(); back()

        openSection("mcp")
        wait(app.descendants(matching: .any)["mcpStatus-fixture"], label: "Connected")
        wait(app.descendants(matching: .any)["mcpStatus-broken"], label: "Failed")
        screenshot("admin-mcp")
        app.buttons["mcpDisconnect-fixture"].tap()
        wait(app.descendants(matching: .any)["mcpStatus-fixture"], label: "Disabled")
        app.buttons["mcpConnect-fixture"].tap()
        wait(app.descendants(matching: .any)["mcpStatus-fixture"], label: "Connected")
    }

    @MainActor func testSavedPermissionAndConfiguration() async throws {
        let admin = try fixture()
        let resolved = try await api("/api/location?" + location(admin.directory))
        let projectID = try XCTUnwrap((resolved["project"] as? [String: Any])?["id"] as? String)
        // A retried attempt starts without the rule an earlier one saved.
        for case let rule as [String: Any] in try await api("/api/permission/saved?projectID=" + projectID)["data"] as? [Any] ?? [] {
            if let id = rule["id"] as? String { _ = try await api("/api/permission/saved/" + id, method: "DELETE") }
        }
        // A real request answered "always", as the desktop would: the simulator has no passcode, so the app keeps its
        // own Allow always disabled.
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "admin-always", "script": ["calls": [
            ["tools": [["name": "shell", "arguments": ["command": "printf 'saved-rule\\n'"]]]], ["deltas": [["text": "Saved rule flow completed."]]]]]], mock: true)
        let created = try await api("/api/session", method: "POST", body: ["title": "Saved rule", "location": ["directory": admin.directory],
            "model": ["providerID": "mock", "id": "mock-1"], "permissions": [["action": "shell", "resource": "*", "effect": "ask"]]])
        let session = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        _ = try await api("/api/session/\(session)/prompt", method: "POST", body: ["text": "Run the saved rule flow."])
        var request: String?
        for _ in 0..<100 where request == nil {
            request = ((try await api("/api/session/\(session)/permission"))["data"] as? [[String: Any]])?.first?["id"] as? String
            if request == nil { try await Task.sleep(for: .milliseconds(200)) }
        }
        _ = try await api("/api/session/\(session)/permission/\(try XCTUnwrap(request))/reply", method: "POST", body: ["decision": "always"])
        _ = try await api("/api/experimental/session/\(session)/wait", method: "POST")
        try setup("-permissions")
        openSection("permissions")
        let delete = app.buttons["deleteSavedPermission"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 20), "The saved rule is listed")
        XCTAssertTrue(app.staticTexts["shell"].exists)
        screenshot("admin-saved-permission")
        delete.tap()
        let confirm = app.buttons["confirmDeleteSavedPermission"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 20))
        let saved = try await api("/api/permission/saved?projectID=" + projectID)
        XCTAssertEqual((saved["data"] as? [Any])?.count, 0, "The server deleted the rule")
        back()

        openSection("configuration")
        XCTAssertTrue(app.descendants(matching: .any)["configDocument"].firstMatch.waitForExistence(timeout: 20))
        let redacted = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "[redacted]")).firstMatch
        XCTAssertTrue(redacted.waitForExistence(timeout: 10), "The mock provider's key is hidden")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "fixture-not-a-secret")).firstMatch.exists)
        screenshot("admin-configuration")
        // Changing the global shell asks first; cancelling changes nothing.
        let shell = app.buttons["shellPicker"]
        XCTAssertTrue(shell.waitForExistence(timeout: 10)); shell.tap()
        let zsh = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "zsh")).firstMatch
        XCTAssertTrue(zsh.waitForExistence(timeout: 5)); zsh.tap()
        XCTAssertTrue(app.buttons["confirmShell"].firstMatch.waitForExistence(timeout: 5))
        // The confirmation is a popover here: tapping outside it cancels.
        if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap() }
        XCTAssertTrue(app.buttons["confirmShell"].firstMatch.waitForNonExistence(timeout: 5))
        let entries = try await rawAPI("/api/config?" + location(admin.directory)) as? [[String: Any]] ?? []
        XCTAssertFalse(entries.contains { (($0["info"] as? [String: Any])?["shell"] as? String) == "/bin/zsh" }, "Cancel sent nothing")
    }

    @MainActor func testWorktreeRemovalAsksFirst() async throws {
        let admin = try fixture()
        let resolved = try await api("/api/location?" + location(admin.directory))
        let projectID = try XCTUnwrap((resolved["project"] as? [String: Any])?["id"] as? String)
        try setup("-worktrees")
        openSection("worktrees")
        let name = "ui-wt-" + String(UUID().uuidString.prefix(6)).lowercased()
        let field = app.textFields["worktreeName"]
        XCTAssertTrue(field.waitForExistence(timeout: 20)); scrollTo(field); field.tap(); field.typeText(name)
        app.buttons["createWorktree"].tap()
        let delete = app.buttons["deleteWorktree-" + name]
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "The new worktree is listed")
        func directories() async throws -> [String] {
            (try await rawAPI("/api/worktree?projectID=" + projectID) as? [[String: Any]] ?? []).compactMap { $0["directory"] as? String }
        }
        let created = try await directories()
        let worktree = try XCTUnwrap(created.first { $0.hasSuffix("/" + name) })
        _ = try await api("/api/shell?" + location(worktree), method: "POST", body: ["command": "printf 'changed\\n' >> README.md && printf 'new\\n' > ui-dirty.txt"])
        for _ in 0..<50 {
            let status = try await api("/api/vcs/status?" + location(worktree))
            if (status["data"] as? [Any])?.count == 2 { break }
            try await Task.sleep(for: .milliseconds(300))
        }
        scrollTo(delete); delete.tap()
        let dirty = app.descendants(matching: .any)["worktreeDirty"].firstMatch
        XCTAssertTrue(dirty.waitForExistence(timeout: 20), "The uncommitted changes are shown first")
        XCTAssertTrue(app.staticTexts["README.md"].exists && app.staticTexts["ui-dirty.txt"].exists)
        XCTAssertTrue(app.buttons["forceDeleteWorktree"].exists)
        screenshot("admin-worktree-dirty")
        app.buttons["cancelDeleteWorktree"].tap()
        XCTAssertTrue(dirty.waitForNonExistence(timeout: 10))
        let kept = try await directories()
        XCTAssertTrue(kept.contains(worktree), "Cancel kept the worktree")
        delete.tap()
        XCTAssertTrue(dirty.waitForExistence(timeout: 20))
        app.buttons["forceDeleteWorktree"].tap()
        let confirm = app.buttons["confirmForceDeleteWorktree"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 30))
        let remaining = try await directories()
        XCTAssertFalse(remaining.contains(worktree), "The server deleted it")
    }

    /// The switcher opens a server's settings section; on iPad the sections sit in a sidebar.
    @MainActor func testSwitcherOpensSettings() throws {
        try setup("-switcher-settings")
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForNonExistence(timeout: 10))
        if ipad { rotate(to: .landscapeLeft) }
        setHome(open: true)
        let button = app.buttons["openCommandPalette"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        let search = app.textFields["paletteSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.typeText("worktrees")
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "palette-settings:", ":worktrees")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["createWorktree"].waitForExistence(timeout: 15), "The switcher opened Worktrees")
        if ipad {
            let providers = app.buttons["settingsSidebar-providers"]
            XCTAssertTrue(providers.waitForExistence(timeout: 5), "iPad shows the settings sidebar"); providers.tap()
            XCTAssertTrue(app.buttons["provider-mock"].waitForExistence(timeout: 20))
        }
        screenshot("admin-switcher-settings")
    }

    /// Bare arrays, which `api` does not return.
    @MainActor private func rawAPI(_ route: String) async throws -> Any {
        let base = try XCTUnwrap(env["OPENCODE_UI_URL"]), password = try XCTUnwrap(env["OPENCODE_UI_PASSWORD"])
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + route)))
        request.setValue("Basic " + Data(("opencode:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }
}

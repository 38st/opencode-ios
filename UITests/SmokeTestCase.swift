import Foundation
import XCTest
import UIKit

nonisolated class SmokeTestCase: XCTestCase {
    @MainActor lazy var app = XCUIApplication()

    /// - Parameter animations: false launches the Debug build without UIKit animations.
    @MainActor func launchFreshApp(suffix: String, animations: Bool = true) throws {
        let id = try XCTUnwrap(ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"])
        app.launchEnvironment["OPENCODE_UI_TEST_ID"] = id + suffix
        app.launchArguments = ["--ui-testing-reset"] + (animations ? [] : ["--ui-testing-no-animations"])
        addTeardownBlock { @MainActor [self] in finishTest() }
        app.launch()
        // XCUIApplication.open can relaunch the process. Only the test's initial launch resets data.
        app.launchArguments = []
        // Set orientation after launch: a cold iPad launch can restore the previous portrait scene.
        rotate(to: .portrait)
        XCTAssertTrue(app.buttons["addFirstServer"].waitForExistence(timeout: 10), "Reset must restore onboarding")
    }

    @MainActor func connect(explainingLocalNetwork: Bool) {
        app.buttons["connectServer"].tap()
        if explainingLocalNetwork {
            let proceed = app.buttons["localNetworkContinue"]
            XCTAssertTrue(proceed.waitForExistence(timeout: 20), "A fresh install must explain Local Network access")
            proceed.tap()
        }
    }

    @MainActor func waitForConnections(_ count: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let statuses = app.descendants(matching: .any).matching(identifier: "serverConnectionStatus")
            .matching(NSPredicate(format: "value == %@", "connected"))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: statuses)
        let result = XCTWaiter.wait(for: [expectation], timeout: 20)
        attachConnectionDiagnostics()
        XCTAssertEqual(result, .completed, "Expected \(count) connected servers", file: file, line: line)
        // Regression: the narrow iPad Home sheet must not displace the Settings confirmation.
        XCTAssertTrue(app.buttons["closeSettings"].exists, "Settings must remain presented after setup", file: file, line: line)
    }

    @MainActor func attachConnectionDiagnostics() {
        let probe = app.descendants(matching: .any).matching(identifier: "connectionDiagnostics").firstMatch
        let diagnostics = probe.exists ? (probe.value as? String ?? "No diagnostics value") : "Diagnostics element unavailable"
        let attachment = XCTAttachment(string: diagnostics)
        attachment.name = "connection-state-and-transitions"; attachment.lifetime = .keepAlways; add(attachment)
    }

    /// Rotates and waits until the app's window has the new aspect. A tap sent while the
    /// interface is still rotating can be lost or land on the old layout.
    @MainActor func rotate(to orientation: UIDeviceOrientation, file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let window = app.windows.firstMatch, deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let frame = window.exists ? window.frame : .zero
            if frame.width > 0 && (frame.width > frame.height) == landscape { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Rotation to \(landscape ? "landscape" : "portrait") did not finish", file: file, line: line)
    }

    /// Opens or closes iPad Home (the sidebar, or the sheet at narrow widths) through its toggle,
    /// whose accessibility value reports what is visible. iPhone has no toggle.
    @MainActor func setHome(open: Bool, file: StaticString = #filePath, line: UInt = #line) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let toggle = app.buttons["toggleHome"], target = open ? "open" : "closed"
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Missing Home toggle", file: file, line: line)
        func reached() -> Bool {
            let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", target), object: toggle)
            return XCTWaiter.wait(for: [state], timeout: 10) == .completed
        }
        if toggle.value as? String == target { return }
        toggle.tap()
        if reached() { return }
        // One re-tap covers a tap lost to a late layout pass; it is logged so a pattern stays visible.
        print("setHome(open: \(open)): Home toggle still \(String(describing: toggle.value)) after 10 s; tapping once more")
        if toggle.value as? String != target { toggle.tap() }
        XCTAssertTrue(reached(), "Home did not become \(target)", file: file, line: line)
    }

    /// Home realizes rows only near the viewport, and earlier sessions sink as more are created or the day changes.
    /// Wait for a new row at the top, then sweep the list from the top down until the row is on screen.
    @MainActor func homeSessionRow(_ id: String, timeout: TimeInterval = 30) -> XCUIElement {
        let row = app.buttons["homeSession-" + id], list = app.collectionViews["homeSessions"]
        func visible() -> Bool { row.exists && row.isHittable }
        if row.waitForExistence(timeout: 5) && row.isHittable { return row }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard list.waitForExistence(timeout: 2) else { continue }
            for _ in 0..<6 where !visible() { list.swipeDown() }
            for _ in 0..<15 where !visible() { list.swipeUp() }
            if visible() { return row }
        }
        return row
    }
    @MainActor func api(_ route: String, method: String = "GET", body: [String: Any]? = nil, mock: Bool = false) async throws -> [String: Any] {
        let env = ProcessInfo.processInfo.environment
        let base = try XCTUnwrap(env[mock ? "OPENCODE_UI_MOCK_URL" : "OPENCODE_UI_URL"])
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + route)))
        request.httpMethod = method
        if !mock {
            let password = try XCTUnwrap(env["OPENCODE_UI_PASSWORD"])
            request.setValue("Basic " + Data(("opencode:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertTrue((200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0))
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    @MainActor private func finishTest() {
        if (testRun?.failureCount ?? 0) > 0 {
            attachConnectionDiagnostics()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "failure-screen"; screenshot.lifetime = .keepAlways; add(screenshot)
            var hierarchy = app.debugDescription
            for (key, value) in ProcessInfo.processInfo.environment where key.contains("PASSWORD") || key.contains("PAIRING_LINK") {
                if !value.isEmpty { hierarchy = hierarchy.replacingOccurrences(of: value, with: "[REDACTED]") }
            }
            hierarchy = hierarchy.replacingOccurrences(of: #"https?://[^\s'\"<>]+/auth/connect/[A-Za-z0-9_-]+"#, with: "[REDACTED PAIRING LINK]", options: .regularExpression)
            let attachment = XCTAttachment(string: hierarchy)
            attachment.name = "failure-accessibility-hierarchy"; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.terminate()
    }
}

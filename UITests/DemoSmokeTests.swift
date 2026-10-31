import XCTest

/// The demo App Review uses: from a fresh install, without a server, approve the waiting permission, review the
/// diff and leave. The demo is recorded (Tools/demo/record.mjs); recording it again changes these session IDs.
final class DemoSmokeTests: SmokeTestCase {
    static let permissionSession = "ses_e6fa7427bffer8tYLzVWh0mXe0"
    static let liveSession = "ses_e6fa74a63ffeurj25DlwRKuTvK"
    @MainActor private var ipad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = (ipad ? "ipad-" : "") + name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func open(_ id: String) {
        if !ipad, app.buttons["BackButton"].isHittable { app.buttons["BackButton"].tap() }
        setHome(open: true)
        let row = homeSessionRow(id); XCTAssertTrue(row.isHittable, "Missing demo session \(id)"); row.tap()
        XCTAssertTrue(app.textViews["promptEditor"].waitForExistence(timeout: 10))
        setHome(open: false)
    }

    @MainActor func testDemoApprovesReviewsAndExits() throws {
        try launchFreshApp(suffix: "demo")
        let start = app.buttons["tryDemo"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        XCTAssertTrue(app.buttons["exitDemo"].waitForExistence(timeout: 10), "The demo must say it is a demo and offer a way out")
        screenshot("demo-home")

        // A running session streams its recorded reply.
        open(Self.liveSession)
        let reply = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "validate")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20), "The live session should stream its reply")

        // The waiting permission is approved from the dock, and the session carries on.
        open(Self.permissionSession)
        let dock = app.descendants(matching: .any).matching(identifier: "approvalDock").firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 15))
        let allow = dock.buttons["dockAllowOnce"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 10)); screenshot("demo-permission")
        allow.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dock)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 15), .completed, "Approving should clear the request")

        // Review shows the working-tree diff.
        let review = app.buttons[ipad ? "toggleReview" : "sessionReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        let file = app.buttons[ipad ? "reviewFile-src/validate.ts" : "src/validate.ts"].firstMatch
        if file.waitForExistence(timeout: 10) { file.tap() }
        else {
            let tree = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "validate.ts")).firstMatch
            XCTAssertTrue(tree.waitForExistence(timeout: 10)); tree.tap()
        }
        XCTAssertTrue(app.collectionViews["diffCollection"].waitForExistence(timeout: 10)); screenshot("demo-review")
        if !ipad { app.buttons["closeReview"].tap() } else { review.tap() }

        // Leaving returns to onboarding, and nothing from the demo stays.
        app.buttons["exitDemo"].tap()
        XCTAssertTrue(app.buttons["addFirstServer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tryDemo"].exists)
    }
}

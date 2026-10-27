import Foundation
import XCTest
import UIKit

nonisolated final class ReviewSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var ipad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = (ipad ? "ipad-" : "") + name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func setupReview() async throws -> [String: String] {
        try launchFreshApp(suffix: "review")
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverURL"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Review sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()
        // Close Settings before rotating, as the other suites do: a tap during rotation can be lost.
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForNonExistence(timeout: 10))
        if ipad { rotate(to: .landscapeLeft) }
        return try JSONDecoder().decode([String: String].self, from: Data(try XCTUnwrap(env["OPENCODE_UI_REVIEW"]).utf8))
    }
    @MainActor private func openSession(_ id: String) {
        if !ipad, app.buttons["BackButton"].isHittable { app.buttons["BackButton"].tap() }
        setHome(open: true)
        let row = homeSessionRow(id); XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(app.textViews["promptEditor"].waitForExistence(timeout: 10))
        setHome(open: false)
    }
    @MainActor private func openReview() {
        let button = app.buttons[ipad ? "toggleReview" : "sessionReview"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    @MainActor func testReviewAndFiles() async throws {
        let fixture = try await setupReview(); let session = try XCTUnwrap(fixture["session"])
        let commentText = ipad ? "Simplify this iPad review selection" : "Simplify this review selection"
        openSession(session); openReview()
        let file = app.buttons[ipad ? "reviewFile-Sources/Example.swift" : "Sources/Example.swift"].firstMatch
        if file.waitForExistence(timeout: 10) { file.tap() }
        else {
            let tree = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Example.swift")).firstMatch
            XCTAssertTrue(tree.waitForExistence(timeout: 10)); tree.tap()
        }
        let collection = app.collectionViews["diffCollection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10)); screenshot("review-changes")
        let first = collection.cells.matching(NSPredicate(format: "label CONTAINS %@", "added")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5)))
        let editor = app.textViews["Add context for this change"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(commentText)
        app.buttons["Comment"].tap()
        if !ipad { app.buttons["closeReview"].tap() }
        let chips = app.descendants(matching: .any)["commentAttachments"]
        XCTAssertTrue(chips.waitForExistence(timeout: 5)); screenshot("review-comment")
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "plain-text"], mock: true)
        let send = app.buttons["composerSend"]; XCTAssertTrue(send.waitForExistence(timeout: 5)); send.tap()
        let user = try await sentComment(session, text: commentText)
        let metadata = try XCTUnwrap(user["metadata"] as? [String: Any])
        let comments = try XCTUnwrap(metadata["comments"] as? [[String: Any]])
        XCTAssertEqual(comments.first?["comment"] as? String, commentText)
        let selection = try XCTUnwrap(comments.first?["selection"] as? [String: Any])
        XCTAssertEqual(selection["startLine"] as? Int, 2); XCTAssertEqual(selection["endLine"] as? Int, 3)
        let path = try XCTUnwrap(comments.first?["path"] as? String)
        XCTAssertTrue(path.hasSuffix("/Sources/Example.swift"))
        XCTAssertEqual(user["text"] as? String, "The user made the following comment regarding lines 2 through 3 of \(path): \(commentText)")
        let proof = XCTAttachment(data: try JSONSerialization.data(withJSONObject: user, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        proof.name = "review-comment-server"; proof.lifetime = .keepAlways; add(proof)
        XCTAssertTrue(app.staticTexts[commentText].firstMatch.waitForExistence(timeout: 10))
        if !ipad { openReview() }
        app.buttons["Files"].firstMatch.tap()
        let filter = app.textFields["Filter files"]; XCTAssertTrue(filter.waitForExistence(timeout: 10)); filter.tap(); filter.typeText("Example")
        let result = app.buttons["fileEntry-Sources/Example.swift"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap(); screenshot("review-files")
        XCTAssertTrue(app.buttons["Mention in composer"].waitForExistence(timeout: 10)); app.buttons["Mention in composer"].tap()
        if !ipad {
            let source = app.collectionViews["diffCollection"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Line 2,")).firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 5)); source.press(forDuration: 0.6)
            XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Document this file line")
            app.buttons["Comment"].tap(); app.buttons["closeReview"].tap()
            _ = try await api("/admin/scenario", method: "POST", body: ["name": "plain-text"], mock: true)
            app.buttons["composerSend"].tap()
            let fileUser = try await sentComment(session, text: "Document this file line")
            let fileComments = (fileUser["metadata"] as? [String: Any])?["comments"] as? [[String: Any]]
            XCTAssertEqual(fileComments?.first?["origin"] as? String, "file")
            let proof = XCTAttachment(data: try JSONSerialization.data(withJSONObject: fileUser, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
            proof.name = "file-comment-server"; proof.lifetime = .keepAlways; add(proof)
            XCTAssertTrue(app.staticTexts["Document this file line"].firstMatch.waitForExistence(timeout: 10))
            openSession(try XCTUnwrap(fixture["noGitSession"])); openReview()
            let create = app.buttons["Create Git repository"]
            XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
            let directory = try XCTUnwrap(fixture["noGit"])
            var location = URLComponents(); location.queryItems = [.init(name: "location[directory]", value: directory)]
            var provider: String?
            for _ in 0..<100 {
                provider = (try await api("/api/vcs?" + (location.percentEncodedQuery ?? "")))["data"].flatMap { $0 as? [String: Any] }?["provider"] as? String
                if provider == "git" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(provider, "git")
            XCTAssertTrue(create.waitForNonExistence(timeout: 5))
            screenshot("review-created-git")
        }
    }
    @MainActor private func sentComment(_ session: String, text: String) async throws -> [String: Any] {
        for _ in 0..<200 {
            let messages = try await api("/api/session/\(session)/message?limit=200&order=asc")
            if let user = (messages["data"] as? [[String: Any]])?.last(where: { item in
                ((item["metadata"] as? [String: Any])?["comments"] as? [[String: Any]])?.contains { $0["comment"] as? String == text } == true
            }) { return user }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The server did not receive the review comment")
        return [:]
    }
    @MainActor func testReviewNavigation() async throws {
        let fixture = try await setupReview()
        openSession(try XCTUnwrap(fixture["navigationSession"]))
        let turnFile = app.buttons["turnFile-Sources/Example.swift"].firstMatch
        for _ in 0..<15 {
            if turnFile.isHittable { break }
            app.collectionViews["transcriptScroll"].swipeDown()
        }
        XCTAssertTrue(turnFile.waitForExistence(timeout: 10)); turnFile.tap()
        let collection = app.collectionViews["diffCollection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Next file"].waitForExistence(timeout: 5))
        if ipad {
            collection.cells.firstMatch.tap()
            app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
            XCTAssertEqual(app.buttons["reviewFile-src/created.ts"].value as? String, "Selected")
            app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
            XCTAssertEqual(app.buttons["reviewFile-Sources/Example.swift"].value as? String, "Selected")
            app.buttons["Diff view"].tap(); app.buttons["Unified"].tap()
        } else {
            app.buttons["Next file"].tap(); app.buttons["Previous file"].tap()
        }
        screenshot("review-turn-navigation")
        let source = app.buttons["Review source"]
        for name in ["Branch changes", "Git changes", "Last turn changes"] {
            source.tap(); app.buttons[name].tap()
            XCTAssertTrue(collection.waitForExistence(timeout: 10))
        }
        if ipad {
            app.buttons["reviewFile-Sources/Example.swift"].tap()
            app.switches["Reviewed"].tap()
        } else {
            if app.buttons["Collapse all"].exists { app.buttons["Collapse all"].tap() }
            app.buttons["Expand all"].tap()
            app.buttons["Collapse all"].tap()
            app.buttons["Review options"].tap(); app.buttons["Reviewed Sources/Example.swift"].tap()
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 of ")).firstMatch.waitForExistence(timeout: 5))
        screenshot("review-reviewed")
        if !ipad {
            let header = app.buttons["Sources/Example.swift"].firstMatch
            XCTAssertTrue(header.waitForExistence(timeout: 5)); header.tap()
        }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open file")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Mention in composer"].waitForExistence(timeout: 10))
        XCTAssertTrue(collection.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Line 2,")).firstMatch.waitForExistence(timeout: 5))
        // On iPad the first synthesized ⌘F does not reach the Find field until M6 adds menu commands; it is an expected failure below.
        app.buttons["Find"].tap()
        let find = app.textFields["Find"]
        let opened = find.waitForExistence(timeout: 5)
        XCTAssertTrue(opened); guard opened else { return }; find.tap(); find.typeText("let")
        let matches = app.staticTexts["Search matches"]
        XCTAssertTrue(matches.waitForExistence(timeout: 5))
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1 of 2"), object: matches)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed)
        app.buttons["Next match"].tap(); XCTAssertEqual(matches.value as? String, "2 of 2")
        app.buttons["Previous match"].tap(); XCTAssertEqual(matches.value as? String, "1 of 2")
        app.buttons["Close search"].tap()
        app.buttons["All files"].tap()
        let folder = app.buttons["fileEntry-Sources/"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10)); folder.tap()
        app.buttons["fileEntry-Sources/Example.swift"].tap()
        XCTAssertTrue(app.buttons["Mention in composer"].waitForExistence(timeout: 10))
        screenshot("review-file-tree")
        if !ipad { app.buttons["closeReview"].tap() }
        else { app.buttons["toggleReview"].tap() }
        let link = app.links["Example.swift"].firstMatch
        for _ in 0..<15 {
            if link.isHittable { break }
            app.collectionViews["transcriptScroll"].swipeDown()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        XCTAssertTrue(app.buttons["Mention in composer"].waitForExistence(timeout: 10))
        if !ipad { app.buttons["closeReview"].tap() } else { app.buttons["toggleReview"].tap() }
        let codeLink = app.links["Sources/Example.swift:2"].firstMatch
        XCTAssertTrue(codeLink.waitForExistence(timeout: 10)); codeLink.tap()
        XCTAssertTrue(app.buttons["Mention in composer"].waitForExistence(timeout: 10))
        screenshot("review-file-link")
        if ipad {
            XCTExpectFailure("Known issue: on iPad the first synthesized ⌘F does not reach the Find field until M6 adds menu commands", options: .nonStrict()) {
                app.typeKey("f", modifierFlags: .command)
                XCTAssertTrue(app.textFields["Find"].waitForExistence(timeout: 5))
            }
        }
    }
    @MainActor func testLargeDiffScroll() async throws {
        let fixture = try await setupReview(); openSession(try XCTUnwrap(fixture["largeSession"])); openReview()
        let source = app.buttons["Review source"]
        XCTAssertTrue(source.waitForExistence(timeout: 15)); source.tap(); app.buttons["Last turn changes"].tap()
        let file = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Large.swift")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
        if ipad, app.buttons["Toggle file tree"].exists { app.buttons["Toggle file tree"].tap() }
        let collection = app.collectionViews["diffCollection"]
        XCTAssertTrue(collection.cells.firstMatch.waitForExistence(timeout: 10))
        screenshot(ipad ? "review-large-split" : "review-large-unified")
        let options = XCTMeasureOptions(); options.iterationCount = 1
        var traversal: TimeInterval = 0
        // On the simulator this metric reports only the dragging and deceleration duration, without hitch data;
        // the app's display-link recorder carries the budgets.
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            traversal = traverse(collection)
        }
        try recordScroll(collection, name: "review-scroll", traversal: traversal)
        if ipad {
            app.buttons["Diff view"].tap(); app.buttons["Wrap lines"].tap()
            screenshot("review-large-split-nowrap")
            let unwrapped = traverse(collection)
            try recordScroll(collection, name: "review-scroll-nowrap", traversal: unwrapped)
        }
    }
    /// Flicks through the whole diff and back. Gestures use coordinates computed once, so a flick never
    /// re-resolves the list, and the position is read every third flick to keep XCUITest queries off the frames.
    @MainActor @discardableResult private func traverse(_ collection: XCUIElement) -> TimeInterval {
        func metrics() -> [String: Double] { (collection.value as? String).flatMap { try? JSONDecoder().decode([String: Double].self, from: Data($0.utf8)) } ?? [:] }
        let started = Date(), frame = collection.frame, origin = app.coordinate(withNormalizedOffset: .zero)
        let low = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.85))
        let high = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * 0.2))
        func flick(up: Bool) { (up ? low : high).press(forDuration: 0.01, thenDragTo: up ? high : low, withVelocity: XCUIGestureVelocity(20_000), thenHoldForDuration: 0) }
        var bottom = false, previous: Double = -1, stationary = 0
        for flicks in 1...600 {
            flick(up: true)
            guard flicks % 3 == 0 else { continue }
            let values = metrics(), offset = values["offset"] ?? -1
            if offset + (values["viewportHeight"] ?? 0) >= (values["contentHeight"] ?? .infinity) - 2 { bottom = true; break }
            stationary = offset == previous ? stationary + 1 : 0; previous = offset
            if stationary >= 2 { XCTFail("Diff did not advance: \(values)"); return Date().timeIntervalSince(started) }
        }
        XCTAssertTrue(bottom, "The fast flicks must reach the final diff row")
        var top = false
        for flicks in 1...600 {
            flick(up: false)
            guard flicks % 3 == 0 else { continue }
            if (metrics()["offset"] ?? .infinity) <= 2 { top = true; break }
        }
        XCTAssertTrue(top, "The fast flicks must return to the first diff row")
        return Date().timeIntervalSince(started)
    }
    @MainActor private func recordScroll(_ collection: XCUIElement, name: String, traversal: TimeInterval) throws {
        let json = try XCTUnwrap(collection.value as? String)
        var metrics = try JSONDecoder().decode([String: Double].self, from: Data(json.utf8))
        metrics["traversalSeconds"] = traversal
        let data = try JSONEncoder().encode(metrics)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json"); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(metrics["frames"] ?? 0, 0)
        XCTAssertEqual(metrics["split"], ipad ? 1 : 0)
        XCTAssertEqual(metrics["wrapping"], name.hasSuffix("nowrap") ? 0 : 1)
        XCTAssertEqual(metrics["rows"], ipad ? 5_000 : 10_000)
        XCTAssertEqual(metrics["highlightedLines"], 10_000)
        XCTAssertEqual(metrics["wordDiffLines"], 10_000)
        XCTAssertLessThan(metrics["hitchMillisecondsPerSecond"] ?? .infinity, 5)
        XCTAssertLessThan(metrics["longestFrameMilliseconds"] ?? .infinity, 100)
        XCTAssertLessThan(metrics["firstRowsMilliseconds"] ?? .infinity, 300)
        XCTAssertLessThan(metrics["physicalFootprintMiB"] ?? .infinity, 200)
    }
}

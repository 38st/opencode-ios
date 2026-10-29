import Foundation
import XCTest
import UIKit

/// The window inventory and command trace the DEBUG app exposes to UI tests.
struct WindowInventory {
    struct Window { let id: String; let key: Bool; let path: [String] }
    let this: String
    let windows: [Window]
    init(_ value: String) {
        let lines = value.split(separator: "\n").map(String.init)
        this = lines.first.map { String($0.dropFirst("this=".count)) } ?? ""
        windows = lines.dropFirst().compactMap { line in
            let fields = Dictionary(uniqueKeysWithValues: line.split(separator: " ").compactMap { field -> (String, String)? in
                let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : parts.count == 1 && field.hasSuffix("=") ? (parts[0], "") : nil
            })
            guard let id = fields["window"] else { return nil }
            return Window(id: id, key: fields["key"] == "true", path: (fields["path"] ?? "").split(separator: ",").map(String.init))
        }
    }
    var current: Window? { windows.first { $0.id == this } }
    var key: Window? { windows.first(where: \.key) }
}

extension SmokeTestCase {
    /// The window on screen. With two windows iPadOS keeps the other one's hierarchy queryable, and XCUITest can call
    /// either window hittable, so queries are scoped to the key window: the one most recently brought forward or touched.
    @MainActor var screen: XCUIElement {
        let windows = app.windows.allElementsBoundByIndex
        var key: String?, shown: [(window: XCUIElement, id: String)] = []
        for window in windows {
            let element = window.descendants(matching: .any)["windowInventory"].firstMatch
            guard element.exists, let value = element.value as? String else { continue }
            let inventory = WindowInventory(value)
            key = key ?? inventory.key?.id
            shown.append((window, inventory.this))
        }
        return shown.first { $0.id == key }?.window ?? windows.first { $0.isHittable } ?? app
    }
    @MainActor func inventory() -> WindowInventory {
        WindowInventory(screen.descendants(matching: .any)["windowInventory"].firstMatch.value as? String ?? "")
    }
    @MainActor @discardableResult func waitInventory(timeout: TimeInterval = 10, _ description: String, file: StaticString = #filePath, line: UInt = #line,
                                                     _ predicate: (WindowInventory) -> Bool) -> WindowInventory {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let value = inventory()
            if predicate(value) { return value }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        let value = inventory()
        XCTAssertTrue(predicate(value), description + ": " + String(describing: value.windows.map { "\($0.id.prefix(8)) key=\($0.key) path=\($0.path)" }), file: file, line: line)
        return value
    }
    /// Performed commands by ID, counted where they are dispatched.
    @MainActor func trace() -> [String: Int] {
        let value = screen.descendants(matching: .any)["commandTrace"].firstMatch.value as? String ?? ""
        return Dictionary(uniqueKeysWithValues: value.split(separator: " ").compactMap { field in
            let parts = field.split(separator: "=").map(String.init)
            return parts.count == 2 ? (parts[0], Int(parts[1]) ?? 0) : nil
        })
    }
    /// The menu commands the key window enables right now.
    @MainActor func enabledCommands() -> Set<String> {
        Set((screen.descendants(matching: .any)["workspaceCommands"].firstMatch.value as? String ?? "").split(separator: " ").map(String.init))
    }
    @MainActor func waitEnabled(_ command: String, _ enabled: Bool, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if enabledCommands().contains(command) == enabled { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("\(command) should be \(enabled ? "enabled" : "disabled"); enabled: \(enabledCommands().sorted())", file: file, line: line)
    }
    @MainActor func waitTrace(_ id: String, count: Int, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if trace()[id] ?? 0 == count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(trace()[id] ?? 0, count, "Performed count for \(id)", file: file, line: line)
    }
    @MainActor func waitValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: timeout), .completed, "\(element) should be \(value)", file: file, line: line)
    }
}

/// iPad only: the menu bar, the switcher with a keyboard, two windows, and drag and drop.
nonisolated final class WorkspaceSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var editor: XCUIElement { app.textViews["promptEditor"] }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "ipad-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    /// A paired server, Settings closed, landscape, Home open, and sessions created newest last.
    @MainActor private func setup(_ suffix: String, sessions titles: [String]) async throws -> [String] {
        continueAfterFailure = false
        try launchFreshApp(suffix: suffix)
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Workspace sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForNonExistence(timeout: 10))
        rotate(to: .landscapeLeft)
        var ids: [String] = []
        for title in titles {
            let created = try await api("/api/session", method: "POST", body: ["title": title, "location": ["directory": try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])], "model": ["providerID": "mock", "id": "mock-1"]])
            ids.append(try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String))
            try await Task.sleep(for: .milliseconds(50))
        }
        setHome(open: true)
        for id in ids { XCTAssertTrue(homeSessionRow(id).exists) }
        primeKeyboard()
        return ids
    }
    /// The server's ID, from the open session's header.
    @MainActor private func serverID() -> String {
        let header = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sessionHeader-")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        return String(header.identifier.dropFirst("sessionHeader-".count))
    }
    @MainActor private func key(_ key: String, _ modifiers: XCUIElement.KeyModifierFlags = []) { app.typeKey(key, modifierFlags: modifiers) }
    /// The iPad simulator drops the key of the first chord after a launch: only its modifier reaches the app.
    /// ReviewSmokeTests.testReviewNavigation checks that first chord; these flows send one chord that no command owns
    /// first, so every chord they check is pressed exactly once.
    @MainActor private func primeKeyboard() { key("j", .command) }
    /// Home's root sessions in the order ⌘1–9 and the session commands use; unread ones end in "*". The sandbox
    /// server also holds the fixture sessions, so expectations are computed from this, never assumed.
    @MainActor private func homeEntries() -> [String] {
        (screen.descendants(matching: .any)["homeOrder"].firstMatch.value as? String ?? "").split(separator: " ").map(String.init)
    }
    @MainActor private func homeOrder() -> [String] { homeEntries().map { $0.hasSuffix("*") ? String($0.dropLast()) : $0 } }
    /// The session `offset` places from the open one, wrapping, as the desktop's tab order does; optionally only unread ones.
    @MainActor private func neighbour(_ offset: Int, unread: Bool = false) -> String {
        let entries = homeEntries(), order = homeOrder(), current = inventory().current?.path.first ?? ""
        guard let index = order.firstIndex(of: current) else { XCTFail("\(current) is not in Home's order \(order)"); return "" }
        for step in 1..<max(order.count, 1) {
            let candidate = (index + offset * step + order.count) % order.count
            if !unread || entries[candidate].hasSuffix("*") { return order[candidate] }
        }
        XCTFail("No \(unread ? "unread " : "")neighbour in \(entries)"); return ""
    }
    /// Home's row for a session in the window on screen, scrolled into view.
    @MainActor private func row(_ id: String) -> XCUIElement {
        let screen = screen, row = screen.buttons["homeSession-" + id], list = screen.collectionViews["homeSessions"]
        func visible() -> Bool { row.exists && row.isHittable }
        if row.waitForExistence(timeout: 5) && row.isHittable { return row }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            guard list.waitForExistence(timeout: 2) else { continue }
            for _ in 0..<6 where !visible() { list.swipeDown() }
            for _ in 0..<15 where !visible() { list.swipeUp() }
            if visible() { return row }
        }
        return row
    }
    /// Opens Home in the window on screen through its state-verified toggle.
    @MainActor private func showHome() {
        let toggle = screen.buttons["toggleHome"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "open" { toggle.tap() }
        waitValue(toggle, "open")
    }
    @MainActor private func waitPath(_ ids: [String], _ description: String, file: StaticString = #filePath, line: UInt = #line) {
        waitInventory(description, file: file, line: line) { $0.current?.path == ids }
    }
    /// Puts the caret in the open session's composer, so a chord also has to get past the text view's own keys.
    @MainActor private func focusComposer(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "The session's composer", file: file, line: line)
        editor.tap()
        waitForKeyboard(shown: true, file: file, line: line)
    }
    /// Waits until the software keyboard has finished appearing or leaving. XCUITest waits for the app to idle after
    /// every event; a chord sent while the keyboard was still animating in (0.8 s after the tap on the composer) once
    /// left the app without its "animations complete" signal, and every later event then waited 60 seconds for it,
    /// past the test's time allowance (once, on the iPad).
    @MainActor private func waitForKeyboard(shown: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        if shown { XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "The software keyboard appears", file: file, line: line) }
        var last = CGRect.null, still = 0
        let deadline = Date().addingTimeInterval(5)
        while still < 3 && Date() < deadline {
            let frame = keyboard.exists ? keyboard.frame : .zero
            still = frame == last ? still + 1 : 0; last = frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(still, 3, "The software keyboard stops moving", file: file, line: line)
    }

    @MainActor func testMenuNavigationAndSwitcher() async throws {
        executionTimeAllowance = 300
        let ids = try await setup("-menus", sessions: ["Workspace A", "Workspace B", "Workspace C"])
        // ⌘1–9 follow Home's order (newest first), up to the number of sessions; nothing is open, so no neighbour either.
        XCTAssertTrue(Set(ids).isSubset(of: Set(homeOrder())), "Home lists the new sessions: \(homeOrder())")
        let count = min(9, homeOrder().count)
        waitEnabled("session.\(count)", true)
        if count < 9 { waitEnabled("session.\(count + 1)", false) }
        waitEnabled("session.next", false)
        var expected = homeOrder()[0]
        key("1", .command); waitPath([expected], "⌘1 opens the first session in Home's order")
        expected = homeOrder()[1]
        key("2", .command); waitPath([expected], "⌘2")
        // The session keys add ⌘ to the desktop's ⌥↑ and ⌥↓, which move the caret in a text view; they work from the composer.
        expected = neighbour(1)
        focusComposer(); key(XCUIKeyboardKey.downArrow.rawValue, [.option, .command]); waitPath([expected], "⌥⌘↓ is the next session")
        expected = neighbour(1)
        focusComposer(); key(XCUIKeyboardKey.downArrow.rawValue, [.option, .command]); waitPath([expected], "⌥⌘↓ again, wrapping")
        expected = neighbour(-1)
        focusComposer(); key(XCUIKeyboardKey.upArrow.rawValue, [.option, .command]); waitPath([expected], "⌥⌘↑ is the previous session")
        // Open A, so B and C can turn unread.
        row(ids[0]).tap(); waitPath([ids[0]], "A is open")
        // Unread: replies in B and C while A is open.
        for (index, id) in [ids[1], ids[2]].enumerated() {
            _ = try await api("/admin/scenario", method: "POST", body: ["name": "workspace-unread-\(index)", "script": ["calls": [["deltas": [["text": "Unread reply \(index)."]]]]]], mock: true)
            _ = try await api("/api/session/\(id)/prompt", method: "POST", body: ["text": "Reply so this session is unread."])
            _ = try await api("/api/experimental/session/\(id)/wait", method: "POST")
        }
        waitEnabled("session.next.unseen", true, timeout: 20)
        let unreadDeadline = Date().addingTimeInterval(20)
        while Date() < unreadDeadline && !(homeEntries().contains(ids[1] + "*") && homeEntries().contains(ids[2] + "*")) { try await Task.sleep(for: .milliseconds(300)) }
        XCTAssertTrue(homeEntries().contains(ids[1] + "*") && homeEntries().contains(ids[2] + "*"), "B and C are unread: \(homeEntries())")
        expected = neighbour(1, unread: true)
        focusComposer(); key(XCUIKeyboardKey.downArrow.rawValue, [.option, .shift, .command]); waitPath([expected], "⌥⇧⌘↓ opens the next unread session")
        expected = neighbour(-1, unread: true)
        focusComposer(); key(XCUIKeyboardKey.upArrow.rawValue, [.option, .shift, .command]); waitPath([expected], "⌥⇧⌘↑ opens the previous unread session")
        // Toggles are state-verified through their accessibility values.
        let home = screen.buttons["toggleHome"], review = screen.buttons["toggleReview"]
        waitValue(home, "open")
        key("\\", .command); waitValue(home, "closed")
        key("\\", .command); waitValue(home, "open")
        waitValue(review, "closed")
        key("r", [.command, .shift]); waitValue(review, "open")
        screenshot("workspace-review-open")
        key("r", [.command, .shift]); waitValue(review, "closed")
        // ⌘N starts a new session in this window.
        key("n", .command); waitPath([], "⌘N clears the window's session for New session")
        // A system New Window would take a moment to connect, so the count is watched for a while.
        for _ in 0..<10 {
            XCTAssertEqual(inventory().windows.count, 1, "⌘N is New session, not a system New Window")
            try await Task.sleep(for: .milliseconds(300))
        }
        // The switcher with the keyboard: open, type, move and open the active entry.
        key("k", .command)
        let search = app.textFields["paletteSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        waitForKeyboard(shown: true)
        screenshot("palette")
        search.typeText("Workspace")
        let sessionRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "palette-session:"))
        XCTAssertTrue(sessionRows.element(boundBy: 2).waitForExistence(timeout: 5), "The three new sessions match")
        let active = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "palette-session:")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 5), "The first result is active")
        XCTAssertEqual(active.identifier, sessionRows.element(boundBy: 0).identifier)
        key(XCUIKeyboardKey.downArrow.rawValue); key(XCUIKeyboardKey.downArrow.rawValue); key(XCUIKeyboardKey.upArrow.rawValue)
        let second = sessionRows.element(boundBy: 1).identifier
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND selected == true", second)).firstMatch.waitForExistence(timeout: 5), "↓ ↓ ↑ makes the second result active")
        let target = String(second.split(separator: ":").last ?? "")
        // With the simulator's software keyboard up, XCUITest delivers Return to a text field only as typed text, which
        // reaches the field's delegate as a hardware Return does. Escape cannot reach a focused text field here at all:
        // the field's keys are unit tests and a device check.
        waitForKeyboard(shown: true)
        search.typeText("\n")
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        waitPath([target], "Return opens the active entry")
        waitForKeyboard(shown: false)
        key("k", .command); XCTAssertTrue(search.waitForExistence(timeout: 5))
        waitForKeyboard(shown: true)
        // A tap on the dimmed window beside the switcher closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.3)).tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5), "A tap outside closes the switcher")
        waitPath([target], "Closing it changes nothing")
        // Every navigation command ran once per press.
        for (id, count) in ["menu.session.1": 1, "menu.session.2": 1, "menu.session.next": 2, "menu.session.previous": 1, "menu.session.next.unseen": 1, "menu.session.previous.unseen": 1,
                            "menu.sidebar.toggle": 2, "menu.review.toggle": 2, "menu.session.new": 1, "menu.command.palette": 2] {
            waitTrace(id, count: count)
        }
    }

    @MainActor func testMenuComposerCommands() async throws {
        executionTimeAllowance = 300
        let ids = try await setup("-menu-composer", sessions: ["Composer menu", "Composer elsewhere"])
        row(ids[0]).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        // The composer's commands are on the menu before their states are checked.
        waitEnabled("model.choose", true)
        waitEnabled("prompt.submit", false); waitEnabled("session.stop", false)
        // Send. XCUITest on this simulator delivers no Return chord, neither to the menu bar (it enables Send and
        // nothing is dispatched) nor to a focused text view, so ⌘↩ itself is a device check and the editor's Return,
        // ⌘↩ and Escape are unit tests. Here both sessions hold a draft, so their composers look the same to the menu;
        // the switcher runs the menu's Send through the same router, and it sends the draft of the session on screen.
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "menu-send", "script": ["calls": [
            ["deltas": [["text": "Sent from the other session."]]], ["deltas": [["text": "Sent from the switcher."]]]]]], mock: true)
        editor.tap(); editor.typeText("Send from the switcher")
        // Through the switcher: with the keyboard up, a long Home list can keep the row out of reach.
        func openFromSwitcher(_ id: String, _ title: String) {
            key("k", .command)
            let search = app.textFields["paletteSearch"]
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.typeText(title)
            let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "palette-session:", ":" + id)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        }
        func sendFromSwitcher(_ count: Int) {
            waitEnabled("prompt.submit", true)
            key("k", .command)
            let search = app.textFields["paletteSearch"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.typeText("Send")
            XCTAssertTrue(app.buttons["palette-command:prompt.submit"].waitForExistence(timeout: 5), "The switcher lists Send while the menu enables it")
            search.typeText("\n")
            XCTAssertTrue(search.waitForNonExistence(timeout: 5))
            waitTrace("palette.prompt.submit", count: count)
        }
        func prompts(_ id: String, _ text: String) async throws -> Int {
            let messages = try await api("/api/session/\(id)/message?limit=50&order=asc")
            return (messages["data"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "user" && ($0["text"] as? String) == text }.count
        }
        openFromSwitcher(ids[1], "Composer elsewhere"); waitPath([ids[1]], "The other session opens")
        editor.tap(); editor.typeText("Send from the other session")
        sendFromSwitcher(1)
        _ = try await api("/api/experimental/session/\(ids[1])/wait", method: "POST")
        let sentHere = try await prompts(ids[1], "Send from the other session")
        let sentThere = try await prompts(ids[0], "Send from the switcher")
        XCTAssertEqual(sentHere, 1, "Send acts on the session on screen")
        XCTAssertEqual(sentThere, 0, "The first session keeps its draft")
        openFromSwitcher(ids[0], "Composer menu"); waitPath([ids[0]], "The draft's session opens again")
        waitValue(editor, "Send from the switcher")
        sendFromSwitcher(2)
        _ = try await api("/api/experimental/session/\(ids[0])/wait", method: "POST")
        let sent = try await prompts(ids[0], "Send from the switcher")
        XCTAssertEqual(sent, 1, "One command sends one prompt")
        XCTAssertEqual(trace()["key.return"] ?? 0, 0, "Sending is not also the editor's Return")
        waitEnabled("prompt.submit", false)
        // ⌘. stops the session on screen once, and is not also Escape: with both sessions running, it stops the other
        // session's run first, then this one's.
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "menu-stop", "script": ["calls": [
            ["deltas": [["text": "Holding."]], "waitForAbort": true], ["deltas": [["text": "Holding too."]], "waitForAbort": true]]]], mock: true)
        _ = try await api("/api/session/\(ids[0])/prompt", method: "POST", body: ["text": "Hold until stopped."])
        _ = try await api("/api/session/\(ids[1])/prompt", method: "POST", body: ["text": "Hold this one too."])
        waitEnabled("session.stop", true, timeout: 20)
        openFromSwitcher(ids[1], "Composer elsewhere"); waitPath([ids[1]], "The other running session opens")
        waitEnabled("session.stop", true, timeout: 20)
        key(".", .command)
        waitTrace("menu.session.stop", count: 1)
        waitEnabled("session.stop", false, timeout: 20)
        openFromSwitcher(ids[0], "Composer menu"); waitPath([ids[0]], "The first session opens again")
        waitEnabled("session.stop", true, timeout: 20)
        key(".", .command)
        waitTrace("menu.session.stop", count: 2)
        waitEnabled("session.stop", false, timeout: 20)
        XCTAssertEqual(trace()["key.escape"] ?? 0, 0, "⌘. is not also Escape")
        // ⌘' opens the model picker; ⇧⌘D cycles the variant of a model that has them; ⌘U opens Add files.
        key("'", .command)
        let all = app.switches["Show all models"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        if all.value as? String != "1" { all.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        waitValue(all, "1")
        let vision = app.buttons["model-mock:mock-vision"].firstMatch
        XCTAssertTrue(vision.waitForExistence(timeout: 5)); vision.tap()
        let variant = app.buttons["composerVariant"]
        XCTAssertTrue(variant.waitForExistence(timeout: 5))
        let before = variant.value as? String ?? ""
        waitEnabled("model.variant.cycle", true)
        key("d", [.command, .shift])
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: variant)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "⇧⌘D changes the variant")
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Nothing to cancel before ⌘U")
        key("u", .command)
        waitTrace("menu.file.attach", count: 1)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "⌘U opens Add files")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10), "Add files closes")
        screenshot("workspace-composer-commands")
        for (id, count) in ["menu.model.choose": 1, "menu.model.variant.cycle": 1] { waitTrace(id, count: count) }
    }

    @MainActor func testReviewNextApproval() async throws {
        executionTimeAllowance = 240
        let ids = try await setup("-menu-approval", sessions: ["Approval elsewhere", "Open session"])
        row(ids[1]).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        _ = try await api("/admin/scenario", method: "POST", body: ["name": "menu-approval", "script": ["calls": [
            ["tools": [["name": "shell", "arguments": ["command": "printf 'menu-approval\\n'"]]]], ["deltas": [["text": "Approval done."]]]]]], mock: true)
        let created = try await api("/api/session", method: "POST", body: ["title": "Needs approval", "location": ["directory": try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])],
            "model": ["providerID": "mock", "id": "mock-1"], "permissions": [["action": "shell", "resource": "*", "effect": "ask"]]])
        let pending = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        _ = try await api("/api/session/\(pending)/prompt", method: "POST", body: ["text": "Ask for approval."])
        // The newest request comes first in Home's Needs you, before the fixture's older requests.
        waitEnabled("permissions.next", true, timeout: 20)
        let needsYou = Date().addingTimeInterval(20)
        while Date() < needsYou && homeOrder().first != pending { try await Task.sleep(for: .milliseconds(300)) }
        key("a", [.command, .shift])
        waitInventory("⇧⌘A opens the session that needs approval") { $0.current?.path.first == pending }
        let allow = app.buttons["allowOnce"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "The permission's full review is presented")
        screenshot("workspace-next-approval")
        waitTrace("menu.permissions.next", count: 1)
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 10), "The reply closes the review")
    }

    @MainActor func testTwoWindows() async throws {
        executionTimeAllowance = 360
        let ids = try await setup("-windows", sessions: ["Window A", "Window B", "Window C"])
        row(ids[0]).tap()
        waitPath([ids[0]], "A opens in the first window")
        let server = serverID()
        let first = inventory().this
        screen.buttons["toggleReview"].tap(); waitValue(screen.buttons["toggleReview"], "open")
        // Open in New Window from B's context menu.
        let rowB = row(ids[1])
        rowB.press(forDuration: 1.2)
        let open = app.buttons["Open in New Window"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let two = waitInventory(timeout: 20, "A second window opens") { $0.windows.count == 2 }
        // What XCUITest sees in the simulator's current multitasking mode, recorded as found.
        let inventories = app.descendants(matching: .any).matching(identifier: "windowInventory").allElementsBoundByIndex
        var probe = "app.windows.count=\(app.windows.count)\n"
        for (index, window) in app.windows.allElementsBoundByIndex.enumerated() { probe += "window[\(index)] frame=\(window.frame) hittable=\(window.isHittable)\n" }
        probe += "inventory elements=\(inventories.count)\n" + inventories.map { ($0.value as? String ?? "") + "\n---" }.joined(separator: "\n")
        note("finding-windows", probe)
        screenshot("windows-second")
        let second = try XCTUnwrap(two.windows.first { $0.id != first }?.id)
        XCTAssertEqual(two.windows.first { $0.id == second }?.path, [ids[1]], "The new window shows B")
        XCTAssertEqual(two.windows.first { $0.id == first }?.path, [ids[0]], "The first window keeps A")
        // The new window navigates on its own; the first keeps its session.
        if inventory().this == second {
            row(ids[2]).tap()
            waitInventory("The second window navigates to C") { $0.windows.first { $0.id == second }?.path == [ids[2]] }
            XCTAssertEqual(inventory().windows.first { $0.id == first }?.path, [ids[0]])
            // Opening A from Home here brings the first window forward instead of a second copy.
            row(ids[0]).tap()
            waitInventory("The first window comes forward") { $0.key?.id == first && $0.windows.count == 2 }
            XCTAssertEqual(inventory().windows.first { $0.id == second }?.path, [ids[2]], "The second window stays on C")
            // A link goes to the window showing its session: with C's window in front, a link to A brings A's back.
            // The system opens it in the running app; XCUIApplication.open would relaunch the app.
            row(ids[2]).tap()
            waitInventory("Opening C from Home brings its window forward") { $0.key?.id == second && $0.windows.count == 2 }
            XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "opencodeios://server/" + server + "/session/" + ids[0])))
            waitInventory("A link to A goes to the window showing A") { $0.windows.count == 2 && $0.key?.id == first && $0.key?.path == [ids[0]] }
            XCTAssertEqual(inventory().windows.first { $0.id == second }?.path, [ids[2]], "The other window keeps its session")
        } else {
            XCTFail("After Open in New Window the window on screen is \(inventory().this), not the new one")
        }
        // Both windows survive a relaunch, each with its own state. iPadOS may reconnect only the visible window; the
        // other stays in the app switcher until it comes forward, which opening its session from Home does.
        let before = inventory().windows
        app.terminate(); app.launch()
        let restored = waitInventory(timeout: 30, "The visible window restores its session") { value in
            value.current.map { window in before.contains { $0.path == window.path } } ?? false
        }
        // Scenes are checked by their root sessions: a scene an earlier run left in the app switcher may be listed too.
        let scenes = { (self.screen.descendants(matching: .any)["sceneInventory"].firstMatch.value as? String ?? "").split(separator: "\n").map(String.init) }
        func keeps(_ root: String?, _ lines: [String]) -> Bool { lines.contains { root != nil && $0.hasSuffix("root=" + (root ?? "")) } }
        func waitScenes(_ description: String, _ predicate: ([String]) -> Bool) {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline && !predicate(scenes()) { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
            XCTAssertTrue(predicate(scenes()), description + ": \(scenes())")
        }
        waitScenes("iPadOS keeps both windows") { lines in before.allSatisfy { keeps($0.path.first, lines) } }
        note("finding-restored", "connected=\(restored.windows.count)\n" + restored.windows.map { "key=\($0.key) path=\($0.path)" }.joined(separator: "\n") + "\nscenes:\n" + scenes().joined(separator: "\n"))
        if restored.current?.path == [ids[0]] { waitValue(screen.buttons["toggleReview"], "open") }
        if let other = before.first(where: { $0.path != restored.current?.path }), let root = other.path.first {
            if restored.windows.count < 2 {
                showHome()
                row(root).tap()
            }
            waitInventory(timeout: 20, "The other window comes back with its own session") { value in
                value.windows.count == 2 && value.windows.contains { $0.path == other.path }
            }
            // A's window also kept its open review panel; check it once that window is back in front.
            if root == ids[0] {
                if inventory().key?.path != [ids[0]] { showHome(); row(ids[0]).tap() }
                waitInventory("A's window is in front") { $0.key?.path == [ids[0]] }
                waitValue(screen.buttons["toggleReview"], "open")
            }
        }
        // ⇧⌘N opens a new window at New session; the relaunch above was a new launch. Closing a window is not driven
        // here: iPadOS on this simulator accepts a scene's destruction request and keeps the scene, so the coordinator's
        // unit tests and a device check cover it.
        let shown = inventory().windows.count
        primeKeyboard()
        key("n", [.command, .shift])
        waitInventory(timeout: 20, "⇧⌘N opens a window") { $0.windows.count == shown + 1 && $0.windows.contains { $0.path.isEmpty } }
        waitTrace("menu.window.new", count: 1)
    }

    @MainActor func testDragFileIntoComposer() async throws {
        executionTimeAllowance = 240
        let ids = try await setup("-drag", sessions: ["Drag and drop"])
        row(ids[0]).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.buttons["toggleReview"].tap(); waitValue(app.buttons["toggleReview"], "open")
        app.buttons["Files"].firstMatch.tap()
        let file = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier ENDSWITH %@", "fileEntry-", "/")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        let name = String(file.identifier.dropFirst("fileEntry-".count).split(separator: "/").last ?? "")
        file.press(forDuration: 1.2, thenDragTo: editor)
        let mentioned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "@" + name), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [mentioned], timeout: 10), .completed, "Dropping a Files row inserts an @file mention")
        screenshot("workspace-drop-mention")
    }
}

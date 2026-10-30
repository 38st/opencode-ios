import Foundation
import XCTest
import UIKit

/// Server terminals against the sandbox: full-screen programs, resuming without lost output, resizing, and Run a command.
/// The DEBUG app exposes, under a `ui-` test identity only, the terminal's visible rows (`terminalScreen`), the size it
/// sent (`terminalSize`) and the `OCSEQ-<n>` marker lines of its whole buffer (`terminalSequence`).
nonisolated final class TerminalSmokeTests: SmokeTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var ipad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    @MainActor private var screenProbe: XCUIElement { app.descendants(matching: .any)["terminalScreen"].firstMatch }
    @MainActor private var terminalText: String { screenProbe.value as? String ?? "" }
    @MainActor private var size: String { app.descendants(matching: .any)["terminalSize"].firstMatch.value as? String ?? "" }
    @MainActor private var sequence: [String: String] {
        let value = app.descendants(matching: .any)["terminalSequence"].firstMatch.value as? String ?? ""
        return Dictionary(value.split(separator: " ").compactMap { field in
            let parts = field.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }, uniquingKeysWith: { _, last in last })
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = (ipad ? "ipad-" : "") + name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text); attachment.name = (ipad ? "ipad-" : "") + name; attachment.lifetime = .keepAlways; add(attachment)
    }

    /// A paired server and a session in the sandbox project, open, with its terminals on screen.
    @MainActor private func setup(_ suffix: String) async throws -> String {
        continueAfterFailure = false
        try launchFreshApp(suffix: suffix)
        app.buttons["addFirstServer"].tap()
        XCTAssertTrue(app.buttons["Use password"].waitForExistence(timeout: 5)); app.buttons["Use password"].tap()
        XCTAssertTrue(app.textFields["serverName"].waitForExistence(timeout: 5))
        app.textFields["serverName"].tap(); app.textFields["serverName"].typeText("Terminal sandbox")
        app.textFields["serverURL"].tap(); app.textFields["serverURL"].typeText(try XCTUnwrap(env["OPENCODE_UI_URL"]))
        app.secureTextFields["serverPassword"].tap(); app.secureTextFields["serverPassword"].typeText(try XCTUnwrap(env["OPENCODE_UI_PASSWORD"]))
        connect(explainingLocalNetwork: true); waitForConnections()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForNonExistence(timeout: 10))
        if ipad { rotate(to: .landscapeLeft) }
        try await clearTerminals()
        let created = try await api("/api/session", method: "POST", body: ["title": "Terminal " + suffix, "location": ["directory": try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])]])
        let id = try XCTUnwrap((created["data"] as? [String: Any])?["id"] as? String)
        openSession(id)
        openTerminals()
        return id
    }
    /// Terminals outlive a test on the shared sandbox server, and titles count up from the lowest free number, so each
    /// test starts with none.
    @MainActor private func clearTerminals() async throws {
        let directory = try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"])
        let location = "location%5Bdirectory%5D=" + (directory.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        for case let pty as [String: Any] in try await api("/api/pty?" + location)["data"] as? [Any] ?? [] {
            if let id = pty["id"] as? String { _ = try await api("/api/pty/\(id)?" + location, method: "DELETE") }
        }
    }
    @MainActor private func openSession(_ id: String) {
        setHome(open: true)
        let row = homeSessionRow(id); XCTAssertTrue(row.isHittable); row.tap()
        XCTAssertTrue(app.textViews["promptEditor"].waitForExistence(timeout: 10))
        setHome(open: false)
    }
    /// iPad: the review panel's Terminal tab. iPhone: the session menu's Terminals screen.
    @MainActor private func openTerminals() {
        if ipad {
            let review = app.buttons["toggleReview"]
            XCTAssertTrue(review.waitForExistence(timeout: 5))
            if review.value as? String != "open" { review.tap() }
            let tab = app.buttons["Terminal"].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
        } else {
            let menu = app.buttons["timelineDetail"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5)); menu.tap()
            let item = app.buttons["openTerminals"]
            XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
        }
        XCTAssertTrue(app.buttons["newTerminal"].waitForExistence(timeout: 10), "The terminal list")
    }
    /// Starts a terminal with the server's shell and opens it, focused, at its prompt.
    @MainActor private func newTerminal(_ title: String) {
        app.buttons["newTerminal"].tap()
        let shell = app.buttons["newTerminalDefault"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5)); shell.tap()
        openTerminal(title)
    }
    /// A terminal just started opens by itself; another opens from its row.
    @MainActor private func openTerminal(_ title: String) {
        if !screenProbe.waitForExistence(timeout: 3) {
            let row = app.buttons["terminalRow-" + title]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(title) is listed"); row.tap()
        }
        XCTAssertTrue(screenProbe.waitForExistence(timeout: 10))
        let terminal = app.descendants(matching: .any)["terminal"].firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 5)); terminal.tap()
        waitScreen("the shell's prompt") { $0.contains("$ ") }
    }
    /// Types into the focused terminal; a newline is Return.
    @MainActor private func type(_ text: String) { app.typeText(text) }
    @MainActor private func screenShows(within timeout: TimeInterval, _ predicate: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline { if predicate(terminalText) { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        return false
    }
    @MainActor private func waitScreen(_ description: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line,
                                       _ predicate: (String) -> Bool) {
        if screenShows(within: timeout, predicate) { return }
        note("terminal-screen-timeout", terminalText)
        XCTFail("Waiting for \(description). Screen:\n\(terminalText)", file: file, line: line)
    }
    @MainActor private func waitPrompt(after marker: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        waitScreen("the prompt after \(marker)", timeout: timeout, file: file, line: line) { screen in
            guard let range = screen.range(of: marker, options: .backwards) else { return false }
            return screen[range.upperBound...].contains("$ ")
        }
    }
    /// A file in the sandbox project, as the server's fs.read returns it.
    @MainActor private func serverFile(_ name: String) async throws -> String {
        var components = try XCTUnwrap(URLComponents(string: try XCTUnwrap(env["OPENCODE_UI_URL"]) + "/api/fs/read/" + name))
        components.queryItems = [.init(name: "location[directory]", value: try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"]))]
        var request = URLRequest(url: try XCTUnwrap(components.url))
        let password = try XCTUnwrap(env["OPENCODE_UI_PASSWORD"])
        request.setValue("Basic " + Data(("opencode:" + password).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "fs.read \(name)")
        return String(decoding: data, as: UTF8.self)
    }
    /// `stty size` prints rows and columns; the terminal reports the columns and rows it sent the server.
    @MainActor private func checkSize(_ label: String) {
        let marker = "stty-\(label)"
        type("clear; echo \(marker); stty size\n")
        waitPrompt(after: marker)
        compareSize(label, marker: marker)
    }
    @MainActor private func compareSize(_ label: String, marker: String) {
        let lines = terminalText.components(separatedBy: "\n")
        let index = lines.lastIndex { $0.contains(marker) && !$0.contains("echo") }
        let reported = index.flatMap { lines.indices.contains($0 + 1) ? lines[$0 + 1].trimmingCharacters(in: .whitespaces) : nil } ?? ""
        let numbers = reported.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2, "stty size printed \(reported)")
        XCTAssertEqual(numbers.count == 2 ? "\(numbers[1])x\(numbers[0])" : "", size, "stty size matches the terminal (\(label))")
        note("terminal-size-" + label, "stty: \(reported); terminal: \(size)")
    }

    @MainActor func testTerminalPrograms() async throws {
        executionTimeAllowance = 600
        _ = try await setup("programs")
        // A new file each attempt, so a retry finds vim's [New] again.
        let file = "m7-vim-\(ipad ? "ipad" : "iphone")-\(Int(Date().timeIntervalSince1970)).txt", text = "Edited in vim on the \(ipad ? "iPad" : "iPhone")"
        newTerminal("Terminal 1")
        screenshot("terminal-shell")
        // vim: insert, the key bar's Escape, write and quit; the server's file changes.
        type("vim \(file)\n")
        waitScreen("vim") { $0.contains("[New]") }
        type("i" + text)
        waitScreen("insert mode") { $0.contains("-- INSERT --") }
        let escape = app.buttons["terminalKey-Escape"]
        if escape.waitForExistence(timeout: 5) { escape.tap() } else {
            // A hardware keyboard replaces the key bar on iPad. The simulator can drop a first key or chord, so Ctrl-[
            // follows when Escape did not arrive.
            XCTAssertTrue(ipad, "The key bar's Escape")
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            if !screenShows(within: 3, { !$0.contains("-- INSERT --") }) { app.typeKey("[", modifierFlags: .control) }
        }
        waitScreen("normal mode") { !$0.contains("-- INSERT --") }
        screenshot("terminal-vim")
        type(":wq\n")
        waitPrompt(after: "vim \(file)")
        let written = try await serverFile(file)
        XCTAssertEqual(written, text + "\n", "vim wrote the file on the server")
        // A program that redraws the whole screen live, then q. The sandbox cannot run top: macOS refuses a sandboxed
        // process the set-user-ID /usr/bin/top ("Operation not permitted"), so nettop stands in for it.
        type("nettop -P\n")
        // At a phone's width nettop shows only its `name.pid` column.
        waitScreen("nettop") { screen in screen.split(separator: "\n").filter { $0.wholeMatch(of: /\S.*\.\d+\s*/) != nil }.count >= 3 }
        screenshot("terminal-top")
        type("q")
        waitPrompt(after: "nettop -P")
        // less pages with the space bar.
        type("seq 1 400 | less\n")
        waitScreen("less") { $0.contains("\n1\n") || $0.hasPrefix("1\n") }
        let rows = Int(size.split(separator: "x").last ?? "") ?? 0
        XCTAssertGreaterThan(rows, 0, "The terminal reports its rows")
        let nextPage: (String) -> Bool = { screen in screen.components(separatedBy: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.contains { $0 > rows } }
        // The iPad simulator sometimes drops a key typed right after less draws its first page; the page did not move
        // then, so the key is sent again (a second space past a page that did move is never sent).
        type(" ")
        if !screenShows(within: 5, nextPage) { note("terminal-key-resent", terminalText); type(" ") }
        waitScreen("the next page", nextPage)
        type("q")
        waitPrompt(after: "| less")
        // A new size reaches the server: on iPad, the window's width with Home shown. The iPhone simulator neither
        // rotates the app under XCUITest nor keeps the software keyboard away reliably, so iPhone resizing is a device
        // check; the debounced size requests themselves are unit-tested.
        checkSize("before")
        guard ipad else { return }
        let before = size
        setHome(open: true)
        waitForNewSize(than: before)
        app.descendants(matching: .any)["terminal"].firstMatch.tap()
        checkSize("after")
        setHome(open: false)
    }
    @MainActor private func waitForNewSize(than before: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = Date().addingTimeInterval(10)
        while Date() < changed && size == before { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        XCTAssertNotEqual(size, before, "The terminal has a new size", file: file, line: line)
    }

    /// Numbered lines keep printing while the app is in the background and while it is not running; every line arrives
    /// once and in order.
    @MainActor func testResumeLosesNoOutput() async throws {
        executionTimeAllowance = 600
        let session = try await setup("resume")
        newTerminal("Terminal 1")
        type("for i in $(seq 1 1500); do echo OCSEQ-$i; sleep 0.008; done; echo OCSEQ-END-$((1+1))\n")
        let started = Date().addingTimeInterval(20)
        while Date() < started && (Int(sequence["count"] ?? "") ?? 0) < 100 { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertGreaterThan(Int(sequence["count"] ?? "") ?? 0, 99, "Output is arriving")
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(6))
        app.activate()
        waitScreen("the end of the background run", timeout: 60) { $0.contains("OCSEQ-END-2") }
        let background = sequence
        note("terminal-resume-background", background.description)
        XCTAssertEqual(background["first"], "1"); XCTAssertEqual(background["last"], "1500")
        XCTAssertEqual(background["missing"], "0"); XCTAssertEqual(background["duplicates"], "0"); XCTAssertEqual(background["rising"], "true")
        XCTAssertFalse(app.descendants(matching: .any)["terminalGap"].exists, "Nothing was lost")
        screenshot("terminal-resumed")
        // Killed in the background, relaunched: the saved screen and cursor continue the same sequence.
        type("for i in $(seq 1501 3000); do echo OCSEQ-$i; sleep 0.008; done; echo OCSEQ-END-$((1+2))\n")
        let second = Date().addingTimeInterval(20)
        while Date() < second && (Int(sequence["last"] ?? "") ?? 0) < 1_600 { try await Task.sleep(for: .milliseconds(200)) }
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(2))
        app.terminate()
        try await Task.sleep(for: .seconds(3))
        app.launch()
        openSession(session)
        openTerminals()
        openTerminal("Terminal 1")
        waitScreen("the end of the run after the relaunch", timeout: 60) { $0.contains("OCSEQ-END-3") }
        let relaunched = sequence
        note("terminal-resume-relaunch", relaunched.description)
        XCTAssertEqual(relaunched["last"], "3000"); XCTAssertEqual(relaunched["missing"], "0")
        XCTAssertEqual(relaunched["duplicates"], "0"); XCTAssertEqual(relaunched["rising"], "true")
        XCTAssertFalse(app.descendants(matching: .any)["terminalGap"].exists, "Nothing was lost")
    }

    @MainActor func testRunACommandAndStopIt() async throws {
        executionTimeAllowance = 300
        _ = try await setup("run")
        app.buttons["terminalListActions"].tap()
        let run = app.buttons["runCommand"]
        XCTAssertTrue(run.waitForExistence(timeout: 5)); run.tap()
        let field = app.textFields["runCommandField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let output = app.descendants(matching: .any)["shellOutputScreen"].firstMatch
        field.tap(); field.typeText("for i in 1 2 3; do echo run-$i; sleep 1; done")
        app.buttons["runCommandRun"].tap()
        let ended = app.descendants(matching: .any)["runCommandEnded"].firstMatch
        XCTAssertTrue(ended.waitForExistence(timeout: 30), "The command finishes")
        XCTAssertTrue((output.value as? String ?? "").contains("run-3"), "Its output: \(output.value as? String ?? "")")
        XCTAssertEqual(ended.label, "Exited with code 0")
        screenshot("terminal-run")
        field.tap(); field.typeText("echo started; sleep 60; echo never")
        app.buttons["runCommandRun"].tap()
        let stop = app.buttons["runCommandStop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "A running command can be stopped")
        let printed = Date().addingTimeInterval(10)
        while Date() < printed && !(output.value as? String ?? "").contains("started") { try await Task.sleep(for: .milliseconds(250)) }
        XCTAssertTrue((output.value as? String ?? "").contains("started"), "The command printed before it was stopped")
        stop.tap()
        XCTAssertTrue(ended.waitForExistence(timeout: 10)); XCTAssertEqual(ended.label, "Stopped")
        let running = try await api("/api/shell?location%5Bdirectory%5D=" + (try XCTUnwrap(env["OPENCODE_UI_DIRECTORY"]).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
        XCTAssertEqual((running["data"] as? [Any])?.count, 0, "The server runs no command any more: \(running)")
        XCTAssertFalse((output.value as? String ?? "").contains("never"))
        app.buttons["runCommandDone"].tap()
    }
}

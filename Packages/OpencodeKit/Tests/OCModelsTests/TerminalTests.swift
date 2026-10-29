import Foundation
import Testing
import OCFoundation
@testable import OCModels

private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

@Test func controlSendsTheC0ByteXtermSends() {
    for (offset, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
        #expect(TerminalKeys.control(letter) == UInt8(offset + 1))
        #expect(TerminalKeys.control(Character(letter.uppercased())) == UInt8(offset + 1))
    }
    let specials: [(Character, UInt8)] = [("@", 0x00), (" ", 0x00), ("2", 0x00), ("`", 0x00), ("[", 0x1B), ("3", 0x1B), ("\\", 0x1C), ("|", 0x1C),
        ("4", 0x1C), ("]", 0x1D), ("5", 0x1D), ("^", 0x1E), ("~", 0x1E), ("6", 0x1E), ("_", 0x1F), ("/", 0x1F), ("-", 0x1F), ("7", 0x1F),
        ("?", 0x7F), ("8", 0x7F)]
    for (character, byte) in specials { #expect(TerminalKeys.control(character) == byte, "Ctrl-\(character)") }
    for character: Character in ["1", "9", "0", "é", "😀", "."] { #expect(TerminalKeys.control(character) == nil, "Ctrl-\(character) is unchanged") }
}

@Test func keyBarBytesWithModifiers() {
    #expect(TerminalKeys.encode(.escape) == [0x1B])
    #expect(TerminalKeys.encode(.escape, modifiers: .alt) == [0x1B, 0x1B])
    #expect(TerminalKeys.encode(.tab) == [0x09])
    #expect(TerminalKeys.encode(.text("|")) == bytes("|"))
    #expect(TerminalKeys.encode(.text("c"), modifiers: .control) == [0x03])
    #expect(TerminalKeys.encode(.text("~"), modifiers: .control) == [0x1E])
    #expect(TerminalKeys.encode(.text("b"), modifiers: .alt) == [0x1B] + bytes("b"))
    #expect(TerminalKeys.encode(.text("x"), modifiers: [.control, .alt]) == [0x1B, 0x18])
    // Text typed while a modifier is latched modifies only its first character.
    #expect(TerminalKeys.encode(.text("cd"), modifiers: .control) == [0x03] + bytes("d"))
    #expect(TerminalKeys.encode(.text("é"), modifiers: .control) == bytes("é"))
}

@Test func arrowsFollowApplicationCursorMode() {
    let finals: [(TerminalKey, String)] = [(.up, "A"), (.down, "B"), (.right, "C"), (.left, "D")]
    for (key, final) in finals {
        #expect(TerminalKeys.encode(key) == bytes("\u{1B}[" + final))
        #expect(TerminalKeys.encode(key, applicationCursor: true) == bytes("\u{1B}O" + final))
        // Modified cursor keys use CSI 1;m in both modes.
        for application in [false, true] {
            #expect(TerminalKeys.encode(key, modifiers: .control, applicationCursor: application) == bytes("\u{1B}[1;5" + final))
            #expect(TerminalKeys.encode(key, modifiers: .alt, applicationCursor: application) == bytes("\u{1B}[1;3" + final))
            #expect(TerminalKeys.encode(key, modifiers: [.control, .alt], applicationCursor: application) == bytes("\u{1B}[1;7" + final))
        }
    }
}

@Test func stickyModifiersLatchForOneKey() {
    var latch = TerminalModifierLatch()
    latch.toggle(.control)
    #expect(latch.latched == .control)
    latch.toggle(.alt)
    #expect(latch.consume() == [.control, .alt])
    #expect(latch.latched.isEmpty)
    #expect(latch.consume().isEmpty)
    latch.toggle(.control); latch.toggle(.control)
    #expect(latch.latched.isEmpty, "A second tap releases the latch")
}

@Test func cursorCountsUTF16CodeUnitsLikeTheServer() {
    // JavaScript's String.length: emoji and other astral characters are 2, CJK 1, a combining mark 1 more.
    let cases: [(String, Int)] = [("a", 1), ("😀", 2), ("漢字", 2), ("e\u{301}", 2), ("👨‍👩‍👧", 8), ("\u{FFFD}", 1), ("\r\n", 2), ("é", 1)]
    for (text, units) in cases { #expect(text.utf16.count == units, "\(text.debugDescription)") }
    var link = TerminalLink()
    _ = link.start(cursor: 10, restoredScreen: true); _ = link.opened(); _ = link.control(cursor: 10)
    #expect(link.text("😀漢e\u{301}\r\n") == [.feed("😀漢e\u{301}\r\n")])
    #expect(link.cursor == 10 + 2 + 1 + 2 + 2)
    _ = link.text("👨‍👩‍👧")
    #expect(link.cursor == 25)
}

@Test func freshTerminalReplaysFromZero() {
    var link = TerminalLink()
    #expect(link.start(cursor: nil, restoredScreen: false) == [.connect(seek: 0)])
    #expect(link.opened() == [.pushSize])
    #expect(link.text("$ ").isEmpty, "Replay waits for the control frame")
    #expect(link.control(cursor: 2) == [.replay("$ "), .persist])
    #expect(link.phase == .live && link.cursor == 2)
}

@Test func firstConnectionReportsTrimmedOutput() {
    var link = TerminalLink()
    _ = link.start(cursor: nil, restoredScreen: false); _ = link.opened()
    _ = link.text(String(repeating: "x", count: 10))
    #expect(link.control(cursor: 30) == [.reset, .replay(String(repeating: "x", count: 10)), .gap(.trimmed(units: 20)), .persist])
}

@Test func resumeFromTheSavedCursorWithoutLoss() {
    var link = TerminalLink()
    #expect(link.start(cursor: 100, restoredScreen: true) == [.connect(seek: 100)])
    _ = link.opened(); _ = link.text("12345")
    #expect(link.control(cursor: 105) == [.replay("12345"), .persist])
}

@Test func bufferThatNoLongerReachesTheCursorSaysHowMuchWasLost() {
    // The server keeps 2 MiB; a cursor older than its start replays from the start and the control frame shows the gap.
    var link = TerminalLink()
    _ = link.start(cursor: 100, restoredScreen: true); _ = link.opened()
    let replay = String(repeating: "y", count: 2_097_152)
    _ = link.text(replay)
    let end = 3_000_000
    #expect(link.control(cursor: end) == [.reset, .replay(replay), .gap(.lost(units: end - 100 - 2_097_152)), .persist])
    #expect(link.cursor == end)
}

@Test func restoredScreenWithoutCursorTailsFromNow() {
    var link = TerminalLink()
    #expect(link.start(cursor: nil, restoredScreen: true) == [.connect(seek: -1)])
    _ = link.opened()
    #expect(link.control(cursor: 500) == [.gap(.skipped), .persist])
    #expect(link.cursor == 500)
    var invalid = TerminalLink()
    #expect(invalid.start(cursor: -5, restoredScreen: true) == [.connect(seek: -1)], "A negative saved cursor counts as none")
}

@Test func serverBehindTheCursorRedraws() {
    var link = TerminalLink()
    _ = link.start(cursor: 1_000, restoredScreen: true); _ = link.opened(); _ = link.text("ab")
    #expect(link.control(cursor: 10) == [.reset, .replay("ab"), .gap(.positionReset), .persist])
}

@Test func normalCloseLooksBeforeReconnecting() {
    var link = TerminalLink()
    _ = link.start(cursor: nil, restoredScreen: false); _ = link.opened(); _ = link.control(cursor: 0)
    #expect(link.closed(code: 1000) == [.checkStatus])
    #expect(link.status(.exited(code: 3)) == [.persist], "Every byte arrived before a normal close")
    #expect(link.phase == .exited(code: 3))
    var removed = TerminalLink()
    _ = removed.start(cursor: nil, restoredScreen: false); _ = removed.opened(); _ = removed.control(cursor: 0)
    _ = removed.closed(code: 1000)
    #expect(removed.status(.gone) == [.forget])
    #expect(removed.phase == .gone)
}

@Test func close4404WaitsThenFindsTheExit() {
    var link = TerminalLink()
    _ = link.start(cursor: 40, restoredScreen: true)
    #expect(link.closed(code: 4404) == [.wait(.milliseconds(250))], "4404 arrives without the socket opening")
    #expect(link.waited() == [.checkStatus])
    #expect(link.status(.exited(code: 0)) == [.gap(.exitedWhileAway), .persist])
    #expect(link.phase == .exited(code: 0))
}

@Test func abnormalCloseBacksOffAndReconnectsFromTheCursor() {
    var link = TerminalLink()
    _ = link.start(cursor: 7, restoredScreen: true); _ = link.opened(); _ = link.control(cursor: 7); _ = link.text("abc")
    var delays: [Duration] = []
    for _ in 0..<6 {
        guard case .wait(let delay)? = link.closed(code: nil).first else { Issue.record("Expected a wait"); return }
        delays.append(delay)
        #expect(link.waited() == [.checkStatus])
        #expect(link.status(.running) == [.connect(seek: 10)])
    }
    #expect(delays == [250, 500, 1_000, 2_000, 4_000, 4_000].map { .milliseconds($0) })
    _ = link.opened()
    #expect(link.tries == 0, "A connection that opens resets the backoff")
    #expect(link.closed(code: nil) == [.wait(.milliseconds(250))])
    _ = link.waited()
    #expect(link.status(.unknown) == [.connect(seek: 10)], "An unreachable server is not a gone terminal")
}

@Test func goneTerminalIsForgotten() {
    var link = TerminalLink()
    _ = link.start(cursor: nil, restoredScreen: false)
    #expect(link.closed(code: nil, httpStatus: 404) == [.forget])
    #expect(link.phase == .gone)
    #expect(link.closed(code: 1000).isEmpty)
    var removed = TerminalLink()
    _ = removed.start(cursor: nil, restoredScreen: false); _ = removed.opened()
    #expect(removed.removed() == [.close, .forget])
}

@Test func socketLostMidReplayKeepsTheScreenAndCursor() {
    var link = TerminalLink()
    _ = link.start(cursor: 50, restoredScreen: true); _ = link.opened(); _ = link.text("abc")
    _ = link.closed(code: nil)
    #expect(link.cursor == 50 && link.seek == 50)
    _ = link.waited()
    #expect(link.status(.running) == [.connect(seek: 50)])
}

@Test func suspendSavesThenResumesFromTheCursor() {
    var link = TerminalLink()
    _ = link.start(cursor: nil, restoredScreen: false); _ = link.opened(); _ = link.control(cursor: 0); _ = link.text("hello")
    #expect(link.suspend() == [.persist, .close])
    #expect(link.closed(code: 1000).isEmpty, "Our own close is not a disconnection")
    #expect(link.resume() == [.connect(seek: 5)])
    var waiting = TerminalLink()
    _ = waiting.start(cursor: 1, restoredScreen: true); _ = waiting.closed(code: nil)
    #expect(waiting.retryNow() == [.checkStatus], "The server's connection coming back skips the wait")
}

@Test func exitedTerminalDoesNotConnect() {
    var link = TerminalLink()
    #expect(link.exited(code: 2, cursor: 9) == [.gap(.exitedWhileAway)])
    #expect(link.phase == .exited(code: 2) && link.cursor == 9)
    #expect(link.start(cursor: 9, restoredScreen: true).isEmpty)
}

@Test func shellOutputPaging() {
    var pager = ShellPager(running: true)
    #expect(pager.start() == .fetch(cursor: 0))
    #expect(pager.received(cursor: 65_536, size: 100_000) == .fetch(cursor: 65_536), "Catch up while the server holds more")
    #expect(pager.received(cursor: 100_000, size: 100_000) == .poll(after: .seconds(1)), "Poll each second while it runs")
    #expect(pager.received(cursor: 100_000, size: 100_500) == .fetch(cursor: 100_000))
    #expect(pager.received(cursor: 100_500, size: 100_500) == .poll(after: .seconds(1)))
    #expect(pager.exited() == .fetch(cursor: 100_500), "Read what is left once after the exit")
    #expect(pager.exited() == .done)
    #expect(pager.received(cursor: 100_600, size: 100_600) == .done)
    #expect(pager.received(cursor: 5, size: 100_600) == .done, "The cursor never moves back")
    #expect(pager.cursor == 100_600)
    var removed = ShellPager(running: true)
    #expect(removed.notFound() == .done)
    #expect(removed.missing && removed.start() == .done)
    #expect(ShellPager.terminalText("a\nb\r\nc") == "a\r\nb\r\nc")
}

@Test func terminalTitlesTakeTheLowestFreeNumber() {
    #expect(TerminalTitles.next(after: []) == "Terminal 1")
    #expect(TerminalTitles.next(after: ["Terminal 1", "Terminal 3"]) == "Terminal 2")
    #expect(TerminalTitles.next(after: ["Terminal 1", "Terminal 2", "Build"]) == "Terminal 3")
    #expect(TerminalTitles.next(after: ["Terminal x", "Terminal 0"]) == "Terminal 1")
}

@Test func ptyAndShellOptionsDecodeTolerantly() throws {
    let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"id":"pty_1","title":"Terminal 1","command":"/bin/bash","args":["-l"],"cwd":"/w","status":"exited","pid":4,"exitCode":3,"extra":true}"#.utf8))
    let pty = PtyInfo(raw: raw)
    #expect(pty.status == .exited && pty.exitCode == 3 && pty.commandLine == "bash -l" && pty.pid == 4)
    #expect(PtyInfo(raw: .object(["id": .string("pty_2"), "status": .string("paused")])).status == .unknown("paused"))
    let shells = try JSONDecoder().decode(LossyArray<ShellOption>.self, from: Data(#"[{"path":"/bin/zsh","name":"zsh","acceptable":true},{"path":"/usr/local/bin/fish","acceptable":false},7]"#.utf8))
    #expect(shells.values.map(\.name) == ["zsh", "fish"])
}

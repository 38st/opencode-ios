#if os(iOS)
import Testing
@testable import FeatureTerminal

/// The saved screen: what a new terminal replays to show the same screen, with no blank cells written out.
@MainActor @Suite struct TerminalSerializerTests {
    @Test func aSavedScreenRestoresTheSameScreen() throws {
        let source = SwiftTermEngine(session: nil, fontSize: 13, optionAsMeta: false)
        source.feed("$ make\r\n\u{1B}[1;31mFAIL\u{1B}[0m one\r\n\u{1B}[44m  \u{1B}[0m blue\r\n😀漢é wide\r\n" + String(repeating: "w", count: 100) + "\r\n$ ")
        let screen = try #require(source.snapshot(scrollback: 100))
        #expect(!screen.contains("  \r\n"), "Rows end at their last written or coloured cell")
        #expect(screen.contains("\u{1B}[0;44m  "), "A coloured blank cell is kept")
        let copy = SwiftTermEngine(session: nil, fontSize: 13, optionAsMeta: false)
        copy.restore(screen, cols: source.size.cols, rows: source.size.rows)
        #expect(copy.snapshot(scrollback: 100) == screen)
    }
    /// A device-attributes query in replayed or restored output is answered by nobody; the same query live is.
    @Test func repliesToReplayedQueriesAreNotSent() async throws {
        let engine = SwiftTermEngine(session: nil, fontSize: 13, optionAsMeta: false)
        var sent: [String] = []
        engine.forward = { sent.append(String(decoding: $0, as: UTF8.self)) }
        engine.replay("$ \u{1B}[c\u{1B}[6n")
        engine.restore("\u{1B}[>c", cols: 80, rows: 24)
        for _ in 0..<5 { await Task.yield(); try await Task.sleep(for: .milliseconds(20)) }
        #expect(sent.isEmpty, "Replies to replayed queries: \(sent)")
        engine.feed("\u{1B}[c")
        for _ in 0..<5 { await Task.yield(); try await Task.sleep(for: .milliseconds(20)) }
        #expect(sent.contains { $0.hasPrefix("\u{1B}[?") }, "A live query is answered")
    }
    @Test func theAlternateScreenAndModesComeBack() throws {
        let source = SwiftTermEngine(session: nil, fontSize: 13, optionAsMeta: false)
        source.feed("$ vim\r\n\u{1B}[?1049h\u{1B}[H\u{1B}[?1h\u{1B}=\u{1B}[?2004hfile text\r\n~")
        let screen = try #require(source.snapshot(scrollback: 100))
        let copy = SwiftTermEngine(session: nil, fontSize: 13, optionAsMeta: false)
        copy.restore(screen, cols: source.size.cols, rows: source.size.rows)
        #expect(copy.applicationCursor)
        #expect(copy.snapshot(scrollback: 100) == screen)
    }
}
#endif

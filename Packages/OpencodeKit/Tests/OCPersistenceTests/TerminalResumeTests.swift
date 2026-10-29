import Foundation
import Testing
@testable import OCPersistence

private func point(_ pty: String, server: String = "s", directory: String = "/w", cursor: Int = 7, screen: String = "\u{1B}[0mhello", updated: Date = Date()) -> TerminalResume {
    TerminalResume(serverID: server, ptyID: pty, directory: directory, cursor: cursor, cols: 80, rows: 24, screen: screen, updated: updated)
}

@Test func terminalResumeRoundTripsAndIsForgotten() async throws {
    let writer = try PersistenceWriter()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try await writer.saveTerminal(point("pty_1", updated: now))
    let loaded = try #require(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: now))
    #expect(loaded == point("pty_1", updated: now))
    try await writer.saveTerminal(point("pty_1", cursor: 9, updated: now))
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: now)?.cursor == 9, "A save replaces the point")
    try await writer.forgetTerminal(serverID: "s", ptyID: "pty_1")
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: now) == nil)
}

@Test func terminalPointsFollowTheServer() async throws {
    let writer = try PersistenceWriter()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for (pty, directory) in [("pty_1", "/w"), ("pty_2", "/w"), ("pty_3", "/other")] { try await writer.saveTerminal(point(pty, directory: directory, updated: now)) }
    try await writer.saveTerminal(point("pty_9", server: "t", updated: now))
    try await writer.forgetTerminals(serverID: "s", directory: "/w", keeping: ["pty_2"])
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: now) == nil, "The server no longer lists it")
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_2", now: now) != nil)
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_3", now: now) != nil, "Another location is untouched")
    try await writer.forgetTerminals(serverID: "s")
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_2", now: now) == nil)
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_3", now: now) == nil)
    #expect(try await writer.terminal(serverID: "t", ptyID: "pty_9", now: now) != nil, "Unpairing one server keeps another's")
}

@Test func terminalPointsExpireAndStayBounded() async throws {
    let writer = try PersistenceWriter()
    let saved = Date(timeIntervalSince1970: 1_800_000_000)
    try await writer.saveTerminal(point("pty_1", updated: saved))
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: saved.addingTimeInterval(6 * 86_400)) != nil)
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_1", now: saved.addingTimeInterval(8 * 86_400)) == nil, "Older than a week")
    try await writer.saveTerminal(point("pty_2", screen: String(repeating: "x", count: TerminalResume.screenLimit + 1), updated: saved))
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_2", now: saved) == nil, "A screen over the limit is not kept")
    let metadata = try PersistenceWriter(metadataOnly: true)
    try await metadata.saveTerminal(point("pty_3", updated: saved))
    #expect(try await metadata.terminal(serverID: "s", ptyID: "pty_3", now: saved) == nil, "A metadata-only cache keeps no terminal output")
}

@Test func savedScreensExpireWithoutTheirTerminalOpening() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "terminal-expiry-\(UUID().uuidString)/cache.sqlite")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let saved = Date(timeIntervalSince1970: 1_800_000_000)
    let writer = try PersistenceWriter(url: url)
    try await writer.saveTerminal(point("pty_old", updated: saved))
    // Another terminal's save a week and a day later drops the old screen, which nobody opened.
    try await writer.saveTerminal(point("pty_new", updated: saved.addingTimeInterval(8 * 86_400)))
    #expect(try await writer.terminal(serverID: "s", ptyID: "pty_old", now: saved) == nil)
    try await writer.saveTerminal(point("pty_left", updated: saved))
    // Opening the cache later drops it too.
    let reopened = try PersistenceWriter(url: url, date: { saved.addingTimeInterval(8 * 86_400) })
    #expect(try await reopened.terminal(serverID: "s", ptyID: "pty_left", now: saved) == nil)
    #expect(try await reopened.terminal(serverID: "s", ptyID: "pty_new", now: saved.addingTimeInterval(8 * 86_400)) != nil)
}

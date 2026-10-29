import Foundation
import GRDB

/// Where a terminal resumes: the output cursor and the screen that matches it. Kept only in the app's cache database,
/// never in the App Group, and only while the PTY exists, for at most `lifetime`.
public struct TerminalResume: Sendable, Equatable {
    public var serverID: String
    public var ptyID: String
    public var directory: String
    /// UTF-16 code units of output, as the server counts them.
    public var cursor: Int
    public var cols: Int
    public var rows: Int
    /// The screen and part of its scrollback as escape sequences, at most `screenLimit` bytes.
    public var screen: String
    public var updated: Date
    public static let screenLimit = 1 << 20
    public static let lifetime: TimeInterval = 7 * 86_400
    public init(serverID: String, ptyID: String, directory: String, cursor: Int, cols: Int, rows: Int, screen: String, updated: Date) {
        self.serverID = serverID; self.ptyID = ptyID; self.directory = directory; self.cursor = cursor
        self.cols = cols; self.rows = rows; self.screen = screen; self.updated = updated
    }
}

extension PersistenceWriter {
    /// Nothing is kept when the cache holds metadata only, or for a screen over the limit.
    public func saveTerminal(_ value: TerminalResume) throws {
        guard !metadataOnly, value.cursor >= 0, value.screen.utf8.count <= TerminalResume.screenLimit else { return }
        try database.write { db in
            try Self.dropExpiredTerminals(db, now: value.updated)
            try db.execute(sql: "INSERT OR REPLACE INTO pty_cursor(server_id,pty_id,cursor,directory,cols,rows,screen,updated_at) VALUES (?,?,?,?,?,?,?,?)",
                           arguments: [value.serverID, value.ptyID, value.cursor, value.directory, value.cols, value.rows,
                                       Data(value.screen.utf8), value.updated.timeIntervalSince1970])
        }
    }
    /// The saved point, after dropping every point older than `TerminalResume.lifetime`.
    public func terminal(serverID: String, ptyID: String, now: Date = Date()) throws -> TerminalResume? {
        try database.write { db in
            try Self.dropExpiredTerminals(db, now: now)
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM pty_cursor WHERE server_id=? AND pty_id=?", arguments: [serverID, ptyID]) else { return nil }
            let screen: Data = row["screen"] ?? Data()
            return TerminalResume(serverID: serverID, ptyID: ptyID, directory: row["directory"] ?? "", cursor: row["cursor"],
                                  cols: row["cols"] ?? 0, rows: row["rows"] ?? 0, screen: String(decoding: screen, as: UTF8.self),
                                  updated: Date(timeIntervalSince1970: row["updated_at"] ?? 0))
        }
    }
    /// Saved screens live at most `TerminalResume.lifetime`, whether or not their terminal is opened again: this runs
    /// when the cache opens, on every save and on every read.
    static func dropExpiredTerminals(_ db: Database, now: Date) throws {
        try db.execute(sql: "DELETE FROM pty_cursor WHERE updated_at IS NULL OR updated_at < ?", arguments: [now.timeIntervalSince1970 - TerminalResume.lifetime])
    }
    public func forgetTerminal(serverID: String, ptyID: String) throws {
        try database.write { try $0.execute(sql: "DELETE FROM pty_cursor WHERE server_id=? AND pty_id=?", arguments: [serverID, ptyID]) }
    }
    /// Drops the points of terminals the server no longer lists in `directory`, as after a server restart.
    public func forgetTerminals(serverID: String, directory: String, keeping ids: Set<String>) throws {
        try database.write { db in
            for id in try String.fetchAll(db, sql: "SELECT pty_id FROM pty_cursor WHERE server_id=? AND directory=?", arguments: [serverID, directory])
            where !ids.contains(id) {
                try db.execute(sql: "DELETE FROM pty_cursor WHERE server_id=? AND pty_id=?", arguments: [serverID, id])
            }
        }
    }
    public func forgetTerminals(serverID: String) throws {
        try database.write { try $0.execute(sql: "DELETE FROM pty_cursor WHERE server_id=?", arguments: [serverID]) }
    }
}

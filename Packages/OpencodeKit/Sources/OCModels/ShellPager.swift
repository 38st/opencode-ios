// Paging rules: packages/core/src/shell.ts output() (byte cursor, 64 KiB pages, `cursor == size` when caught up) and the
// web UI's one-second polling (packages/session-ui/src/tools/shell-output.ts) at v2.2.0.
import Foundation

public struct ShellPager: Equatable, Sendable {
    public enum Next: Equatable, Sendable { case fetch(cursor: Int), poll(after: Duration), done }
    public private(set) var cursor = 0
    public private(set) var running: Bool
    /// The server answered 404: the command was removed (Stop) or dropped after its 25 most recent exited shells.
    public private(set) var missing = false
    public static let pageSize = 65_536
    public init(running: Bool) { self.running = running }

    public func start() -> Next { missing ? .done : .fetch(cursor: cursor) }
    /// After a page: read on while the server holds more, poll while the command runs, else stop.
    public mutating func received(cursor next: Int, size: Int) -> Next {
        cursor = max(cursor, min(next, size))
        if cursor < size { return .fetch(cursor: cursor) }
        return running ? .poll(after: .seconds(1)) : .done
    }
    /// The command ended: read what is left once, then stop.
    public mutating func exited() -> Next {
        guard running, !missing else { return .done }
        running = false
        return .fetch(cursor: cursor)
    }
    public mutating func notFound() -> Next { missing = true; running = false; return .done }
    /// Captured output of a command without a terminal has bare newlines; the terminal also needs the carriage return.
    public static func terminalText(_ output: String) -> String {
        output.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
    }
}

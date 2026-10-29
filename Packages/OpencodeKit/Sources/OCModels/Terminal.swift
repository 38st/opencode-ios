// Sources: packages/schema/src/pty.ts, schema/src/config/shell.ts and gui-plugins/src/terminal/{model,title}.ts at v2.2.0.
import Foundation
import OCFoundation

/// A server PTY (`Pty.Info`). Exited PTYs stay listed, with their exit code, until removed.
public struct PtyInfo: WireValue, Identifiable {
    public enum Status: Equatable, Sendable { case running, exited, unknown(String) }
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var title: String { string("title") }
    public var command: String { string("command") }
    public var args: [String] { strings("args") }
    public var cwd: String { string("cwd") }
    public var pid: Int? { self["pid"]?.wireInt }
    public var exitCode: Int? { self["exitCode"]?.wireInt }
    public var status: Status {
        switch string("status") { case "running": .running; case "exited": .exited; case let other: .unknown(other) }
    }
    /// The command line as the list shows it: the program's name and its arguments.
    public var commandLine: String {
        ([URL(fileURLWithPath: command).lastPathComponent] + args).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// One entry of `GET /api/config/shell`, which answers a bare array rather than a `{data}` envelope.
public struct ShellOption: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { path }
    public var path: String { string("path") }
    public var name: String { string("name", default: URL(fileURLWithPath: path).lastPathComponent) }
}

public enum TerminalTitles {
    /// New terminals are titled "Terminal N" with the lowest number not in use, as the desktop titles its tabs.
    public static func next(after titles: [String]) -> String {
        let used = Set(titles.compactMap { title -> Int? in
            guard title.hasPrefix("Terminal "), let number = Int(title.dropFirst("Terminal ".count)), number > 0 else { return nil }
            return number
        })
        return "Terminal \((1...(used.count + 1)).first { !used.contains($0) } ?? 1)"
    }
}

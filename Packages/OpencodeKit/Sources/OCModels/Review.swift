import Foundation
import OCFoundation

public struct VCSInfo: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var provider: String? { self["provider"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
    public var current: String? { self["branch"]?["current"]?.stringValue }
    public var defaultBranch: String? { self["branch"]?["default"]?.stringValue }
}

public enum ReviewSource: Codable, Hashable, Sendable {
    case working, branch, lastTurn, turn(String)
    public var key: String {
        switch self { case .working: "working"; case .branch: "branch"; case .lastTurn: "lastTurn"; case .turn(let id): "turn:" + id }
    }
    public var title: String {
        switch self { case .working: localized("Git changes"); case .branch: localized("Branch changes"); case .lastTurn: localized("Last turn changes"); case .turn: localized("Turn changes") }
    }
    public var projectRelative: Bool { switch self { case .lastTurn, .turn: true; default: false } }
    public static func available(vcs: VCSInfo, session: Bool) -> [Self] {
        guard vcs.provider != nil else { return [] }
        var result: [Self] = [.working]
        if let current = vcs.current, let base = vcs.defaultBranch, current != base { result.append(.branch) }
        if session && vcs.provider == "git" { result.append(.lastTurn) }
        return result
    }
}

public struct ReviewState: Codable, Equatable, Sendable {
    public var source: ReviewSource = .working
    public var selectedFile: String?
    public var openFiles: Set<String> = []
    public var tab = "Changes"
    public init() {}
}

/// All paths crossing fs.* are normalized here; no request contains a parent segment.
public struct ReviewPath: Equatable, Sendable {
    public enum Root: Sendable { case project, repository, location }
    public let directory: String
    public let path: String
    public var absolute: String { directory == "/" ? "/" + path : directory + "/" + path }
    public init?(_ path: String, root: Root, location: String, project: String) {
        guard !path.contains("\0") else { return nil }
        let path = path.replacingOccurrences(of: "\\", with: "/")
        let base = root == .location ? location : project
        let absolute = Self.normalize(path.hasPrefix("/") || Self.drivePath(path) ? path : base + "/" + path)
        let local = Self.normalize(location), project = Self.normalize(project)
        if let relative = Self.relative(absolute, to: local) { directory = local; self.path = relative }
        else if let relative = Self.relative(absolute, to: project) { directory = project; self.path = relative }
        else { return nil }
    }
    public static func normalize(_ path: String) -> String {
        let path = path.replacingOccurrences(of: "\\", with: "/")
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(part) }
        }
        return (path.hasPrefix("//") ? "//" : path.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
    }
    private static func relative(_ path: String, to root: String) -> String? {
        let windows = drivePath(root) || root.hasPrefix("//")
        if windows ? path.lowercased() == root.lowercased() : path == root { return "" }
        let prefix = root == "/" ? root : root + "/"
        return (windows ? path.lowercased().hasPrefix(prefix.lowercased()) : path.hasPrefix(prefix)) ? String(path.dropFirst(prefix.count)) : nil
    }
    private static func drivePath(_ path: String) -> Bool { path.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil }
}

public enum ReviewOrder {
    public static func paths(_ paths: [String]) -> [String] {
        paths.sorted { lhs, rhs in
            let a = lhs.split(separator: "/"), b = rhs.split(separator: "/")
            for i in 0..<min(a.count, b.count) {
                if a[i] == b[i] { continue }
                let ad = i < a.count - 1, bd = i < b.count - 1
                if ad != bd { return ad }
                return String(a[i]).localizedCompare(String(b[i])) == .orderedAscending
            }
            return a.count < b.count
        }
    }
}

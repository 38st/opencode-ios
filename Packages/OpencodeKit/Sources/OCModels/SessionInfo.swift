import OCFoundation

public struct SessionInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var parentID: String? { self["parentID"]?.stringValue }
    public var projectID: String { string("projectID") }
    public var title: String? { self["title"]?.stringValue }
    public var agent: String? { self["agent"]?.stringValue }
    public var model: ModelRef? { optional("model") }
    public var time: WireTime { object("time") }
    public var cost: Double { number("cost") }
    public var tokens: TokenUsage { object("tokens") }
    public var location: Location { object("location") }
    public var subpath: String? { self["subpath"]?.stringValue }
    public var outcome: String? { self["outcome"]?.stringValue }
    public var metadata: JSONValue? { self["metadata"] }
    public var permissions: [PermissionRule] { self["permissions"]?.lossy(PermissionRule.self).values ?? [] }
    public var revert: SessionRevert? { optional("revert") }
    public var fork: SessionFork? { optional("fork") }
}
public struct SessionRevert: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var messageID: String { string("messageID") }
    public var snapshot: String? { self["snapshot"]?.stringValue }
    public var partID: String? { self["partID"]?.stringValue }
    public var files: [FileDiff] { self["files"]?.lossy(FileDiff.self).values ?? [] }
}
public struct SessionFork: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var sessionID: String { string("sessionID") }
    public var boundary: WireObject { object("boundary") }
}
public struct Location: WireValue, Hashable {
    public var raw: JSONValue
    public init(raw: JSONValue = .object([:])) { self.raw = raw }
    public init(directory: String, workspaceID: String? = nil) {
        raw = .object(["directory": .string(directory)])
        self["workspaceID"] = workspaceID.map(JSONValue.string)
    }
    public var directory: String { string("directory") }
    public var workspaceID: String? { self["workspaceID"]?.stringValue }
    public var project: LocationProject? { optional("project") }
    public var key: String { (try? JSONValue.array([.string(directory), workspaceID.map(JSONValue.string) ?? .null]).prettyPrinted()) ?? directory }
}
public struct Project: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var canonical: String { string("canonical") }
    public var name: String? { self["name"]?.stringValue }
    public var vcs: String? { self["vcs"]?.stringValue }
    public var icon: ProjectIcon? { optional("icon") }
    public var commands: WireObject? { optional("commands") }
    public var time: WireTime { object("time") }
    public var sandboxes: [String] { strings("sandboxes") }
}
public struct FileDiff: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var file: String { string("file") }
    public var patch: String { string("patch") }
    public var additions: Int { max(0, self["additions"]?.wireInt ?? 0) }
    public var deletions: Int { max(0, self["deletions"]?.wireInt ?? 0) }
    public var status: String { string("status") }
    public var statusKind: FileStatus {
        switch status { case "added": .added; case "deleted": .deleted; case "modified": .modified; default: .unknown(status) }
    }
    public var changedLines: Int { Self.add(additions, deletions) }
    public static func totals(_ files: [Self]) -> (additions: Int, deletions: Int) {
        files.reduce((0, 0)) { (add($0.0, $1.additions), add($0.1, $1.deletions)) }
    }
    private static func add(_ a: Int, _ b: Int) -> Int { let result = a.addingReportingOverflow(b); return result.overflow ? Int.max : result.partialValue }
}
public enum FileStatus: Equatable, Sendable { case added, deleted, modified, unknown(String) }
public struct ShellOutput: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var output: String { string("output") }
    public var cursor: Double { number("cursor") }
    public var size: Double { number("size") }
    public var truncated: Bool { self["truncated"]?.boolValue ?? false }
}
public struct ShellInfo: WireValue, Identifiable {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var id: String { string("id") }
    public var status: String { string("status") }
    public var command: String { string("command") }
    public var cwd: String { string("cwd") }
    public var shell: String { string("shell") }
    public var file: String { string("file") }
    public var pid: Double? { self["pid"]?.wireNumber }
    public var exit: Double? { self["exit"]?.wireNumber }
    public var signal: String? { self["signal"]?.stringValue }
    public var metadata: JSONValue? { self["metadata"] }
    public var time: WireTime { object("time") }
}

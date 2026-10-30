import Foundation
import OCFoundation

/// A session export (`SessionTransfer.Data`: `{info, messages}`) as Markdown, rendered on the device.
public enum TranscriptMarkdown {
    public static func render(_ transfer: JSONValue, timeZone: TimeZone = .current) -> String {
        let info = SessionInfo(raw: transfer["info"] ?? .object([:]))
        let messages = transfer["messages"]?.lossy(SessionMessage.self).values ?? []
        var out = "# " + (info.title.map(oneLine) ?? "Untitled session") + "\n\n"
        var facts = ["- Session: `\(info.id)`"]
        if !info.location.directory.isEmpty { facts.append("- Directory: `\(info.location.directory)`") }
        if info.time.created > 0 { facts.append("- Created: " + timestamp(info.time.created, timeZone)) }
        facts.append("- Cost: " + String(format: "$%.4f", info.cost))
        out += facts.joined(separator: "\n") + "\n"
        for message in messages {
            let block = section(message.fields)
            if !block.isEmpty { out += "\n" + block + "\n" }
        }
        return out
    }

    static func section(_ row: MessageFields) -> String {
        switch row.type {
        case "user": return "## User\n\n" + row.text + files(row)
        case "synthetic": return "## Context\n\n" + quote(row.text)
        case "system": return "## Instructions\n\n" + quote(row.text)
        case "skill": return "## Skill: " + oneLine(row.string("name", default: row.string("skill"))) + "\n\n" + row.text
        case "shell":
            let output = row["output"]?["output"]?.stringValue ?? ""
            return "## Shell\n\n" + fence("$ " + row.string("command") + (output.isEmpty ? "" : "\n" + output), language: "sh")
        case "assistant": return assistant(row)
        case "compaction":
            let summary = row.string("summary")
            return "## Compaction\n\n" + (summary.isEmpty ? "_Context compacted (\(row.string("status")))._" : quote(summary))
        case "agent-switched": return "_Agent: " + oneLine(row.string("agent")) + "_"
        case "model-switched": return "_Model: " + oneLine(row["model"]?["id"]?.stringValue ?? "") + "_"
        case "location-switched": return "_Moved to `" + (row["location"]?["directory"]?.stringValue ?? "") + "`_"
        case "idle":
            guard let outcome = row["outcome"]?.stringValue, outcome != "succeeded" else { return "" }
            let error = row["error"]?["message"]?.stringValue
            return "_Turn " + outcome + (error.map { ": " + oneLine($0) } ?? "") + "_"
        default: return ""
        }
    }

    static func assistant(_ row: MessageFields) -> String {
        var parts: [String] = []
        for item in row.content {
            let fields = item.fields
            switch item {
            case .text: if !fields.text.isEmpty { parts.append(fields.text) }
            case .reasoning:
                if !fields.text.isEmpty { parts.append("<details><summary>Thinking</summary>\n\n" + fields.text + "\n\n</details>") }
            case .tool:
                let state = fields.toolState.fields
                var tool = "**Tool: " + oneLine(fields.name) + "** (" + (state.status.isEmpty ? "pending" : state.status) + ")"
                if state.input != .object([:]), let input = try? state.input.prettyPrinted() { tool += "\n\n" + fence(input, language: "json") }
                let output = state.content.compactMap { content -> String? in
                    switch content {
                    case .text(let value): value.text
                    case .file(let value): "[" + (value.name ?? value.mime) + "]"
                    default: nil
                    }
                }.joined(separator: "\n")
                if !output.isEmpty { tool += "\n\n" + fence(output, language: "") }
                if let error = state.error?["message"]?.stringValue { tool += "\n\nError: " + oneLine(error) }
                parts.append(tool)
            default: break
            }
        }
        guard !parts.isEmpty else { return "" }
        let agent = row["agent"]?.stringValue.map { " (" + oneLine($0) + ")" } ?? ""
        return "## Assistant" + agent + "\n\n" + parts.joined(separator: "\n\n")
    }

    private static func files(_ row: MessageFields) -> String {
        let names = (row["files"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue ?? $0["source"]?["uri"]?.stringValue }
        return names.isEmpty ? "" : "\n\n" + names.map { "- Attachment: " + oneLine($0) }.joined(separator: "\n")
    }
    /// A fence longer than any backtick run inside the text, so the text cannot close it.
    static func fence(_ text: String, language: String) -> String {
        var longest = 0, run = 0
        for character in text { if character == "`" { run += 1; longest = max(longest, run) } else { run = 0 } }
        let marks = String(repeating: "`", count: max(3, longest + 1))
        return marks + language + "\n" + text + "\n" + marks
    }
    private static func quote(_ text: String) -> String { text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") }
    private static func oneLine(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " ") }
    private static func timestamp(_ milliseconds: Double, _ zone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter(); formatter.timeZone = zone
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }
}

/// Each export gets a temporary folder of its own; folders older than ten minutes are removed with the next export.
public enum SessionExportFile {
    /// The desktop app's name: the title (or ID) lowercased, with runs of other characters as "-".
    public static func name(title: String?, sessionID: String, extension ext: String) -> String {
        let base = (title.flatMap { $0.isEmpty ? nil : $0 } ?? sessionID).lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return (base.isEmpty ? sessionID : base) + "." + ext
    }
    public static func write(_ data: Data, title: String?, sessionID: String, extension ext: String,
                             root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let exports = root.appending(path: "Exports", directoryHint: .isDirectory)
        let cutoff = Date().addingTimeInterval(-600)
        for old in (try? FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: [.creationDateKey])) ?? []
            where ((try? old.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < cutoff {
            try? FileManager.default.removeItem(at: old)
        }
        let folder = exports.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name(title: title, sessionID: sessionID, extension: ext))
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        return url
    }
}

public enum ExportFormat: String, Hashable, Sendable { case json, markdown }

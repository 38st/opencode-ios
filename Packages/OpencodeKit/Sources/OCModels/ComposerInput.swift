import Foundation
import OCFoundation

/// Local selection, kept with the draft rather than the streaming transcript.
public struct ComposerOptions: Codable, Sendable, Equatable {
    public var shell = false
    public var agent: String?
    public var model: ModelRef?
    public var editingOutboxID: String?
    public var creatingSessionID: String?
    public var recoveringCreateID: String?
    public init(shell: Bool = false, agent: String? = nil, model: ModelRef? = nil, editingOutboxID: String? = nil) {
        self.shell = shell; self.agent = agent; self.model = model; self.editingOutboxID = editingOutboxID
    }
}

public enum ComposerInput {
    public static func encode(_ text: AttributedString, directory: String, files: [PromptFileInput] = [], comments: [LineComment] = [],
                              agent: String?, model: ModelRef?, delivery: Delivery = .steer) -> PromptInput {
        let plain = String(text.characters)
        let inline = files
        var files: [PromptFileInput] = [], agents: [WireObject] = [], skills: [WireObject] = []
        for run in text.runs {
            guard let token = run[MentionAttribute.self] else { continue }
            let start = String(text[..<run.range.lowerBound].characters).utf16.count
            let label = String(text[run.range].characters)
            let mention: JSONValue = .object(["start": .integer(Int64(start)), "end": .integer(Int64(start + label.utf16.count)), "text": .string(label)])
            switch token.kind {
            case "file", "reference":
                let path = absolute(token.value, directory: directory)
                files.append(.init(uri: fileURI(path) + (token.selection.map { "?start=\($0.start)&end=\($0.end)" } ?? ""), name: token.kind == "reference" ? String(label.dropFirst()) : path.split(separator: "/").last.map(String.init), mention: mention))
            case "agent": agents.append(.init(raw: .object(["name": .string(token.value), "mention": mention])))
            case "skill": skills.append(.init(raw: .object(["id": .string(token.value), "mention": mention])))
            default: break
            }
        }
        let comments = comments.filter { !$0.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var used = Set(files.map(\.uri))
        for comment in comments {
            if comment.selection?.deleted != true {
                let range = comment.selection?.newRange
                let uri = fileURI(absolute(comment.file, directory: directory)) + (range.map { "?start=\($0.lowerBound)&end=\($0.upperBound)" } ?? "")
                files.append(.init(uri: uri, name: comment.file.split(separator: "/").last.map(String.init)))
                used.insert(uri)
            }
            for path in LineComment.mentions(comment.comment) {
                let uri = fileURI(absolute(path, directory: directory))
                if used.insert(uri).inserted { files.append(.init(uri: uri, name: path.split(separator: "/").last.map(String.init))) }
            }
        }
        files += inline
        let wireText = (plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [plain]) + comments.map(\.note)
        var metadata: JSONValue = .object(["displayText": .string(plain), "comments": .array(comments.map(\.metadata)), "attachments": .array([])])
        metadata.set("agent", agent.map(JSONValue.string))
        if let model {
            var selection: JSONValue = .object(["modelID": .string(model.id), "providerID": .string(model.providerID)])
            selection.set("variant", model.variant.map(JSONValue.string))
            metadata.set("model", selection)
        }
        return .init(text: wireText.joined(separator: "\n"), files: files, agents: agents, skills: skills, metadata: metadata, delivery: delivery)
    }

    public static func restoreModel(_ metadata: JSONValue?) -> ModelRef? {
        guard var model = metadata?["model"] else { return nil }
        if let id = model["modelID"] { model.set("id", id); model.set("modelID", nil) }
        return ModelRef(raw: model)
    }

    /// Accepts both stored server prompts and immutable outbox admission bodies.
    /// Malformed, overlapping or stale ranges remain ordinary text.
    public static func restoreText(_ raw: JSONValue, references: JSONValue? = nil) -> AttributedString {
        let plain = raw["metadata"]?["displayText"]?.stringValue ?? (LineComment.parseNote(raw["text"]?.stringValue ?? "") == nil ? raw["text"]?.stringValue ?? "" : "")
        var result = AttributedString(plain), occupied = IndexSet()
        for (key, kind, valueKey) in [("files", "file", "uri"), ("agents", "agent", "name"), ("skills", "skill", "id")] {
            for item in raw[key]?.arrayValue ?? [] {
                guard let mention = item["mention"], let start = mention["start"]?.wireInt, let end = mention["end"]?.wireInt,
                      start >= 0, end > start, end <= plain.utf16.count,
                      let range = Range(NSRange(location: start, length: end - start), in: plain),
                      String(plain[range]) == mention["text"]?.stringValue,
                      occupied.intersection(IndexSet(integersIn: start..<end)).isEmpty,
                      let lower = AttributedString.Index(range.lowerBound, within: result),
                      let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
                var value = item[valueKey]?.stringValue ?? "", resolvedKind = kind
                var selection: LineSelection?
                if kind == "file" {
                    value = item["source"]?["uri"]?.stringValue ?? value
                    guard value.hasPrefix("file://") else { continue }
                    // A restored mention must retain directory slashes and its original URI spelling.
                    let link = FileLink(value, normalizingPath: false); value = link.path; selection = link.selection
                    if references?.arrayValue?.contains(where: { $0["path"]?.stringValue == value && $0["name"]?.stringValue == String(plain[range].dropFirst()) }) == true ||
                        item["name"]?.stringValue == String(plain[range].dropFirst()) &&
                        item["name"]?.stringValue != value.split(separator: "/").last.map(String.init) { resolvedKind = "reference" }
                }
                guard !value.isEmpty else { continue }
                result[lower..<upper][MentionAttribute.self] = .init(kind: resolvedKind, value: value, selection: selection)
                occupied.insert(integersIn: start..<end)
            }
        }
        return result
    }

    public static func absolute(_ path: String, directory: String) -> String {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") || path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil { return path }
        return directory.replacingOccurrences(of: #"[/\\]+$"#, with: "", options: .regularExpression) + "/" + path
    }
    public static func fileURI(_ path: String) -> String {
        var path = path.replacingOccurrences(of: "\\", with: "/")
        if path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil { path = "/" + path }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return "file://" + path.components(separatedBy: "/").enumerated().map { index, segment in
            if index == 1, segment.range(of: #"^[A-Za-z]:$"#, options: .regularExpression) != nil { return segment }
            return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
        }.joined(separator: "/")
    }
}

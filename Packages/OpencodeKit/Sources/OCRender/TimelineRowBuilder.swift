import Foundation
import OCModels
import OCFoundation

/// Owned by a session screen. A durable idle marker closes a turn, including steered prompts.
/// Comparing frozen input also invalidates cached rows after authoritative corrections/reverts.
public actor TimelineRowBuilder {
    private struct Frozen: Sendable {
        var input: [SessionMessage]
        var rows: [TimelineRow]
    }
    private var cache: [String: Frozen] = [:]
    private var preset: TimelineDetail = .compact
    public private(set) var rebuiltTurns = 0
    public init() {}
    public func build(_ messages: [SessionMessage], detail: TimelineDetail = .compact,
                      pending: [TimelineRow] = []) -> [TimelineRow] {
        if preset != detail { cache.removeAll(); preset = detail }
        var rows: [TimelineRow] = [], turn: [SessionMessage] = [], retained: Set<String> = []
        for message in messages {
            turn.append(message)
            guard message.type == "idle" else { continue }
            let key = (turn.first?.id ?? "") + ":" + message.id
            retained.insert(key)
            if let frozen = cache[key], frozen.input == turn { rows += frozen.rows }
            else {
                let built = buildTurn(turn, detail: detail)
                cache[key] = Frozen(input: turn, rows: built); rows += built; rebuiltTurns += 1
            }
            turn.removeAll(keepingCapacity: true)
        }
        cache = cache.filter { retained.contains($0.key) }
        if !turn.isEmpty { rows += buildTurn(turn, detail: detail); rebuiltTurns += 1 }
        return rows + pending
    }

    private func buildTurn(_ messages: [SessionMessage], detail: TimelineDetail) -> [TimelineRow] {
        var result: [TimelineRow] = [], group: [TimelineRow] = [], files: Set<String> = []
        func flush() {
            guard let first = group.first else { return }
            let tools = group.filter { [.tool, .shell, .subagent].contains($0.kind) }
            let names = tools.map(\.text).filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ")
            let text = tools.isEmpty ? (group.allSatisfy { $0.kind == .reasoning } ? "Thinking" : "Updates") : "Used \(tools.count) \(names.isEmpty ? "tools" : names)"
            result.append(.init(id: "group:" + first.id, kind: .toolGroup, text: text, children: group))
            group.removeAll(keepingCapacity: true)
        }
        func append(_ row: TimelineRow, tool: String? = nil, required: Bool = false) {
            switch required ? .separate : detail.placement(row, tool: tool) {
            case .hidden: break
            case .grouped: group.append(row)
            case .separate: flush(); result.append(row)
            }
        }
        func appendError(_ error: StructuredError, id: String, interrupted: Bool = false, deduplicate: Bool = false) {
            let type = error.type.lowercased()
            let interrupted = interrupted || type.contains("abort") || type.contains("interrupt")
            let row = TimelineRow(id: id + ":error", kind: interrupted ? .notice : .error,
                                  text: interrupted ? "Interrupted" : error.message)
            if deduplicate && result.contains(where: { $0.kind == row.kind && $0.text == row.text }) { return }
            append(row, required: true)
        }
        for message in messages {
            let f = message.fields
            switch message.type {
            case "user":
                append(.init(id: message.id, kind: .userPrompt, text: f.text,
                             badge: f.text.hasPrefix("Voice delegation.") ? "Voice" : nil))
            case "assistant":
                files.formUnion(f.snapshot?.files ?? [])
                for (index, content) in message.content.enumerated() {
                    let c = content.fields, name = c.name
                    let ref = TimelineReference(messageID: message.id, index: index)
                    let id = message.id + ":" + (content.type == "tool" ? c.id : "\(index)")
                    switch content.type {
                    case "text":
                        // Empty/open items still get a stable row before their first delta.
                        append(.init(id: id, kind: .assistantText, reference: ref))
                    case "reasoning": append(.init(id: id, kind: .reasoning, reference: ref))
                    case "tool":
                        if name == "question", ["streaming", "running"].contains(c.toolState.type) { continue }
                        let kind: TimelineRow.Kind = ["subagent", "task"].contains(name) ? .subagent : ["shell", "bash"].contains(name) ? .shell : .tool
                        append(.init(id: id, kind: kind, text: ToolPresenterRegistry().presentation(c).title, reference: ref,
                                     badge: ["read", "glob", "grep"].contains(name) ? "explore" : nil,
                                     childID: c.toolState.fields.metadata?["sessionID"]?.stringValue), tool: name,
                               required: c.toolState.type == "error" || ToolPresentation.shellFailed(c.toolState.fields.metadata))
                    default: append(.init(id: id, kind: .notice, text: "Unsupported content: \(content.type)"))
                    }
                }
                if let retry = f.retry {
                    append(.init(id: message.id + ":retry", kind: .retry, text: retry.error.message,
                                 badge: "Attempt \(Int(clamping: retry.attempt))"))
                }
                if let error = f.error { appendError(error, id: message.id) }
            case "idle":
                if let error = f.error { appendError(error, id: message.id, interrupted: f.outcome == "interrupted", deduplicate: true) }
                if detail == .compact && files.isEmpty { continue }
                append(.init(id: message.id, kind: .turnEnd, text: files.isEmpty ? "Turn complete" : "Changed \(files.count) \(files.count == 1 ? "file" : "files")",
                             files: files.sorted(), badge: f.outcome, turnFrom: messages.first { $0.type == "user" }?.id))
            case "shell": append(.init(id: message.id, kind: .shell, text: f.command ?? "Shell"), required: (f.exit ?? 0) != 0)
            case "compaction":
                append(.init(id: message.id, kind: .compaction, text: f.summary ?? "Compacting conversation", badge: f.status), required: f.status != "completed")
            default:
                let text: String = switch message.type {
                case "agent-switched": "Agent switched to \(f.agent ?? "unknown")"
                case "model-switched": "Model switched to \(f.model?.id ?? "unknown")"
                case "location-switched": "Location switched to \(f.location?.directory ?? "unknown")"
                case "skill": "Loaded \(f.name ?? f.skill ?? "skill")"
                default: f.text.isEmpty ? message.type.capitalized : f.text
                }
                append(.init(id: message.id, kind: .notice, text: text, childID: f.metadata?["sessionID"]?.stringValue),
                       required: f.metadata?["state"]?.stringValue == "error" || ToolPresentation.shellFailed(f.metadata))
            }
        }
        flush(); return result
    }
}

extension Int {
    init(clamping value: Double) {
        self = value.isFinite && value >= Double(Int.min) && value < Double(Int.max) ? Int(value) : 0
    }
}

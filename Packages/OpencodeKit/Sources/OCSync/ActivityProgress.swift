import Foundation
import OCActivity
import OCFoundation
import OCModels

/// Plaintext state has no command, path, prompt, title or error body.
struct ActivityProgress {
    var states: [String: SessionActivityAttributes.ContentState] = [:]
    mutating func receive(_ event: ServerEvent, sessions: [String: SessionModel]) {
        guard let sessionID = event.sessionID, let type = event.header?.type else { return }
        var root = sessionID, seen: Set<String> = []
        while seen.insert(root).inserted, let parent = sessions[root]?.info.parentID { root = parent }
        let now = Date().timeIntervalSince1970
        var state = states[root] ?? .init(startedAt: now, updatedAt: now)
        switch type {
        case "session.execution.started" where sessionID == root:
            state = .init(startedAt: now, updatedAt: now)
        case "session.step.started": state.step = min(100_000, state.step + 1)
        case "session.tool.input.started":
            let tool = event.payload["tool"]?.stringValue ?? event.payload["name"]?.stringValue ?? ""
            state.toolGlyph = switch tool {
            case "read": "read"
            case "edit", "write", "patch", "apply_patch": "edit"
            case "shell", "bash": "shell"
            case "grep", "glob", "list", "ls": "search"
            case "webfetch", "websearch": "web"
            case "task", "subagent": "agent"
            case "question": "question"
            default: "other"
            }
        case "session.execution.succeeded" where sessionID == root: state.phase = "succeeded"
        case "session.execution.failed" where sessionID == root: state.phase = "failed"
        case "session.execution.interrupted" where sessionID == root, "session.deleted" where sessionID == root: state.phase = "interrupted"
        default: return
        }
        state.updatedAt = now; states[root] = state
    }
}

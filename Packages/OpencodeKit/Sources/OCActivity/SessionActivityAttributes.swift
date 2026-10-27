import Foundation
import OCShared

public struct SessionActivityAttributes: Codable, Sendable, Hashable {
    public let serverID: String
    public let sessionID: String
    public let title: String
    public let project: String
    public let createdAt: Date
    public init(serverID: String, sessionID: String, title: String, project: String, createdAt: Date = .now) {
        self.serverID = serverID; self.sessionID = sessionID; self.title = title; self.project = project; self.createdAt = createdAt
    }
    public var url: URL? { UUID(uuidString: serverID).flatMap { DeepLink.url(serverID: $0, sessionID: sessionID) } }

    public struct ContentState: Codable, Sendable, Hashable {
        // Unix seconds, NOT Date's Codable seconds-since-2001. M5a pushes this exact shape.
        public var phase: String
        public var step: Int
        public var toolGlyph: String
        public var startedAt: Double
        public var updatedAt: Double
        public init(phase: String = "running", step: Int = 0, toolGlyph: String = "none", startedAt: Double, updatedAt: Double) {
            self.phase = phase; self.step = step; self.toolGlyph = toolGlyph; self.startedAt = startedAt; self.updatedAt = updatedAt
        }
        public var isFinal: Bool { ["succeeded", "failed", "interrupted"].contains(phase) }
        public var label: String {
            switch phase {
            case "running": "Running"
            case "needsInput": "Needs you"
            case "retrying": "Retrying"
            case "succeeded": "Finished"
            case "failed": "Failed"
            case "interrupted": "Stopped"
            default: "Open for status"
            }
        }
        public var symbol: String {
            switch phase {
            case "succeeded": return "checkmark.circle"
            case "failed": return "exclamationmark.circle"
            case "interrupted": return "stop.circle"
            default: break
            }
            return switch toolGlyph {
            case "read": "doc.text"
            case "edit": "pencil"
            case "shell": "terminal"
            case "search": "magnifyingglass"
            case "web": "globe"
            case "agent": "person.2"
            case "question": "questionmark.bubble"
            default: "circle.dotted"
            }
        }
    }
}
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
extension SessionActivityAttributes: ActivityAttributes {}
#endif

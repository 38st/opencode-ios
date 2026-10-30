import Foundation
import Testing
@testable import OCFoundation

private enum Recordings {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appending(path: "Fixtures/v2")
    }()

    static func files(extension suffix: String, directory: String? = nil) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == suffix,
                  directory == nil || url.deletingLastPathComponent().lastPathComponent == directory
            else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    // Public durable events in schema/session-event.ts and worktree.ts at d0732ea.
    // Checking known types prevents a missing durable envelope from passing silently.
    static let durableTypes: Set<String> = [
        "worktree.resolved", "session.created", "session.agent.selected", "session.model.selected",
        "session.moved", "session.renamed", "session.metadata.updated", "session.permissions",
        "session.viewed", "session.deleted", "session.forked", "session.inbox.delivered",
        "session.inbox.enqueued", "session.inbox.cancelled", "session.inbox.delivery.changed",
        "session.execution.started", "session.execution.succeeded", "session.execution.failed",
        "session.execution.interrupted", "session.instructions.updated", "session.synthetic",
        "session.skill.activated", "session.shell.started", "session.shell.ended",
        "session.step.started", "session.step.streamed", "session.step.ended", "session.step.failed",
        "session.text.started", "session.text.ended", "session.reasoning.started", "session.reasoning.ended",
        "session.tool.input.started", "session.tool.input.ended", "session.tool.called",
        "session.tool.success", "session.tool.failed", "session.retry.scheduled",
        "session.compaction.started", "session.compaction.ended", "session.compaction.failed",
        "session.revert.staged", "session.revert.cleared", "session.revert.committed",
    ]
}

/// Test-only SSE framing. The app parses streams incrementally with `SSEParser` in OCNetworking.
private func eventData(in bytes: Data) throws -> [Data] {
    let text = try #require(String(data: bytes, encoding: .utf8))
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    #expect(normalized.hasSuffix("\n\n"), "Capture ends at a complete SSE frame")
    return normalized.components(separatedBy: "\n\n").compactMap { frame in
        let lines = frame.components(separatedBy: "\n").compactMap { line -> String? in
            guard line == "data" || line.hasPrefix("data:") else { return nil }
            var value = line == "data" ? "" : String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            return value
        }
        return lines.isEmpty ? nil : Data(lines.joined(separator: "\n").utf8)
    }
}

@Test func recordedFixtureInventoryIsPresent() throws {
    #expect(!Recordings.files(extension: "sse").isEmpty)
    #expect(!Recordings.files(extension: "json", directory: "rest").isEmpty)
    let manifests = Recordings.files(extension: "json").filter { $0.lastPathComponent == "manifest.json" }
    #expect(!manifests.isEmpty)
    for file in manifests {
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        #expect(manifest["opencodeVersion"]?.stringValue == file.deletingLastPathComponent().lastPathComponent)
        let scenarios = try #require(manifest["scenarios"]?.arrayValue)
        #expect(!scenarios.isEmpty)
        for scenario in scenarios {
            #expect(scenario["mockScenarioHash"]?.stringValue?.count == 64)
            for entry in try #require(scenario["files"]?.arrayValue) {
                let relative = try #require(entry["path"]?.stringValue)
                #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appending(path: relative).path))
            }
        }
    }
}

@Test(arguments: Recordings.files(extension: "sse"))
func recordedSSEDecodesAndOrdersDurableEvents(file: URL) throws {
    let frames = try eventData(in: Data(contentsOf: file))
    #expect(!frames.isEmpty)
    let events = try frames.map { try JSONDecoder().decode(JSONValue.self, from: $0) }
    #expect(events.first?["type"]?.stringValue == "server.connected")
    var sequences: [String: Int64] = [:]
    for event in events {
        let type = try #require(event["type"]?.stringValue)
        #expect(event["data"] != nil)
        if Recordings.durableTypes.contains(type) { #expect(event["durable"] != nil, "\(type) needs a durable envelope") }
        guard let durable = event["durable"] else { continue }
        let aggregate = try #require(durable["aggregateID"]?.stringValue)
        let sequence = try #require(durable["seq"]?.integerValue)
        let version = try #require(durable["version"]?.integerValue)
        #expect(!aggregate.isEmpty)
        #expect(sequence >= 0)
        #expect(version > 0)
        if let previous = sequences[aggregate] { #expect(sequence > previous) }
        // Gaps are valid: internal durable events do not appear on /api/event.
        sequences[aggregate] = sequence
    }
}

@Test(arguments: Recordings.files(extension: "json", directory: "rest"))
func recordedRESTBodiesDecode(file: URL) throws {
    let exchanges = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
    for exchange in try #require(exchanges.arrayValue) {
        for side in ["request", "response"] {
            let body = try #require(exchange[side]?["body"])
            let bytes = try JSONEncoder().encode(body)
            #expect(try JSONDecoder().decode(JSONValue.self, from: bytes) == body)
        }
        #expect(exchange["response"]?["status"]?.integerValue != nil)
        let authorization = exchange["request"]?["headers"]?["authorization"]?.stringValue
        #expect(authorization == nil || authorization == "[REDACTED]")
    }
}

@Test(arguments: Recordings.files(extension: "json", directory: "ws"))
func recordedPTYContainsBinaryCursorFrames(file: URL) throws {
    let frames = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
    var cursors = 0
    for frame in try #require(frames.arrayValue) {
        guard let encoded = frame["payload"]?.stringValue else { continue }
        let bytes = try #require(Data(base64Encoded: encoded))
        if frame["opcode"]?.integerValue == 2 {
            #expect(bytes.first == 0)
            let marker = try JSONDecoder().decode(JSONValue.self, from: bytes.dropFirst())
            #expect(marker["cursor"]?.integerValue != nil)
            cursors += 1
        }
    }
    #expect(cursors >= 2, "Initial and resumed connections each send a binary cursor marker")
}

@Test func fixtureSSEFramingHandlesCommentsCRLFAndMultilineData() throws {
    let bytes = Data(": heartbeat\r\n\r\ndata: {\r\ndata: \"ok\": true}\r\n\r\n".utf8)
    let frames = try eventData(in: bytes)
    #expect(frames.count == 1)
    #expect(try JSONDecoder().decode(JSONValue.self, from: frames[0]) == .object(["ok": .bool(true)]))
}

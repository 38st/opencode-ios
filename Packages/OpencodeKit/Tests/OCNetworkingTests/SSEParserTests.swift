import Foundation
import Testing
import OCModels
@testable import OCNetworking

extension NetworkingTests {
@Test(arguments: Fixtures.versions) func everyRecordedSSEFrameIsPreserved(version: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(at: version.appending(path: "sse"), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sse" }
    #expect(!files.isEmpty)
    for file in files {
        let bytes = try Data(contentsOf: file)
        let expected = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\n\n").compactMap { block -> Data? in
            let lines = block.components(separatedBy: "\n").filter { $0.hasPrefix("data: ") }.map { String($0.dropFirst(6)) }
            return lines.isEmpty ? nil : Data(lines.joined(separator: "\n").utf8)
        }
        for chunkSize in [1, 7, 4096, max(1, bytes.count)] {
            var parser = SSEParser()
            var actual: [Data] = []
            for index in stride(from: 0, to: bytes.count, by: chunkSize) {
                actual += parser.append(bytes.subdata(in: index..<min(index + chunkSize, bytes.count))).frames.map(\.data)
            }
            #expect(actual == expected, "\(file.lastPathComponent), chunk size \(chunkSize)")
            for data in actual {
                #expect(!ServerEvent.decode(data).isFallback, "Unknown or malformed recorded frame")
            }
        }
    }
}

@Test func lineEndingsUnicodeMultilineAndComments() {
    for newline in ["\r", "\n", "\r\n"] {
        let text = "\u{FEFF}: heartbeat\(newline)\(newline)data: café\(newline)data: 🦊\(newline)event: change\(newline)id: 12\(newline)\(newline)"
        var parser = SSEParser()
        var frames: [SSEFrame] = []
        var activity = 0
        for byte in text.utf8 {
            let parsed = parser.append(Data([byte])); frames += parsed.frames; activity += parsed.receivedBytes
        }
        #expect(activity == text.utf8.count)
        #expect(frames.count == 1)
        #expect(frames.first?.data == Data("café\n🦊".utf8))
        #expect(frames.first?.event == "change")
        #expect(frames.first?.id == "12")
    }
}

@Test func oversizedEventsAreDiscardedAndParsingRecovers() {
    var parser = SSEParser()
    let huge = Data("data: ".utf8) + Data(repeating: 120, count: SSEParser.maximumEventBytes + 1)
    #expect(parser.append(huge).frames.isEmpty)
    let result = parser.append(Data("\r\n\r\ndata: ok\r\n\r\n".utf8))
    #expect(result.skippedEvents == 1)
    #expect(result.frames.map(\.data) == [Data("ok".utf8)])
}

@Test func malformedAndUnknownEventsDoNotEndDecoding() {
    let cases = ["broken", "{\"id\":\"x\",\"type\":\"future\",\"created\":null,\"data\":{}}",
                 "{\"id\":\"x\",\"type\":\"server.connected\",\"data\":null}"]
    var parser = SSEParser()
    let result = parser.append(Data((cases.map { "data: \($0)\n\n" }.joined() + String(decoding: connectedFrame, as: UTF8.self)).utf8))
    #expect(result.frames.count == 4)
    let events = result.frames.map { ServerEvent.decode($0.data) }
    if case .unknown(let header, _) = events[1] { #expect(header.created == nil) } else { Issue.record("Expected unknown") }
    if case .connected = events[3] {} else { Issue.record("Expected recovery") }
}

}

extension NetworkingTests {
    @Test(arguments: Fixtures.versions) func fixtureStreamsContinueAfterEveryUnknownAndMalformedMutation(version: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: version.appending(path: "sse"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sse" }
        for file in files {
            var source = SSEParser(), mutated = SSEParser()
            let frames = source.append(try Data(contentsOf: file)).frames
            for frame in frames {
                let unknown = Data(#"{"id":"future","type":"future.event","data":{}}"#.utf8)
                let bytes = Data("data: ".utf8) + unknown + Data("\n\ndata: {broken\n\ndata: ".utf8) + frame.data + Data("\n\n".utf8)
                var events: [ServerEvent] = []
                for offset in stride(from: 0, to: bytes.count, by: 17) {
                    events += mutated.append(bytes.subdata(in: offset..<min(offset + 17, bytes.count))).frames.map { ServerEvent.decode($0.data) }
                }
                #expect(events.count == 3)
                if case .unknown = events[0] {} else { Issue.record("Expected unknown event") }
                if case .undecodable = events[1] {} else { Issue.record("Expected undecodable event") }
                #expect(events[2] == ServerEvent.decode(frame.data))
                #expect(!events[2].isFallback)
            }
        }
    }
}

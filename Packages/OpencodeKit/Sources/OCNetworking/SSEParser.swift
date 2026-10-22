import Foundation

public struct SSEFrame: Sendable, Equatable {
    public let data: Data
    public let event: String?
    public let id: String?
}

public struct SSEParseResult: Sendable {
    public var frames: [SSEFrame] = []
    public var receivedBytes: Int = 0
    public var skippedEvents: Int = 0
}

/// Incremental UTF-8 framing. Splitting a Unicode scalar or CRLF across chunks is safe.
public struct SSEParser: Sendable {
    public static let maximumEventBytes = 16 * 1024 * 1024
    private let limit: Int
    private var line = Data()
    private var data = Data()
    private var hasData = false
    private var event: String?
    private var id: String?
    private var size = 0
    private var skipping = false
    private var afterCR = false
    private var firstLine = true
    public init(maximumEventBytes: Int = Self.maximumEventBytes) { limit = maximumEventBytes }

    public mutating func append(_ chunk: Data) -> SSEParseResult {
        var result = SSEParseResult(receivedBytes: chunk.count)
        for byte in chunk {
            if afterCR { afterCR = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                finishLine(into: &result)
                afterCR = byte == 13
            } else {
                size += 1
                if size > limit { skipping = true; data.removeAll(keepingCapacity: false) }
                // Retain enough to detect a blank line even while discarding an oversized event.
                if !skipping { line.append(byte) } else if line.isEmpty { line.append(0) }
            }
        }
        return result
    }

    private mutating func finishLine(into result: inout SSEParseResult) {
        if firstLine {
            firstLine = false
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        defer { line.removeAll(keepingCapacity: !skipping) }
        if line.isEmpty {
            if skipping { result.skippedEvents += 1 }
            else if hasData {
                if data.last == 10 { data.removeLast() }
                result.frames.append(SSEFrame(data: data, event: event, id: id))
            }
            data = Data(); hasData = false; event = nil; id = nil; size = 0; skipping = false
            return
        }
        guard !skipping, line.first != 58 else { return }
        let colon = line.firstIndex(of: 58) ?? line.endIndex
        let field = String(decoding: line[..<colon], as: UTF8.self)
        var value = colon == line.endIndex ? Data() : Data(line[line.index(after: colon)...])
        if value.first == 32 { value.removeFirst() }
        switch field {
        case "data": data.append(value); data.append(10); hasData = true
        case "event": event = String(decoding: value, as: UTF8.self)
        case "id": if !value.contains(0) { id = String(decoding: value, as: UTF8.self) }
        default: break
        }
    }
}

import Foundation

public struct CodeSearchMatch: Equatable, Sendable {
    public let line: Int
    public let range: NSRange
    public init(line: Int, range: NSRange) { self.line = line; self.range = range }
}

public struct CodeSearchResult: Equatable, Sendable {
    public var matches: [CodeSearchMatch] = []
    public var lines: [Int: [NSRange]] = [:]
    public init() {}
    @concurrent public static func find(_ query: String, in text: String) async -> Self {
        guard !query.isEmpty else { return .init() }
        var result = Self()
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if Task.isCancelled { return .init() }
            var start = line.startIndex
            while start < line.endIndex, let range = line.range(of: query, options: .caseInsensitive, range: start..<line.endIndex) {
                let match = CodeSearchMatch(line: index + 1, range: NSRange(range, in: line))
                result.matches.append(match); result.lines[match.line, default: []].append(match.range)
                start = range.upperBound
            }
        }
        return result
    }
}

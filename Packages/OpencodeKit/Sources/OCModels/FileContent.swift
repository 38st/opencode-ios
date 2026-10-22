import Foundation

public struct FileContent: Codable, Equatable, Sendable {
    public var data: Data
    public var total: Int
    public var etag: String?
    public var mime: String?
    public init(data: Data, total: Int? = nil, etag: String? = nil, mime: String? = nil) {
        self.data = data; self.total = max(data.count, total ?? data.count); self.etag = etag; self.mime = mime
    }
    public var complete: Bool { data.count >= total }
    public var binary: Bool { data.prefix(8_192).contains(0) }
    public var text: String {
        var bytes = data
        if !complete {
            // Only complete lines are displayed, which also excludes incomplete UTF-8 scalars.
            guard let end = bytes.lastIndex(of: 10) else { return "" }
            bytes = bytes.prefix(through: end)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    public static func image(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "avif", "bmp", "ico", "tif", "tiff", "heic"].contains((path as NSString).pathExtension.lowercased())
    }
    public static func quickLook(_ path: String) -> Bool {
        ["pdf", "mp3", "wav", "m4a", "aac", "flac", "mp4", "mov", "m4v", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "csv", "rtf"].contains((path as NSString).pathExtension.lowercased())
    }
}

public struct FileLink: Equatable, Sendable {
    public var path: String
    public var selection: LineSelection?
    public var isAbsolute: Bool { path.hasPrefix("/") || path.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil }
    public init(_ href: String, normalizingPath: Bool = true) {
        let raw = href.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        let fileURL = raw.lowercased().hasPrefix("file://")
        var parsed = Self.suffix(raw)
        if fileURL {
            if parsed.path == raw {
                let withoutFragment = raw.replacingOccurrences(of: #"(\.[a-z0-9]+)#[^/.]*$"#, with: "$1", options: [.regularExpression, .caseInsensitive])
                parsed = Self.suffix(String(withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]))
            } else { parsed.path = String(parsed.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]) }
            // Ranged composer file parts also resolve directly back to the viewer.
            if parsed.selection == nil, let parts = URLComponents(string: raw),
               let start = parts.queryItems?.first(where: { $0.name == "start" })?.value.flatMap(Int.init) {
                parsed.selection = Self.range(start, parts.queryItems?.first(where: { $0.name == "end" })?.value.flatMap(Int.init) ?? start)
            }
            parsed.path = String(parsed.path.dropFirst(7))
            if parsed.path.lowercased().hasPrefix("localhost/") { parsed.path = String(parsed.path.dropFirst(9)) }
            else if !parsed.path.isEmpty && !parsed.path.hasPrefix("/") { parsed.path = "//" + parsed.path }
            if parsed.path.range(of: #"^/[A-Za-z]:/"#, options: .regularExpression) != nil { parsed.path.removeFirst() }
            parsed.path = parsed.path.removingPercentEncoding ?? parsed.path
        }
        path = normalizingPath ? Self.normalize(parsed.path) : parsed.path; selection = parsed.selection
    }
    private static func range(_ start: Int?, _ end: Int?) -> LineSelection? {
        guard let start, let end, (1...1_000_000).contains(start), (1...1_000_000).contains(end) else { return nil }
        return .init(start: min(start, end), end: max(start, end))
    }
    private static func suffix(_ path: String) -> (path: String, selection: LineSelection?) {
        for (index, pattern) in [#"^(.*?)#L(\d+)(?:C\d+)?(?:-L?(\d+)(?:C\d+)?)?$"#, #"^(.*?):(\d+)(?::\d+)?(?:-(\d+)(?::\d+)?)?:?$"#].enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
                  let head = Range(match.range(at: 1), in: path) else { continue }
            let name = String(path[head])
            if index == 1 && name.range(of: #"^[a-z]:?$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            func number(_ index: Int) -> Int? { Range(match.range(at: index), in: path).flatMap { Int(path[$0]) } }
            return (name, range(number(2), match.range(at: 3).location == NSNotFound ? number(2) : number(3)))
        }
        return (path, nil)
    }
    private static func normalize(_ path: String) -> String {
        let drive = path.range(of: #"^[A-Za-z]:/"#, options: .regularExpression)
        let prefix = path.hasPrefix("//") ? "//" : drive.map { String(path[$0]) } ?? (path.hasPrefix("/") ? "/" : "")
        var parts: [Substring] = []
        for part in path.dropFirst(prefix.count).split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                if let last = parts.last, last != ".." { parts.removeLast() }
                else if prefix.isEmpty { parts.append(part) }
            } else { parts.append(part) }
        }
        return prefix + parts.joined(separator: "/")
    }
}

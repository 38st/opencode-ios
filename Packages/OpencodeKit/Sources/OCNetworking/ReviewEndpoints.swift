import Foundation
import OCFoundation
import OCModels

public enum ReviewEndpoints {
    public static func vcs(_ directory: String) -> Endpoint<Located<VCSInfo>> {
        var endpoint: Endpoint<Located<VCSInfo>> = .json(path: "/api/vcs", scope: .location(directory: directory))
        endpoint.reports503Message = true
        return endpoint
    }
    public static func diff(_ directory: String, mode: String = "working", base: String? = nil, context: Int? = nil) -> Endpoint<Located<LossyArray<FileDiff>>> {
        let query = [("mode", mode), ("base", base), ("context", context.map(String.init))].compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        var endpoint: Endpoint<Located<LossyArray<FileDiff>>> = .json(path: "/api/vcs/diff", query: query, scope: .location(directory: directory))
        endpoint.reports503Message = true
        return endpoint
    }
    public static func initialize(_ directory: String) -> Endpoint<Void> {
        var endpoint = Endpoint<Void>(method: .post, path: "/api/vcs/init", query: [.init(name: "provider", value: "git")], scope: .location(directory: directory)) { _, _ in () }
        endpoint.reports503Message = true
        return endpoint
    }
}

public struct RawFileResponse: Sendable {
    public let data: Data
    public let status: Int
    public let etag: String?
    public let contentType: String?
    public let contentRange: String?
    public let totalSize: Int?
    public let rangeStart: Int?
    init(_ response: HTTPResponse) {
        data = response.data; status = response.response.statusCode
        etag = response.response.value(forHTTPHeaderField: "ETag")
        contentType = response.response.value(forHTTPHeaderField: "Content-Type")
        contentRange = response.response.value(forHTTPHeaderField: "Content-Range")
        totalSize = contentRange?.split(separator: "/").last.flatMap { Int($0) } ?? response.response.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init)
        rangeStart = contentRange?.split(separator: " ").last?.split(separator: "-").first.flatMap { Int($0) }
    }
}

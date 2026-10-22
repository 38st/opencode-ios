import Foundation
import Testing
import OCModels
import OCFoundation
import OCNetworking
import OCPersistence
@testable import OCSync

@Test @MainActor func fileTreeSharesRequestsFindsFilesAndLoadsRanges() async throws {
    let transport = FileModelTransport()
    let client = APIClient(baseURL: try #require(URL(string: "http://127.0.0.1:1")), transport: transport)
    let store = ReadStore(serverID: UUID().uuidString, client: { client })
    let model = store.files(sessionID: "s", directory: "/work/sub")
    model.appear(); model.loadDirectory(""); model.loadDirectory("")
    try await filesEventually { model.children[""] != nil }
    #expect(await transport.listCount == 1)
    #expect(model.children[""]?.map(\.path) == ["folder/", ".hidden", "large.swift"])
    model.query = "superseded"; model.query = "large"
    try await filesEventually { !model.results.isEmpty }
    #expect(await transport.queries == ["large"])
    let path = try #require(ReviewPath("large.swift", root: .location, location: model.directory, project: model.projectDirectory))
    model.open(path)
    try await filesEventually { !model.loading }
    let first = try #require(model.content)
    #expect(first.data.count == 1_048_576 && !first.complete)
    #expect(first.text.hasSuffix("\n") && !first.text.contains("�"))
    #expect(first.text.utf8.count <= first.data.count)
    model.loadMore()
    try await filesEventually { !model.loading }
    #expect(model.content?.data.count == 2_097_152)
    model.open(path)
    try await filesEventually { !model.loading }
    #expect(await transport.notModified == 1)
    #expect(model.content?.data.count == 2_097_152)
    model.loadMore()
    try await filesEventually { !model.loading }
    #expect(model.content?.complete == true)
    #expect(model.content?.data == FileModelTransport.source)
    await store.stop()
}

@Test func fileDiskCacheReopensWithETagAndSharesQuickLookCopy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = FileCache(root: directory)
    let key = await cache.key(server: "s", directory: "/work", path: "a.pdf")
    let content = FileContent(data: Data("%PDF-1.4\nfixture".utf8), etag: "etag", mime: "application/pdf")
    try await cache.save(content, key: key, name: "a.pdf")
    let copy = try await cache.localCopy(content, key: key, name: "a.pdf")
    #expect(try Data(contentsOf: copy) == content.data)
    let reopened = await FileCache(root: directory).get(key)
    #expect(reopened == content)
    #expect(copy.pathExtension == "pdf")
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(key).path).count == 2)
}

@Test @MainActor func messageLinksAreBatchedCachedAndShared() async throws {
    let transport = FileModelTransport()
    let client = APIClient(baseURL: try #require(URL(string: "http://127.0.0.1:1")), transport: transport)
    let store = ReadStore(serverID: UUID().uuidString, client: { client })
    let model = store.files(sessionID: "s", directory: "/work/sub")
    #expect(model.knownLinks(["large.swift"]) == nil)
    async let first = model.existingLinks(["large.swift", "missing.txt", "large.swift"])
    async let second = model.existingLinks(["large.swift"])
    #expect(await first == ["large.swift"])
    #expect(await second == ["large.swift"])
    // One lookup per distinct link, shared by the concurrent messages.
    #expect(await transport.queries.sorted() == ["large.swift", "missing.txt"])
    #expect(model.knownLinks(["large.swift", "missing.txt"]) == ["large.swift"])
    #expect(model.knownLinks(["large.swift", "other.txt"]) == nil)
    // Rendering the same message again answers from the cache.
    #expect(await model.existingLinks(["missing.txt", "large.swift"]) == ["large.swift"])
    #expect(await transport.queries.count == 2)
    await store.stop()
}

@Test func removingAServerDeletesOnlyItsCachedFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = FileCache(root: directory)
    let removed = await cache.key(server: "removed", directory: "/work", path: "a.txt")
    let kept = await cache.key(server: "kept", directory: "/work", path: "a.txt")
    let content = FileContent(data: Data("text\n".utf8), etag: "etag")
    try await cache.save(content, key: removed); try await cache.save(content, key: kept)
    await cache.removeServer("removed")
    #expect(await cache.get(removed) == nil)
    #expect(await cache.get(kept) == content)
    // Neither entry survives only in memory: a fresh actor reads what is on disk.
    let reopened = FileCache(root: directory)
    #expect(await reopened.get(removed) == nil)
    #expect(await reopened.get(kept) == content)
    // A relocated cache starts empty, which keeps UI-test contents inside their namespace.
    let elsewhere = directory.appendingPathComponent("relocated")
    await reopened.relocate(to: elsewhere)
    #expect(await reopened.get(kept) == nil)
}

@Test @MainActor func fileLinksPreferLiteralThenUniqueSuffixAndOfferAmbiguousResults() async throws {
    let files = ["src/index.ts", "packages/app/src/index.ts", "packages/app/src/session/timeline/interaction.ts", "packages/session-ui/src/index.ts", "packages/session-ui/src/components/markdown.tsx", "packages/util/src/path.ts", "packages/tui/src/util/path.ts"]
    let cases: [(String, String?)] = [
        ("src/index.ts", "src/index.ts"),
        ("session/timeline/interaction.ts", "packages/app/src/session/timeline/interaction.ts"),
        ("../timeline/interaction.ts", "packages/app/src/session/timeline/interaction.ts"),
        ("markdown.tsx", "packages/session-ui/src/components/markdown.tsx"),
        ("index.ts", nil), ("util/path.ts", "packages/tui/src/util/path.ts"),
        ("missing.ts", "missing.ts"),
    ]
    for (query, expected) in cases {
        let client = readAPI { _ in .object(["location": .object(["directory": .string("/workspace")]), "data": .array(files.map { .object(["path": .string($0), "type": .string("file")]) })]) }
        let store = ReadStore(serverID: UUID().uuidString, client: { client })
        let model = store.files(sessionID: "s", directory: "/workspace")
        await model.openLink(query)
        #expect(model.selectedPath?.path == expected)
        if expected == nil { #expect(model.query == query) }
        #expect(await model.existsLink("interaction.ts:74"))
        #expect(await model.existsLink("index.ts"))
        #expect(await model.existsLink("Interaction.ts") == false)
        #expect(await model.existsLink("~/README.md") == false)
        #expect(await model.existsLink(#"\\host\share\x.ts"#) == false)
        await store.stop()
    }
}

@MainActor private func filesEventually(_ condition: () -> Bool) async throws {
    for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
    Issue.record("File model did not settle")
}
private actor FileModelTransport: HTTPTransport {
    static let source = Data(String(repeating: "let café = \"🙂\"\n", count: 150_000).utf8)
    var listCount = 0, notModified = 0
    var queries: [String] = []
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = try #require(request.url)
        var status = 200, headers = ["Content-Type": "application/json"]
        let data: Data
        if url.path.contains("/fs/read/") {
            headers = ["Content-Type": "text/plain", "ETag": "W/\"fixture\""]
            if request.value(forHTTPHeaderField: "If-None-Match") == "W/\"fixture\"" { status = 304; notModified += 1; data = Data() }
            else {
                let range = (request.value(forHTTPHeaderField: "Range") ?? "bytes=0-1048575").dropFirst(6).split(separator: "-").compactMap { Int($0) }
                let start = try #require(range.first), end = min(try #require(range.last) + 1, Self.source.count)
                data = Self.source.subdata(in: start..<end); status = 206
                headers["Content-Range"] = "bytes \(start)-\(end - 1)/\(Self.source.count)"
            }
        } else {
            let json: JSONValue
            if url.path == "/api/location" { json = .object(["directory": .string("/work/sub"), "project": .object(["directory": .string("/work")])]) }
            else {
                let entries: JSONValue
                if url.path == "/api/fs/find" {
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    #expect(query.contains(.init(name: "type", value: "file")) && query.contains(.init(name: "limit", value: "200")))
                    queries.append(query.first { $0.name == "query" }?.value ?? "")
                    entries = .array([.object(["path": .string("large.swift"), "type": .string("file")])])
                } else {
                    listCount += 1
                    entries = .array([.object(["path": .string("folder/"), "type": .string("directory")]), .object(["path": .string(".hidden"), "type": .string("file")]), .object(["path": .string("large.swift"), "type": .string("file")])])
                }
                json = .object(["location": .object(["directory": .string("/work/sub")]), "data": entries])
            }
            data = try JSONEncoder().encode(json)
        }
        return .init(data: data, response: try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)))
    }
    nonisolated func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

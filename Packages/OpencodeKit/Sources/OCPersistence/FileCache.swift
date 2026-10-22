import Foundation
import CryptoKit
import OCModels

/// Disk and memory limits are independent. Only hashed server and location/path keys reach the local filesystem.
/// Entries live below one directory per server, so removing a server removes its cached file contents.
public actor FileCache {
    public static let shared = FileCache()
    private var memory: [String: FileContent] = [:]
    private var order: [String] = []
    private var bytes = 0
    private var root: URL
    private let diskLimit = 160 * 1024 * 1024
    private struct Metadata: Codable {
        let total: Int
        let etag: String?
        let mime: String?
        let name: String
    }
    public init(root: URL? = nil) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if root == nil { try? FileManager.default.removeItem(at: caches.appendingPathComponent("ReviewFiles-v4")) }
        self.root = root ?? caches.appendingPathComponent("FileCache")
    }
    /// UI tests keep file contents inside their own namespace, which their reset removes.
    public func relocate(to root: URL) {
        self.root = root; memory = [:]; order = []; bytes = 0
    }
    public func key(server: String, directory: String, path: String) -> String {
        Self.hash(server) + "/" + Self.hash(directory + "\0" + path)
    }
    public func get(_ key: String) -> FileContent? {
        if let value = memory[key] { touch(key); return value }
        let directory = root.appendingPathComponent(key)
        guard let metadata = try? JSONDecoder().decode(Metadata.self, from: Data(contentsOf: directory.appendingPathComponent("metadata.json"))),
              let data = try? Data(contentsOf: directory.appendingPathComponent(metadata.name), options: .mappedIfSafe) else { return nil }
        let value = FileContent(data: data, total: metadata.total, etag: metadata.etag, mime: metadata.mime)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
        remember(value, key: key); return value
    }
    public func save(_ value: FileContent, key: String, name: String = "content") throws {
        remember(value, key: key)
        guard value.data.count < diskLimit else { return }
        let directory = root.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "content." + (name as NSString).pathExtension
        for old in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where old.lastPathComponent != name && old.lastPathComponent != "metadata.json" { try FileManager.default.removeItem(at: old) }
        try value.data.write(to: directory.appendingPathComponent(name), options: .atomic)
        try JSONEncoder().encode(Metadata(total: value.total, etag: value.etag, mime: value.mime, name: name)).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
        try trim()
    }
    /// Removes every memory and disk entry of one server, for example when the server is removed.
    public func removeServer(_ server: String) {
        let prefix = Self.hash(server) + "/"
        for key in order where key.hasPrefix(prefix) { bytes -= memory.removeValue(forKey: key)?.data.count ?? 0 }
        order.removeAll { $0.hasPrefix(prefix) }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.hash(server)))
    }
    private func trim() throws {
        let manager = FileManager.default
        var entries: [(URL, Int, Date)] = []
        for server in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for url in (try? manager.contentsOfDirectory(at: server, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let children = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                let size = children.reduce(0) { total, child in total + ((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                entries.append((url, size, modified))
            }
        }
        entries.sort { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > diskLimit { try manager.removeItem(at: entry.0); total -= entry.1 }
    }
    public func localCopy(_ value: FileContent, key: String, name: String) throws -> URL {
        if value.data.count < diskLimit {
            try save(value, key: key, name: name)
            return root.appendingPathComponent(key).appendingPathComponent("content." + (name as NSString).pathExtension)
        }
        // Explicitly approved oversized downloads are active previews, not cache entries.
        // There is only one temporary preview, removed on the next open/close.
        let directory = previewDirectory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent((name as NSString).lastPathComponent)
        try value.data.write(to: url, options: .atomic); return url
    }
    public func releasePreview() { try? FileManager.default.removeItem(at: previewDirectory) }
    private var previewDirectory: URL { root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-ActivePreview") }
    private func touch(_ key: String) { order.removeAll { $0 == key }; order.append(key) }
    private func remember(_ value: FileContent, key: String) {
        bytes -= memory.removeValue(forKey: key)?.data.count ?? 0
        if value.data.count <= 20 * 1024 * 1024 { memory[key] = value; bytes += value.data.count; touch(key) }
        while order.count > 40 || bytes > 20 * 1024 * 1024 {
            guard !order.isEmpty else { break }; bytes -= memory.removeValue(forKey: order.removeFirst())?.data.count ?? 0
        }
    }
    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

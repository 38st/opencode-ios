import Foundation
import Observation
import OCModels
import OCNetworking
import OCPersistence

@MainActor @Observable public final class FilesModel {
    public let sessionID: String
    public let directory: String
    public private(set) var projectDirectory: String
    public private(set) var children: [String: [FileEntry]] = [:]
    public private(set) var expanded: Set<String> = []
    public private(set) var listingErrors: Set<String> = []
    public private(set) var results: [FileEntry] = []
    public var query = "" { didSet { if query != oldValue { search() } } }
    public var selection: LineSelection?
    public private(set) var selectedPath: ReviewPath?
    public private(set) var openFiles: [ReviewPath] = []
    public private(set) var content: FileContent?
    public private(set) var localURL: URL?
    public private(set) var loading = false
    public private(set) var error: String?
    public var needsDownloadConfirmation = false
    public var scrollOffsets: [String: Double] = [:]
    public var selections: [String: LineSelection] = [:]
    public var presentRequest: UUID?
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private var listings: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var listingGeneration = 0
    /// Link answers are shared by every message of the session and refreshed after a minute.
    @ObservationIgnored private var linkAnswers: [String: (exists: Bool, checked: Date)] = [:]
    @ObservationIgnored private var linkOrder: [String] = []
    @ObservationIgnored private var linkLookups: [String: Task<Bool, Never>] = [:]
    private static let linkLifetime: TimeInterval = 60, linkCapacity = 512, concurrentLinkLookups = 4
    public init(store: ReadStore, sessionID: String, directory: String) {
        self.store = store; self.sessionID = sessionID; self.directory = directory; projectDirectory = directory
    }
    deinit { refreshTask?.cancel(); searchTask?.cancel(); readTask?.cancel(); for t in listings.values { t.cancel() } }
    public func appear() {
        viewers += 1; loadDirectory("", force: true)
        for path in expanded { loadDirectory(path, force: true) }
        if !query.isEmpty { search() }
        if let selectedPath { open(selectedPath, selection: selection) }
    }
    public func disappear() {
        viewers = max(0, viewers - 1)
        if viewers == 0 {
            refreshTask?.cancel(); searchTask?.cancel(); cancel()
            listingGeneration += 1; for task in listings.values { task.cancel() }; listings = [:]
        }
    }
    public func stop() {
        refreshTask?.cancel(); searchTask?.cancel(); readTask?.cancel(); for t in listings.values { t.cancel() }; listings = [:]
        for t in linkLookups.values { t.cancel() }; linkLookups = [:]
    }
    public func invalidate() {
        guard viewers > 0 else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            self.loadDirectory("", force: true)
            for path in self.expanded { self.loadDirectory(path, force: true) }
            if let path = self.selectedPath { self.open(path, selection: self.selection) }
        }
    }
    public func toggle(_ path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path); loadDirectory(path) }
    }
    public func loadDirectory(_ path: String, force: Bool = false) {
        guard listings[path] == nil, force || children[path] == nil, let store else { return }
        let revision = listingGeneration
        listings[path] = Task { [weak self] in
            guard let self else { return }; defer { if self.listingGeneration == revision { self.listings[path] = nil } }
            do {
                if path.isEmpty { self.projectDirectory = try await store.resolveDirectory(self.directory).project?.directory ?? self.directory }
                let entries = try await store.listDirectory(path, directory: self.directory)
                try Task.checkCancellation(); self.children[path] = entries; self.listingErrors.remove(path)
            } catch { if !Task.isCancelled { self.listingErrors.insert(path) } }
        }
    }
    private func search() {
        searchTask?.cancel()
        guard !query.isEmpty, let store else { results = []; return }
        let query = query
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let values = try await store.findFiles(query, directory: self?.directory ?? "", type: "file", limit: 200)
                try Task.checkCancellation(); self?.results = values
            } catch { if !Task.isCancelled { self?.error = ComposerModel.searchFailed } }
        }
    }
    /// Cached answers for every candidate, or nil while any is unknown or stale.
    public func knownLinks(_ hrefs: [String]) -> Set<String>? {
        var result: Set<String> = []
        for href in hrefs {
            guard let answer = linkAnswers[href], Date().timeIntervalSince(answer.checked) < Self.linkLifetime else { return nil }
            if answer.exists { result.insert(href) }
        }
        return result
    }
    /// Resolves message links a few at a time, sharing recent and in-flight answers between messages.
    public func existingLinks(_ hrefs: [String]) async -> Set<String> {
        var seen: Set<String> = [], result: Set<String> = [], pending: [String] = []
        for href in hrefs where seen.insert(href).inserted {
            if let answer = freshAnswer(href) { if answer { result.insert(href) } } else { pending.append(href) }
        }
        var start = 0
        while start < pending.count {
            let batch = pending[start..<min(pending.count, start + Self.concurrentLinkLookups)].map { ($0, lookup($0)) }
            for (href, task) in batch where await task.value { result.insert(href) }
            start += Self.concurrentLinkLookups
        }
        return result
    }
    private func freshAnswer(_ href: String) -> Bool? {
        guard let answer = linkAnswers[href], Date().timeIntervalSince(answer.checked) < Self.linkLifetime else { return nil }
        return answer.exists
    }
    private func lookup(_ href: String) -> Task<Bool, Never> {
        if let running = linkLookups[href] { return running }
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            let exists = await self.existsLink(href)
            self.linkLookups[href] = nil
            if !Task.isCancelled {
                self.linkAnswers[href] = (exists, Date()); self.linkOrder.removeAll { $0 == href }; self.linkOrder.append(href)
                while self.linkOrder.count > Self.linkCapacity { self.linkAnswers.removeValue(forKey: self.linkOrder.removeFirst()) }
            }
            return exists
        }
        linkLookups[href] = task
        return task
    }
    public func existsLink(_ href: String) async -> Bool {
        let link = FileLink(href)
        guard !link.path.isEmpty, !link.path.hasPrefix("~"), !link.path.hasPrefix("//"), let store else { return false }
        if link.isAbsolute {
            guard let target = ReviewPath(link.path, root: .location, location: directory, project: projectDirectory) else { return false }
            let entries = try? await store.listDirectory((target.path as NSString).deletingLastPathComponent, directory: target.directory)
            return entries?.contains { $0.path == target.path && $0.type == .file } ?? false
        }
        let query = link.path.replacingOccurrences(of: #"^(\.\./)+"#, with: "", options: .regularExpression)
        let entries = try? await store.findFiles(query, directory: directory, type: "file", limit: 200)
        return entries?.contains(where: { $0.path == query || $0.path.hasSuffix("/" + query) }) ?? false
    }
    public func openLink(_ href: String, present: Bool = true) async {
        let link = FileLink(href)
        var path = link.path
        if !link.isAbsolute, let store {
            let query = path.replacingOccurrences(of: #"^(\.\./)+"#, with: "", options: .regularExpression)
            let found = (try? await store.findFiles(query, directory: directory, type: "file", limit: 200)) ?? []
            let matches = Set(found.map(\.path).filter { $0 == query || $0.hasSuffix("/" + query) })
            if matches.contains(query) { path = query }
            else if matches.count > 1 { self.query = query; allFiles(); if present { presentRequest = UUID() }; return }
            else if let only = matches.first { path = only }
        }
        guard let target = ReviewPath(path, root: .location, location: directory, project: projectDirectory) else { error = localized("File not found: \(path)", comment: "%@ is a file path"); return }
        open(target, selection: link.selection, present: present)
    }
    public func allFiles() {
        if let path = selectedPath, let selection { selections[path.absolute] = selection }
        cancel(); selectedPath = nil; content = nil; localURL = nil
        store?.owned { await FileCache.shared.releasePreview() }
    }
    public func close(_ path: ReviewPath) { openFiles.removeAll { $0 == path }; if selectedPath == path { if let last = openFiles.last { open(last) } else { allFiles() } } }
    public func open(_ path: ReviewPath, selection: LineSelection? = nil, present: Bool = false) {
        if let previous = selectedPath, let selected = self.selection { selections[previous.absolute] = selected }
        if selectedPath != path { content = nil }
        self.selection = selection ?? selections[path.absolute]
        selectedPath = path; if !openFiles.contains(path) { openFiles.append(path) }
        if present { presentRequest = UUID() }
        readTask?.cancel(); generation += 1; let revision = generation
        loading = true; error = nil; needsDownloadConfirmation = false; localURL = nil
        readTask = Task { [weak self] in
            guard let self, let store = self.store else { return }
            await FileCache.shared.releasePreview()
            defer { if self.generation == revision { self.loading = false; self.readTask = nil } }
            do {
                let key = await FileCache.shared.key(server: store.serverID, directory: path.directory, path: path.path)
                let cached = await FileCache.shared.get(key)
                if self.generation == revision { self.content = cached }
                let response = try await store.writeAPI().readFile(path.path, directory: path.directory, range: 0..<1_048_576, etag: cached?.etag)
                try Task.checkCancellation()
                var value: FileContent
                if response.status == 304, let cached { value = cached }
                else if response.status == 416, response.totalSize == 0 { value = .init(data: Data(), etag: response.etag) }
                else if response.status == 200 || response.status == 206 { value = .init(data: response.data, total: response.totalSize, etag: response.etag, mime: response.contentType) }
                else { throw FileReadError.invalidRange }
                guard self.generation == revision else { return }
                self.content = value
                let media = FileContent.image(path.path) || FileContent.quickLook(path.path)
                if media && value.total > 100 * 1024 * 1024 && !value.complete { self.needsDownloadConfirmation = true }
                else if media || !value.binary && value.total <= 2 * 1024 * 1024 { value = try await self.remainder(value, path: path, all: true) }
                try Task.checkCancellation(); guard self.generation == revision else { return }
                self.content = value
                try await FileCache.shared.save(value, key: key, name: path.path)
                if media && value.complete {
                    let url = try await FileCache.shared.localCopy(value, key: key, name: path.path)
                    if self.generation == revision { self.localURL = url }
                }
            } catch { if !Task.isCancelled && self.generation == revision { self.error = Self.message(error, path: path.path) } }
        }
    }
    private static func message(_ error: any Error, path: String) -> String {
        if case APIError.server(_, 404, _) = error { return localized("File not found: \((path as NSString).lastPathComponent)", comment: "%@ is a file path") }
        return WriteErrorMessage.message(error)
    }
    public func loadMore(all: Bool = false) {
        guard !loading, let value = content, let path = selectedPath, let store else { return }
        loading = true; needsDownloadConfirmation = false
        generation += 1; let revision = generation
        readTask = Task { [weak self] in
            guard let self else { return }; defer { if self.generation == revision { self.loading = false; self.readTask = nil } }
            do {
                let value = try await self.remainder(value, path: path, all: all)
                try Task.checkCancellation(); guard self.generation == revision else { return }; self.content = value
                let key = await FileCache.shared.key(server: store.serverID, directory: path.directory, path: path.path)
                try await FileCache.shared.save(value, key: key, name: path.path)
                if value.complete && (FileContent.image(path.path) || FileContent.quickLook(path.path)) {
                    let url = try await FileCache.shared.localCopy(value, key: key, name: path.path)
                    if self.generation == revision { self.localURL = url }
                }
            } catch { if !Task.isCancelled { self.error = WriteErrorMessage.message(error) } }
        }
    }
    public func cancel() { generation += 1; readTask?.cancel(); readTask = nil; loading = false }
    private func remainder(_ input: FileContent, path: ReviewPath, all: Bool) async throws -> FileContent {
        guard let store else { return input }; var value = input
        while !value.complete {
            try Task.checkCancellation()
            let response = try await store.writeAPI().readFile(path.path, directory: path.directory, range: value.data.count..<min(value.total, value.data.count + 1_048_576))
            guard response.status == 206, response.rangeStart == value.data.count, !response.data.isEmpty, value.etag == response.etag else { throw FileReadError.changed }
            value.data.append(response.data); value.total = response.totalSize ?? value.total
            try Task.checkCancellation()
            if all { content = value } else { break }
        }
        return value
    }
}
public enum FileReadError: Error, LocalizedError {
    case invalidRange, changed
    public var errorDescription: String? { self == .changed ? localized("The file changed. Open it again to refresh.") : localized("The requested range is unavailable.") }
}
extension ReadStore {
    public func files(sessionID: String, directory: String) -> FilesModel {
        if let value = fileModels[sessionID] { return value }
        let value = FilesModel(store: self, sessionID: sessionID, directory: directory); fileModels[sessionID] = value; return value
    }
}

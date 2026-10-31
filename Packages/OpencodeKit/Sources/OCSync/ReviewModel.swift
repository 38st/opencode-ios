import Foundation
import Observation
import CryptoKit
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence

@MainActor @Observable public final class ReviewModel {
    public let sessionID: String
    public let directory: String
    public private(set) var projectDirectory: String
    public private(set) var state = ReviewState()
    public private(set) var vcs = VCSInfo(raw: .object([:]))
    public private(set) var files: [FileDiff] = []
    public private(set) var images: [String: Data] = [:]
    public private(set) var imageErrors: Set<String> = []
    public private(set) var source: ReviewSource = .working
    public private(set) var loading = false
    public private(set) var awaitingProvider = false
    public private(set) var providerKnown = false
    public private(set) var loaded = false
    public private(set) var creating = false
    public private(set) var error: String?
    public var selection: LineSelection?
    public var filter = ""
    public var scrollOffsets: [String: Double] = [:]
    public var sidebarWidth: Double = 240
    public var sidebarVisible = true
    public var presentRequest: UUID?
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private var imageTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var restored = false
    private var reviewed: Set<String> = []
    @ObservationIgnored private var generation = 0
    public init(store: ReadStore, sessionID: String, directory: String) {
        self.store = store; self.sessionID = sessionID; self.directory = directory; projectDirectory = directory
    }
    deinit { task?.cancel(); saving?.cancel(); for task in imageTasks.values { task.cancel() } }
    public var sources: [ReviewSource] {
        var result = ReviewSource.available(vcs: vcs, session: !sessionID.isEmpty)
        if case .turn = state.source { result.append(state.source) }
        return result
    }
    public var orderedFiles: [FileDiff] {
        let lookup = Dictionary(files.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        return ReviewOrder.paths(Array(lookup.keys)).compactMap { lookup[$0] }
    }
    public var filteredFiles: [FileDiff] { orderedFiles.filter { filter.isEmpty || $0.file.localizedCaseInsensitiveContains(filter) } }
    public var selected: FileDiff? { orderedFiles.first { $0.file == state.selectedFile } ?? orderedFiles.first }
    public var additions: Int { FileDiff.totals(files).additions }
    public var deletions: Int { FileDiff.totals(files).deletions }
    public var reviewedCount: Int { files.filter(isReviewed).count }
    public var tab: String { state.tab }
    public func selectTab(_ tab: String) { state.tab = tab; persist() }
    /// Selects a tab and asks the window to show the panel.
    public func present(_ tab: String) { selectTab(tab); presentRequest = UUID() }
    public func select(_ file: String) {
        if state.selectedFile != file { selection = nil }
        state.selectedFile = file; ensureImages(); persist()
    }
    public func move(_ offset: Int) {
        guard let current = selected, let index = orderedFiles.firstIndex(where: { $0.file == current.file }), !orderedFiles.isEmpty else { return }
        let file = orderedFiles[(index + offset + orderedFiles.count) % orderedFiles.count].file
        state.openFiles.insert(file)
        select(file)
    }
    public func choose(_ source: ReviewSource, file: String? = nil, present: Bool = false) {
        if let file {
            let path = files.first { self.path($0.file)?.absolute == file }?.file ?? file
            state.selectedFile = path; state.openFiles.insert(path)
            selection = nil; scrollOffsets["accordion"] = 0
        }
        state.source = source
        if present { state.tab = "Changes"; presentRequest = UUID() }
        persist(); refresh()
    }
    public func isOpen(_ file: String) -> Bool { state.openFiles.contains(file) }
    public func toggle(_ file: String) {
        if state.openFiles.contains(file) { state.openFiles.remove(file) } else { state.openFiles.insert(file) }
        ensureImages(); persist()
    }
    public func expandAll(_ expanded: Bool) { state.openFiles = expanded ? Set(files.map(\.file)) : []; ensureImages(); persist() }
    public func isReviewed(_ file: FileDiff) -> Bool { reviewed.contains(markKey(file)) }
    public func mark(_ file: FileDiff, reviewed value: Bool) {
        if value { reviewed.insert(markKey(file)); state.openFiles.remove(file.file) } else { reviewed.remove(markKey(file)) }
        // Reviewed state is intentionally part of the review graph, never the transcript.
        persist()
    }
    private func markKey(_ file: FileDiff) -> String {
        source.key + "\0" + file.file + "\0" + SHA256.hash(data: Data(file.patch.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func path(_ file: String) -> ReviewPath? {
        ReviewPath(file, root: source.projectRelative ? .project : .repository, location: directory, project: projectDirectory)
    }
    public func appear() { viewers += 1; refresh() }
    public func disappear() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { task?.cancel(); task = nil; for task in imageTasks.values { task.cancel() }; imageTasks = [:] }
    }
    public func invalidate() { if viewers > 0 { refresh(debounce: true) } }
    public func stop() async { for task in imageTasks.values { task.cancel() }; imageTasks = [:]; task?.cancel(); task = nil; await saving?.value; saving = nil }
    public func refresh(debounce: Bool = false) {
        task?.cancel(); generation += 1
        let revision = generation
        task = Task { [weak self] in
            guard let self else { return }
            if debounce { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            self.loading = true
            defer { if self.generation == revision { self.loading = false; self.task = nil } }
            do {
                guard let store = self.store else { return }
                if !self.restored {
                    if let saved = try await store.cache?.writer.reviewState(serverID: store.serverID, sessionID: self.sessionID) {
                        // A turn-card navigation made before hydration takes precedence.
                        if self.presentRequest == nil { self.state = saved.0 }; self.reviewed = saved.1
                    }
                    self.restored = true
                }
                let api = try await store.writeAPI()
                let location = try await api.send(ReadEndpoints.location(self.directory))
                let vcs = try await api.send(ReviewEndpoints.vcs(self.directory)).data
                try Task.checkCancellation()
                self.projectDirectory = location.project?.directory ?? self.directory
                self.awaitingProvider = vcs.provider == nil && store.projects.contains { $0.id == location.project?.id && $0.vcs != nil }
                // A booting plugin can briefly omit its provider. Keep the last result until
                // vcs.branch.updated activates it instead of flashing the no-Git state.
                if self.awaitingProvider { return }
                self.vcs = vcs; self.providerKnown = true
                let available = self.sources
                let selected = available.contains(self.state.source) ? self.state.source : available.first ?? .working
                if available.isEmpty { self.loaded = true; return }
                let values: [FileDiff]
                if case .turn(let from) = selected { values = try await store.turnDiff(sessionID: self.sessionID, from: from).result() }
                else { values = try await store.reviewDiff(sessionID: self.sessionID, directory: self.directory, source: selected) }
                try Task.checkCancellation()
                guard self.generation == revision else { return }
                self.source = selected; self.files = values; self.error = nil; self.loaded = true
                if let absolute = self.state.selectedFile, let matched = self.files.first(where: { self.path($0.file)?.absolute == absolute }) {
                    self.state.selectedFile = matched.file; self.state.openFiles.remove(absolute); self.state.openFiles.insert(matched.file)
                }
                if self.state.selectedFile == nil { self.state.selectedFile = self.orderedFiles.first?.file }
                for task in self.imageTasks.values { task.cancel() }; self.imageTasks = [:]; self.images = [:]
                self.ensureImages()
            } catch is CancellationError {} catch APIError.cancelled {} catch { if self.generation == revision { self.error = WriteErrorMessage.message(error); self.loaded = true } }
        }
    }
    private func ensureImages() {
        guard viewers > 0 else { return }
        for file in files where FileContent.image(file.file) && file.status != "deleted" && (isOpen(file.file) || selected?.file == file.file) { loadImage(file.file) }
    }
    public func loadImage(_ file: String) {
        guard images[file] == nil, imageTasks[file] == nil, let path = path(file), let store else { return }
        imageTasks[file] = Task { [weak self] in
            guard let self else { return }; defer { self.imageTasks[file] = nil }
            do {
                let api = try await store.writeAPI()
                let key = await FileCache.shared.key(server: store.serverID, directory: path.directory, path: path.path)
                let cached = await FileCache.shared.get(key)
                let response = try await api.readFile(path.path, directory: path.directory, range: 0..<1_048_576, etag: cached?.etag)
                var value = response.status == 304 ? cached ?? .init(data: Data()) : FileContent(data: response.data, total: response.totalSize, etag: response.etag, mime: response.contentType)
                guard value.total <= 100 * 1_048_576 else { throw FileReadError.invalidRange }
                while !value.complete {
                    try Task.checkCancellation()
                    let next = try await api.readFile(path.path, directory: path.directory, range: value.data.count..<min(value.total, value.data.count + 1_048_576))
                    guard next.status == 206, next.rangeStart == value.data.count, next.etag == value.etag, !next.data.isEmpty else { throw FileReadError.changed }
                    value.data.append(next.data)
                }
                try Task.checkCancellation()
                try await FileCache.shared.save(value, key: key)
                self.images[file] = value.data; self.imageErrors.remove(file)
            } catch { if !Task.isCancelled { self.imageErrors.insert(file) } }
        }
    }
    public func initializeGit() {
        guard !creating, let store else { return }
        creating = true
        store.performWrite { try await store.writeAPI().send(ReviewEndpoints.initialize(self.directory)) } completion: { [weak self] result in
            guard let self else { return }; self.creating = false
            if case .failure = result { self.error = localized("Request failed") } else { self.refresh() }
        }
    }
    private func persist() {
        guard let store else { return }
        let previous = saving, state = state, reviewed = reviewed, sessionID = sessionID
        saving = Task { [weak self] in
            await previous?.value
            do { try await store.cache?.writer.saveReviewState(serverID: store.serverID, sessionID: sessionID, state: state, reviewed: reviewed) }
            catch { self?.error = localized("Could not save review state.") }
        }
    }
}

@MainActor @Observable public final class TurnDiffModel {
    public private(set) var files: [FileDiff] = []
    public private(set) var loaded = false
    public private(set) var error: String?
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var refreshPending = false
    public let sessionID: String
    public let from: String
    init(store: ReadStore, sessionID: String, from: String) { self.store = store; self.sessionID = sessionID; self.from = from }
    deinit { task?.cancel() }
    public func load(force: Bool = false) {
        if task != nil { refreshPending = refreshPending || force; return }
        guard !loaded || force, let store else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                if self.refreshPending && !Task.isCancelled { self.refreshPending = false; self.load(force: true) }
            }
            do {
                self.files = try await store.reviewDiff(sessionID: self.sessionID, directory: "", source: .turn(self.from))
                self.loaded = true; self.error = nil
            } catch { self.error = WriteErrorMessage.message(error) }
        }
    }
    func result() async throws -> [FileDiff] {
        load(); await task?.value
        if let error { throw ReviewLoadError(message: error) }; return files
    }
    func stop() { task?.cancel(); task = nil }
}
private struct ReviewLoadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension ReadStore {
    public func review(sessionID: String, directory: String) -> ReviewModel {
        if let value = reviews[sessionID] { return value }
        let value = ReviewModel(store: self, sessionID: sessionID, directory: directory); reviews[sessionID] = value; return value
    }
    public func turnDiff(sessionID: String, from: String) -> TurnDiffModel {
        let key = sessionID + ":" + from
        if let value = turnDiffs[key] { return value }
        let value = TurnDiffModel(store: self, sessionID: sessionID, from: from); turnDiffs[key] = value; return value
    }
    func reviewDiff(sessionID: String, directory: String, source: ReviewSource) async throws -> [FileDiff] {
        let api = try await writeAPI()
        func fetch(_ context: Int?) async throws -> [FileDiff] {
            switch source {
            case .working, .branch:
                return try await api.send(ReviewEndpoints.diff(directory, mode: source == .working ? "working" : "branch", context: context)).data.values
            case .lastTurn: return try await api.send(ReadEndpoints.diff(sessionID, context: context)).data
            case .turn(let from): return try await api.send(ReadEndpoints.diff(sessionID, from: from, context: context)).data
            }
        }
        var files = try await fetch(nil)
        let truncated = Set(files.filter { !$0.patch.isEmpty && !$0.patch.contains("@@ ") && !$0.patch.contains("Binary files ") && ($0.additions > 0 || $0.deletions > 0) }.map(\.file))
        if !truncated.isEmpty {
            let retry = try await fetch(3)
            let replacements = Dictionary(retry.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
            files = files.map { file in
                guard truncated.contains(file.file), var replacement = replacements[file.file] else { return file }
                replacement.raw.set("bounded", .bool(true)); return replacement
            }
        }
        return files
    }
    func refreshReviewViews(_ event: ServerEvent) {
        guard let type = event.header?.type else { return }
        guard type == "session.step.ended" || type == "session.idle" || type.hasPrefix("session.execution.") || type.hasPrefix("session.revert.") || type == "vcs.branch.updated" || type == "worktree.updated" else { return }
        for review in reviews.values where event.sessionID == nil || review.sessionID == event.sessionID { review.invalidate() }
        for model in fileModels.values where event.sessionID == nil || model.sessionID == event.sessionID { model.invalidate() }
        if let id = event.sessionID, let snapshot = sessions[id]?.transcript?.snapshot {
            var turn: [SessionMessage] = []
            for message in snapshot.reversed() {
                if message.type == "idle" { if turn.isEmpty { continue }; break }
                turn.append(message)
            }
            if let from = turn.last(where: { $0.type == "user" })?.id { turnDiffs[id + ":" + from]?.load(force: true) }
        }
    }
}

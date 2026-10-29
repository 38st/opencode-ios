// Terminals per location: the server's PTYs (kept current by pty.* events) and one session per PTY that owns its
// socket. Behaviour follows the reference terminal, packages/gui-plugins/src/terminal/{model,terminal}.tsx at v2.2.0.
import Foundation
import Observation
import OCFoundation
import OCModels
import OCNetworking
import OCPersistence

/// The renderer (SwiftTerm, in FeatureTerminal). OCSync never imports it.
@MainActor public protocol TerminalEngine: AnyObject {
    /// Parses synchronously, so a snapshot taken afterwards matches the cursor that counted this output.
    func feed(_ text: String)
    /// Feeds output the server replayed; replies the terminal makes to queries in it are not sent.
    func replay(_ text: String)
    /// Clears the screen and its scrollback, before a replay that does not continue them.
    func reset()
    /// The screen and up to `scrollback` rows above it as escape sequences that `restore` replays; nil when blank.
    func snapshot(scrollback: Int) -> String?
    func restore(_ screen: String, cols: Int, rows: Int)
    var size: (cols: Int, rows: Int) { get }
    /// DECCKM: the key bar's arrows send application sequences while it is set.
    var applicationCursor: Bool { get }
}

@MainActor @Observable public final class TerminalListModel {
    public let directory: String
    public private(set) var terminals: [PtyInfo] = []
    public private(set) var shells: [ShellOption] = []
    public private(set) var loaded = false
    public private(set) var error: String?
    public private(set) var creating = false
    /// The terminal the iPad panel shows instead of the list.
    public var selected: String?
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var sessions: [String: TerminalSession] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init(store: ReadStore, directory: String) { self.store = store; self.directory = directory }

    public func info(_ id: String) -> PtyInfo? { terminals.first { $0.id == id } }
    public var hasExited: Bool { terminals.contains { $0.status == .exited } }
    public func session(_ id: String) -> TerminalSession {
        if let session = sessions[id] { return session }
        let session = TerminalSession(store: store, list: self, id: id); sessions[id] = session
        return session
    }

    public func appear() { viewers += 1; refresh() }
    public func disappear() { viewers = max(0, viewers - 1) }
    public func refresh() {
        owned { list in
            guard let api = try await list.store?.client?() else { return }
            let found = try await api.send(TerminalEndpoints.list(list.directory)).data.values
            list.terminals = found.sorted { $0.id < $1.id }; list.loaded = true; list.error = nil
            // A restarted server has forgotten its PTYs; so do their saved screens.
            if let store = list.store { try? await store.cache?.writer.forgetTerminals(serverID: store.serverID, directory: list.directory, keeping: Set(found.map(\.id))) }
        } failure: { $0.error = "Could not load terminals." }
        if shells.isEmpty {
            owned { list in
                guard let api = try await list.store?.client?() else { return }
                list.shells = try await api.send(TerminalEndpoints.shells).values
            } failure: { _ in }
        }
    }
    /// Starts a terminal titled as the desktop titles its tabs, with `shell` or the server's configured one, and shows it.
    public func create(shell: ShellOption? = nil) {
        guard !creating else { return }
        creating = true
        owned { list in
            defer { list.creating = false }
            guard let api = try await list.store?.client?() else { return }
            let title = TerminalTitles.next(after: list.terminals.map(\.title))
            let info = try await api.send(TerminalEndpoints.create(list.directory, command: shell?.path, title: title)).data
            list.upsert(info); list.selected = info.id
        } failure: { $0.error = "Could not start a terminal." }
    }
    public func rename(_ id: String, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        owned { list in
            guard let api = try await list.store?.client?() else { return }
            list.upsert(try await api.send(TerminalEndpoints.update(id, directory: list.directory, title: title)).data)
        } failure: { $0.error = "Could not rename the terminal." }
    }
    /// Ends the process if it runs and removes the terminal; its saved screen goes too.
    public func close(_ id: String) {
        owned { list in
            guard let api = try await list.store?.client?() else { return }
            do { try await api.send(TerminalEndpoints.delete(id, directory: list.directory)) }
            catch APIError.server(_, 404, _) {}
            list.removed(id)
        } failure: { $0.error = "Could not close the terminal." }
    }
    public func clearExited() { for terminal in terminals where terminal.status == .exited { close(terminal.id) } }

    func handle(type: String, payload: JSONValue) {
        switch type {
        case "pty.created", "pty.updated":
            let info = PtyInfo(raw: payload["info"] ?? .object([:]))
            if !info.id.isEmpty { upsert(info) }
        case "pty.exited":
            guard let id = payload["id"]?.stringValue, let index = terminals.firstIndex(where: { $0.id == id }) else { return }
            terminals[index].raw.set("status", .string("exited"))
            terminals[index].raw.set("exitCode", payload["exitCode"])
        case "pty.deleted":
            if let id = payload["id"]?.stringValue { removed(id) }
        default: break
        }
    }
    /// The server is reachable again: refresh what is on screen and reconnect terminals that are shown.
    func connected() {
        if viewers > 0 { refresh() }
        for session in sessions.values { session.serverConnected() }
    }
    /// Saves each shown terminal and closes its socket, and waits until the saves are written.
    func suspend() async {
        for session in sessions.values { session.suspend() }
        for session in sessions.values { await session.saved() }
    }
    func stop() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        for session in sessions.values { session.stop() }
    }

    private func upsert(_ info: PtyInfo) {
        if let index = terminals.firstIndex(where: { $0.id == info.id }) { terminals[index] = info }
        else { terminals.append(info); terminals.sort { $0.id < $1.id } }
    }
    private func removed(_ id: String) {
        terminals.removeAll { $0.id == id }
        if selected == id { selected = nil }
        if let session = sessions.removeValue(forKey: id) { session.removed(); return }
        guard let store else { return }
        owned { _ in try await store.cache?.writer.forgetTerminal(serverID: store.serverID, ptyID: id) } failure: { _ in }
    }
    private func owned(_ work: @escaping @MainActor (TerminalListModel) async throws -> Void, failure: @escaping @MainActor (TerminalListModel) -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do { try await work(self) } catch is CancellationError {} catch { failure(self) }
            self.tasks.removeValue(forKey: id)
        }
    }
}

@MainActor @Observable public final class TerminalSession: Identifiable {
    public nonisolated let id: String
    public private(set) var link = TerminalLink()
    /// Output this screen cannot show; the user dismisses it.
    public var gap: TerminalGap?
    public private(set) var removedFromServer = false
    public private(set) var latch = TerminalModifierLatch()
    /// Why a fallback to a ticket was needed, when it was.
    public private(set) var ticketReason: String?
    @ObservationIgnored public private(set) weak var engine: (any TerminalEngine)?
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private weak var list: TerminalListModel?
    @ObservationIgnored private var connection: (any WebSocketConnection)?
    @ObservationIgnored private var input: AsyncStream<String>.Continuation?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var writer: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var sizeTimer: Task<Void, Never>?
    /// One size request at a time, carrying the newest size: separate requests could arrive out of order.
    @ObservationIgnored private var sizeSender: Task<Void, Never>?
    @ObservationIgnored private var sizeToSend: (cols: Int, rows: Int)?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var lastSize: (cols: Int, rows: Int)?
    @ObservationIgnored private var pendingSize: (cols: Int, rows: Int)?
    @ObservationIgnored private var lastPersist: ContinuousClock.Instant?
    @ObservationIgnored private var generation = 0
    /// While the screen restored from the saved point is the latest one stored, an update without new output is skipped.
    @ObservationIgnored private var unsaved = false

    init(store: ReadStore?, list: TerminalListModel, id: String) { self.store = store; self.list = list; self.id = id }

    public var info: PtyInfo? { list?.info(id) }
    public var directory: String { list?.directory ?? "" }

    /// Gives this terminal a new, empty renderer: restores the saved screen, then connects from the saved cursor, or
    /// shows an exited terminal's last screen without connecting.
    public func attach(_ engine: any TerminalEngine) async {
        stop()
        self.engine = engine; link = TerminalLink(); gap = nil; lastPersist = nil; lastSize = nil
        var saved: TerminalResume?
        if let store, let writer = store.cache?.writer { saved = try? await writer.terminal(serverID: store.serverID, ptyID: id, now: store.clock.date()) }
        guard self.engine === engine, !removedFromServer else { return }
        if let saved, !saved.screen.isEmpty { engine.restore(saved.screen, cols: saved.cols, rows: saved.rows) }
        if let info, info.status == .exited { run(link.exited(code: info.exitCode, cursor: saved?.cursor)); return }
        run(link.start(cursor: saved?.cursor, restoredScreen: !(saved?.screen.isEmpty ?? true)))
    }
    /// The renderer goes away: save and disconnect. A later `attach` starts from what was saved.
    public func detach() { run(link.suspend()); stop(); engine = nil }
    public func suspend() { if engine != nil { run(link.suspend()) } }
    func saved() async { await persistTask?.value }
    public func resume() { if engine != nil { run(link.resume()) } }
    func serverConnected() { guard engine != nil else { return }; run(link.resume()); run(link.retryNow()) }
    func removed() { removedFromServer = true; run(link.removed()); stop() }
    func stop() {
        reader?.cancel(); writer?.cancel(); timer?.cancel(); statusTask?.cancel(); sizeTimer?.cancel()
        sizeSender?.cancel()
        reader = nil; writer = nil; timer = nil; statusTask = nil; sizeTimer = nil; sizeSender = nil; sizeToSend = nil
        input?.finish(); input = nil
        connection?.close(); connection = nil
    }

    // MARK: Input

    /// Typed text from the view; a latched Ctrl or Alt modifies its first character.
    public func type(_ text: String) {
        let modifiers = latch.consume()
        write(modifiers.isEmpty ? Array(text.utf8) : TerminalKeys.encode(.text(text), modifiers: modifiers))
    }
    public func press(_ key: TerminalKey) {
        write(TerminalKeys.encode(key, modifiers: latch.consume(), applicationCursor: engine?.applicationCursor ?? false))
    }
    /// Bytes the renderer produces itself: hardware keys, paste, and its replies to the program.
    public func send(_ bytes: [UInt8]) { write(bytes) }
    public func toggle(_ modifier: TerminalModifiers) { latch.toggle(modifier) }
    private func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, link.phase == .replaying || link.phase == .live else { return }
        input?.yield(String(decoding: bytes, as: UTF8.self))
    }

    // MARK: Size

    /// The first size goes at once; later ones at most every 100 ms with the latest size, and equal sizes not at all
    /// (terminal.tsx `scheduleSize`). `force` sends after a (re)connection whatever was sent before.
    public func resized(cols: Int, rows: Int, force: Bool = false) {
        guard cols > 0, rows > 0, !removedFromServer else { return }
        if !force, let lastSize, lastSize == (cols, rows) { pendingSize = nil; sizeTimer?.cancel(); sizeTimer = nil; return }
        if lastSize == nil || force { sizeTimer?.cancel(); sizeTimer = nil; pendingSize = nil; lastSize = (cols, rows); pushSize(cols, rows); return }
        pendingSize = (cols, rows)
        guard sizeTimer == nil, let clock = store?.clock else { return }
        sizeTimer = Task { [weak self] in
            try? await clock.sleep(.milliseconds(100))
            guard let self, !Task.isCancelled else { return }
            self.sizeTimer = nil
            guard let next = self.pendingSize else { return }
            self.pendingSize = nil
            if let last = self.lastSize, last == next { return }
            self.lastSize = next; self.pushSize(next.cols, next.rows)
        }
    }
    private func pushSize(_ cols: Int, _ rows: Int) {
        sizeToSend = (cols, rows)
        guard sizeSender == nil else { return }
        let directory = directory, pty = id
        sizeSender = Task { [weak self] in
            while !Task.isCancelled, let self, let next = self.sizeToSend {
                self.sizeToSend = nil
                // Errors are ignored, as the reference does: the next size or reconnection sends it again.
                _ = try? await self.store?.client?().send(TerminalEndpoints.update(pty, directory: directory, cols: next.cols, rows: next.rows))
            }
            if !Task.isCancelled { self?.sizeSender = nil }
        }
    }

    // MARK: The socket

    private func run(_ effects: [TerminalLink.Effect]) {
        for effect in effects {
            switch effect {
            case .connect(let seek): connect(seek)
            case .close: stopSocket()
            case .checkStatus: checkStatus()
            case .wait(let delay): wait(delay)
            case .feed(let text), .replay(let text):
                if case .replay = effect { engine?.replay(text) } else { engine?.feed(text) }
                unsaved = true
                // A kill without backgrounding loses at most ten seconds of saved state.
                if let clock = store?.clock, lastPersist.map({ $0.duration(to: clock.now()) > .seconds(10) }) ?? true { persist() }
            case .reset: engine?.reset(); unsaved = true
            case .gap(let gap): self.gap = gap; unsaved = true
            case .pushSize: if let size = engine?.size { resized(cols: size.cols, rows: size.rows, force: true) }
            case .persist: persist()
            case .forget: forget()
            }
        }
    }
    private func connect(_ seek: Int, ticket: String? = nil) {
        stopSocket()
        generation += 1
        let generation = generation, id = id, directory = directory
        reader = Task { [weak self] in
            guard let self, let store = self.store, let client = store.client else { return }
            let connection: any WebSocketConnection
            do {
                let api = try await client()
                var query = [URLQueryItem(name: "cursor", value: String(seek))]
                if let ticket { query.append(.init(name: "ticket", value: ticket)) }
                let request = try api.webSocketRequest(path: "/api/pty/" + id + "/connect", query: query, scope: .location(directory: directory),
                                                       authenticated: ticket == nil)
                connection = store.webSockets.open(request)
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                self.run(self.link.closed(code: nil))
                return
            }
            guard !Task.isCancelled, generation == self.generation else { connection.close(); return }
            self.connection = connection
            let (inputs, continuation) = AsyncStream.makeStream(of: String.self)
            self.input = continuation
            self.writer = Task { for await text in inputs { try? await connection.send(text) } }
            var opened = false
            for await event in connection.events {
                guard !Task.isCancelled, generation == self.generation else { return }
                switch event {
                case .opened: opened = true; self.run(self.link.opened())
                case .frame(.output(let text)): self.run(self.link.text(text))
                case .frame(.control(let cursor)): self.run(self.link.control(cursor: cursor))
                case .frame(.ignored): break
                case .closed(let code, _, let status):
                    self.input?.finish(); self.input = nil; self.connection = nil
                    // An upgrade refused before it opened, while REST accepts the same credentials, lost its
                    // Authorization header on the way (a proxy): retry once with a single-use ticket. The server answers
                    // 401 or 403, or (v2.2.0) drops the connection without a status.
                    if !opened, ticket == nil, status == nil || status == 401 || status == 403, let ticket = await self.ticket() {
                        guard generation == self.generation else { return }
                        self.ticketReason = status.map { "The connection upgrade answered \($0) with the server's credentials." }
                            ?? "The connection upgrade closed without an answer while the server accepted its credentials."
                        self.connect(seek, ticket: ticket)
                        return
                    }
                    // An upgrade answered 404: the PTY is gone, so the list loses its row as for pty.deleted.
                    if status == 404 { self.list?.handle(type: "pty.deleted", payload: .object(["id": .string(id)])); return }
                    self.run(self.link.closed(code: code, httpStatus: status))
                    return
                }
            }
        }
    }
    private func ticket() async -> String? {
        try? await store?.client?().send(TerminalEndpoints.connectToken(id, directory: directory)).data.ticket
    }
    private func stopSocket() {
        generation += 1
        reader?.cancel(); reader = nil; writer?.cancel(); writer = nil
        input?.finish(); input = nil
        connection?.close(); connection = nil
    }
    private func checkStatus() {
        let id = id, directory = directory
        statusTask = Task { [weak self] in
            let status: TerminalStatus
            do {
                guard let api = try await self?.store?.client?() else { return }
                let info = try await api.send(TerminalEndpoints.get(id, directory: directory)).data
                status = info.status == .exited ? .exited(code: info.exitCode) : .running
            } catch APIError.server(_, 404, _) { status = .gone }
            catch is CancellationError { return }
            catch { status = .unknown }
            guard let self, !Task.isCancelled else { return }
            if case .gone = status { self.list?.handle(type: "pty.deleted", payload: .object(["id": .string(id)])) }
            self.run(self.link.status(status))
        }
    }
    private func wait(_ delay: Duration) {
        guard let clock = store?.clock else { return }
        timer = Task { [weak self] in
            try? await clock.sleep(delay)
            guard let self, !Task.isCancelled else { return }
            self.run(self.link.waited())
        }
    }

    // MARK: Saving

    /// Saves the cursor with the screen it matches; the screen is read after every counted byte has been fed.
    private func persist() {
        guard let store, let writer = store.cache?.writer, let engine, let cursor = link.cursor, unsaved || lastPersist == nil else { return }
        let size = engine.size
        var screen = engine.snapshot(scrollback: 2_000) ?? ""
        for rows in [500, 0] where screen.utf8.count > TerminalResume.screenLimit { screen = engine.snapshot(scrollback: rows) ?? "" }
        let value = TerminalResume(serverID: store.serverID, ptyID: id, directory: directory, cursor: cursor, cols: size.cols, rows: size.rows,
                                   screen: screen, updated: store.clock.date())
        lastPersist = store.clock.now(); unsaved = false
        let previous = persistTask
        persistTask = Task { await previous?.value; try? await writer.saveTerminal(value) }
    }
    private func forget() {
        guard let store, let writer = store.cache?.writer else { return }
        let previous = persistTask, server = store.serverID, id = id
        persistTask = Task { await previous?.value; try? await writer.forgetTerminal(serverID: server, ptyID: id) }
    }
}

extension ReadStore {
    /// The terminals of one location, kept for the life of the server's store.
    public func terminals(directory: String) -> TerminalListModel {
        if let list = terminalLists[directory] { return list }
        let list = TerminalListModel(store: self, directory: directory); terminalLists[directory] = list
        return list
    }
    public func shellRuns(directory: String) -> ShellRunModel {
        if let model = shellRuns[directory] { return model }
        let model = ShellRunModel(store: self, directory: directory); shellRuns[directory] = model
        return model
    }
}

// "Run a command" outside any session: POST /api/shell, its output paged by byte cursor (packages/core/src/shell.ts at
// v2.2.0), Stop (DELETE, which also deletes the captured output) and the location's running commands.
import Foundation
import Observation
import OCFoundation
import OCModels
import OCNetworking

@MainActor @Observable public final class ShellRunModel {
    public let directory: String
    /// The command on screen.
    public private(set) var shell: ShellInfo?
    /// The location's running commands, the agent's own among them.
    public private(set) var running: [ShellInfo] = []
    public private(set) var error: String?
    public private(set) var stopping = false
    @ObservationIgnored private weak var store: ReadStore?
    @ObservationIgnored private weak var engine: (any TerminalEngine)?
    @ObservationIgnored private var output: [String] = []
    @ObservationIgnored private var outputBytes = 0
    @ObservationIgnored private var pager = ShellPager(running: false)
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    /// The current command's output is fully read: it ended, its last page came, or the server dropped it.
    @ObservationIgnored private var finished = false
    @ObservationIgnored private var pageGeneration = UUID()
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    /// What a new output view replays, so the sheet can close and reopen while a command runs.
    static let retainedBytes = 1 << 20

    init(store: ReadStore, directory: String) { self.store = store; self.directory = directory }

    public var isRunning: Bool { shell?.status == "running" && !pager.missing }

    public func appear() {
        resumePaging()
        owned { model in
            guard let api = try await model.store?.client?() else { return }
            model.running = try await api.send(TerminalEndpoints.runningShells(model.directory)).data.values.sorted { $0.id < $1.id }
        }
    }
    /// The output view: it receives what was paged so far, then every new page.
    public func attach(_ engine: any TerminalEngine) {
        self.engine = engine
        engine.reset()
        for chunk in output { engine.feed(chunk) }
    }
    public func run(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        error = nil
        owned { model in
            guard let api = try await model.store?.client?() else { return }
            model.show(try await api.send(TerminalEndpoints.runShell(model.directory, command: command)).data)
        }
    }
    /// Shows `shell`'s output from its start.
    public func show(_ shell: ShellInfo) {
        pageTask?.cancel()
        self.shell = shell; stopping = false
        output = []; outputBytes = 0; engine?.reset()
        pager = ShellPager(running: shell.status == "running"); finished = false
        if shell.status == "running", !running.contains(where: { $0.id == shell.id }) { running.append(shell) }
        page()
    }
    /// Kills the command; the server deletes its output with it, so what was paged stays on screen.
    public func stop() {
        guard let shell, isRunning else { return }
        stopping = true
        owned { model in
            defer { model.stopping = false }
            guard let api = try await model.store?.client?() else { return }
            try await api.send(TerminalEndpoints.removeShell(shell.id, directory: model.directory))
            model.ended(shell.id, status: "killed", exit: nil)
        }
    }
    /// A `shell.*` event of this location; the store routes them here.
    public func handle(type: String, payload: JSONValue) {
        switch type {
        case "shell.created":
            let info = ShellInfo(raw: payload["info"] ?? .object([:]))
            if info.status == "running", !info.id.isEmpty, !running.contains(where: { $0.id == info.id }) { running.append(info) }
        case "shell.exited":
            ended(payload["id"]?.stringValue ?? "", status: payload["status"]?.stringValue ?? "exited", exit: payload["exit"])
        case "shell.deleted":
            let id = payload["id"]?.stringValue ?? ""
            running.removeAll { $0.id == id }
            if shell?.id == id { _ = pager.notFound() }
        default: break
        }
    }
    /// Paging stops while the app is in the background; it continues from its cursor when the sheet shows again or the
    /// server is back, and a command that ended meanwhile still gets its last page.
    func resumePaging() {
        guard shell != nil, !finished, pageTask == nil else { return }
        page()
    }
    func cancel() {
        pageTask?.cancel(); pageTask = nil; pageGeneration = UUID()
        for task in tasks.values { task.cancel() }
        tasks = [:]
    }

    private func ended(_ id: String, status: String, exit: JSONValue?) {
        running.removeAll { $0.id == id }
        guard var shell, shell.id == id, shell.status == "running" else { return }
        shell.raw.set("status", .string(status)); shell.raw.set("exit", exit)
        self.shell = shell
        _ = pager.exited()
        resumePaging()
    }
    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        let chunk = ShellPager.terminalText(text)
        engine?.feed(chunk)
        output.append(chunk); outputBytes += chunk.utf8.count
        while outputBytes > Self.retainedBytes, output.count > 1 { outputBytes -= output.removeFirst().utf8.count }
    }
    private func page() {
        guard let id = shell?.id else { return }
        let directory = directory
        let generation = UUID()
        pageGeneration = generation
        pageTask = Task { [weak self] in
            defer { if let self, self.pageGeneration == generation { self.pageTask = nil } }
            guard var next = self?.pager.start() else { return }
            while !Task.isCancelled, let self {
                switch next {
                case .done: self.finished = true; return
                case .poll(let delay):
                    try? await self.store?.clock.sleep(delay)
                    guard !Task.isCancelled else { return }
                    // A status read catches an exit whose event this connection missed.
                    if self.pager.running, let info = try? await self.store?.client?().send(TerminalEndpoints.shell(id, directory: directory)).data,
                       info.status != "running" {
                        self.ended(id, status: info.status, exit: info["exit"])
                    }
                    next = .fetch(cursor: self.pager.cursor)
                case .fetch(let cursor):
                    do {
                        guard let api = try await self.store?.client?() else { return }
                        let page = try await api.send(ReadEndpoints.shellOutput(id, directory: directory, cursor: cursor, limit: ShellPager.pageSize)).data
                        guard !Task.isCancelled, self.shell?.id == id else { return }
                        self.append(page.output)
                        next = self.pager.received(cursor: Self.offset(page.cursor), size: Self.offset(page.size))
                    } catch APIError.server(_, 404, _) {
                        next = self.pager.notFound()
                    } catch APIError.cancelled { return } catch {
                        self.error = "Could not load the output."
                        try? await self.store?.clock.sleep(.seconds(1))
                        next = .fetch(cursor: self.pager.cursor)
                    }
                }
            }
        }
    }
    private static func offset(_ value: Double) -> Int { value.isFinite && value >= 0 && value < 9e15 ? Int(value) : 0 }
    private func owned(_ work: @escaping @MainActor (ShellRunModel) async throws -> Void) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do { try await work(self) } catch is CancellationError {} catch APIError.cancelled {} catch { self.error = "Could not reach the server." }
            self.tasks.removeValue(forKey: id)
        }
    }
}

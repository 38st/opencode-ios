import Foundation
import OCFoundation
import OCModels

public actor ServerConnection: ConnectionControlling {
    public nonisolated let output: AsyncStream<ConnectionOutput>
    public private(set) var state: ConnectionState = .idle
    public private(set) var transitions: [StateTransition] = []
    public private(set) var endpoints: [EndpointRecord]
    public private(set) var lastResolution: EndpointResolution?
    public private(set) var lastActivity: ContinuousClock.Instant?

    private var credential: Credential?
    private var headers: [String: String]
    private var lastResolvedAt: ContinuousClock.Instant?
    private var allowsLocalNetwork: Bool
    private let resolver: any EndpointResolving
    private let transport: any HTTPTransport
    private let clock: NetworkClock
    private let serverClock: ServerClock
    private let pathMonitor: (any NetworkPathMonitoring)?
    private let mailbox: ConnectionMailbox
    private let backlogLimit: Int
    private var backoff: ReconnectBackoff
    private var runTask: Task<Void, Never>?
    private var pathTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    public private(set) var networkPath: NetworkPathStatus?
    private var generation = 0
    private var started = false
    private var connectedAt: ContinuousClock.Instant?
    private var openedAt: ContinuousClock.Instant?
    private var pending: [ServerEvent] = []

    public init(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String] = [:],
                transport: any HTTPTransport = URLSessionTransport(), resolver: (any EndpointResolving)? = nil,
                clock: NetworkClock = .init(), serverClock: ServerClock = .init(),
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
                pathMonitor: (any NetworkPathMonitoring)? = NetworkPathMonitor(), backlogLimit: Int = 20_000,
                prefersHTTPS: Bool = false, allowsLocalNetwork: Bool = true) {
        self.endpoints = endpoints; self.credential = credential; self.headers = headers
        self.transport = transport; self.clock = clock; self.serverClock = serverClock
        self.allowsLocalNetwork = allowsLocalNetwork
        self.resolver = resolver ?? EndpointResolver(transport: transport, clock: clock, serverClock: serverClock, prefersHTTPS: prefersHTTPS)
        self.pathMonitor = pathMonitor; self.backoff = ReconnectBackoff(random: random)
        self.backlogLimit = max(1, backlogLimit)
        let mailbox = ConnectionMailbox(limit: max(1, backlogLimit))
        self.mailbox = mailbox
        output = AsyncStream(unfolding: { await mailbox.next() }, onCancel: { mailbox.finish() })
    }
    deinit {
        runTask?.cancel(); pathTask?.cancel(); debounceTask?.cancel(); flushTask?.cancel(); mailbox.finish()
    }
    public func start(rerace: Bool = true) {
        guard !started else { return }
        started = true; backoff.reset()
        restart(rerace: rerace)
        if let pathMonitor {
            pathTask = Task { [weak self] in
                for await status in pathMonitor.updates() {
                    guard !Task.isCancelled else { return }
                    await self?.pathChanged(status)
                }
            }
        }
    }
    public func stop() async {
        started = false; generation += 1
        runTask?.cancel(); pathTask?.cancel(); debounceTask?.cancel(); flushTask?.cancel()
        pathTask = nil; debounceTask = nil; flushTask = nil; networkPath = nil
        pending = []; mailbox.discardEvents()
        transition(.suspended)
        await runTask?.value
    }
    public func forceReconnect(_ reason: ReconnectReason, rerace: Bool = true) {
        guard started, state != .unauthorized else { return }
        restart(rerace: rerace)
    }
    public func snapshot() -> ConnectionSnapshot {
        .init(resolution: lastResolution, lastActivity: lastActivity, lastResolvedAt: lastResolvedAt)
    }
    public func setNetworkPath(_ path: NetworkPathStatus) { networkPath = path }
    public func updateEndpoints(_ endpoints: [EndpointRecord]) { self.endpoints = endpoints }
    public func allowLocalNetwork() { allowsLocalNetwork = true }
    public func configure(endpoints: [EndpointRecord], credential: Credential?, headers: [String: String]) {
        self.endpoints = endpoints; self.credential = credential; self.headers = headers
        lastResolution = nil; lastResolvedAt = nil
        if state == .unauthorized { transition(.idle) }
    }
    private func restart(rerace: Bool = true) {
        generation += 1
        let active = generation
        let previous = runTask
        previous?.cancel(); flushTask?.cancel(); flushTask = nil; pending = []
        runTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.run(active, rerace: rerace)
        }
    }
    private func pathChanged(_ status: NetworkPathStatus) {
        let initial = networkPath == nil
        networkPath = status
        guard !initial else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self, clock] in
            do { try await clock.sleep(.milliseconds(500)); try Task.checkCancellation() }
            catch { return }
            await self?.forceReconnect(.networkPathChanged)
        }
    }
    private func transition(_ next: ConnectionState) {
        state = next
        transitions.append(StateTransition(state: next, at: clock.now()))
        if transitions.count > 50 { transitions.removeFirst(transitions.count - 50) }
        mailbox.yield(.state(next))
    }
    private func isActive(_ active: Int) -> Bool { started && generation == active && !Task.isCancelled }

    private func run(_ active: Int, rerace: Bool) async {
        var attempt = 0
        var cached = rerace ? nil : lastResolution
        while isActive(active) {
            connectedAt = nil
            transition(.resolving)
            let resolution: EndpointResolution
            if let cached, cached.selected != nil { resolution = cached }
            else {
                resolution = await resolver.resolve(endpoints: endpoints.filter { allowsLocalNetwork || $0.kind != .lan }, credential: credential, headers: headers,
                                                     localNetworkDenied: networkPath?.localNetworkDenied ?? false)
                lastResolvedAt = clock.now()
            }
            cached = nil // Every failed connection must race again.
            guard isActive(active) else { return }
            lastResolution = resolution
            for endpoint in resolution.discovered where !endpoints.contains(where: { $0.url == endpoint.url }) { endpoints.append(endpoint) }
            do {
                guard let endpoint = resolution.selected else {
                    if resolution.diagnoses.values.contains(.failure(.unauthorized)) { throw APIError.unauthorized }
                    if !resolution.diagnoses.isEmpty && resolution.diagnoses.values.allSatisfy({ $0 == .failure(.notOpencode) }) {
                        transition(.incompatible(.notOpencode)); return
                    }
                    if let delay = resolution.diagnoses.values.compactMap({ if case .starting(let delay) = $0 { delay } else { nil } }).first {
                        throw APIError.serviceStarting(retryAfter: delay)
                    }
                    if let outcome = resolution.diagnoses.values.compactMap({ if case .incompatible(let outcome) = $0 { outcome } else { nil } }).first {
                        transition(.incompatible(outcome)); return
                    }
                    let failure: ConnectionFailure = resolution.diagnoses.values.compactMap { value -> ConnectionFailure? in
                        if case .failure(let failure) = value { failure } else { nil }
                    }.first ?? .transport
                    throw failure
                }
                transition(.connecting(attempt: attempt))
                try await connect(endpoint, active: active)
                throw ConnectionFailure.streamClosed
            } catch {
                guard isActive(active) else { return }
                flushTask?.cancel(); flushTask = nil
                flush()
                if let connectedAt, connectedAt.duration(to: clock.now()) >= .seconds(10) { backoff.reset(); attempt = 0 }
                if case APIError.unauthorized = error { transition(.unauthorized); return }
                if case APIError.notOpencode = error { transition(.incompatible(.notOpencode)); return }
                if case APIError.serviceStarting(let delay) = error {
                    transition(.serviceStarting(delay))
                    do { try await clock.sleep(delay) } catch { return }
                    continue
                }
                let failure = diagnose(error)
                let delay = backoff.next()
                attempt += 1
                transition(.waiting(attempt: attempt, retryAt: clock.now().advanced(by: delay), failure: failure))
                do { try await clock.sleep(delay) } catch { return }
            }
        }
    }

    private func connect(_ endpoint: EndpointRecord, active: Int) async throws {
        openedAt = clock.now(); lastActivity = openedAt
        var request = try APIClient.request(baseURL: endpoint.url, path: "/api/event", credential: credential,
                                            headers: headers, timeout: 120)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let stream = transport.stream(request)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                try await self.read(stream, endpoint: endpoint, active: active)
            }
            group.addTask { [weak self] in
                guard let self else { return }
                try await self.watchdog(lan: endpoint.kind == .lan, active: active)
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
    private func watchdog(lan: Bool, active: Int) async throws {
        while isActive(active) {
            guard let openedAt, let lastActivity else { return }
            let first = connectedAt == nil
            let deadline = first ? openedAt.advanced(by: .seconds(lan ? 3 : 8)) : lastActivity.advanced(by: .seconds(45))
            let remaining = clock.now().duration(to: deadline)
            if remaining <= .zero { throw first ? ConnectionFailure.firstFrameTimeout : .watchdog }
            try await clock.sleep(remaining)
        }
        throw CancellationError()
    }
    private func read(_ stream: AsyncThrowingStream<TransportChunk, any Error>, endpoint: EndpointRecord, active: Int) async throws {
        var parser = SSEParser()
        var accepted = false
        for try await chunk in stream {
            try Task.checkCancellation()
            guard isActive(active) else { throw CancellationError() }
            switch chunk {
            case .response(let response):
                try APIClient.validate(response, now: clock.date(), contentType: "text/event-stream")
                accepted = true
            case .bytes(let bytes):
                guard accepted else { throw ConnectionFailure.invalidFirstFrame }
                if !bytes.isEmpty { lastActivity = clock.now() }
                let parsed = parser.append(bytes)
                if parsed.skippedEvents > 0 { mailbox.yield(.resyncNeeded(.oversizedEvent)) }
                let events = await ServerEvent.decodeBatch(parsed.frames.map(\.data))
                try Task.checkCancellation()
                guard isActive(active) else { throw CancellationError() }
                for event in events {
                    if connectedAt == nil {
                        guard case .connected = event else { throw ConnectionFailure.invalidFirstFrame }
                        connectedAt = clock.now()
                        transition(.connected(endpoint.id, since: clock.now()))
                    }
                    if case .connected(let header) = event { mailbox.yield(.resyncNeeded(.serverConnected(header))) }
                    if let created = event.header?.created, created.isFinite {
                        serverClock.refine(eventTimestamp: Date(timeIntervalSince1970: created / 1000), receivedAt: clock.date())
                    }
                    pending.append(event)
                    if pending.count > backlogLimit {
                        pending = []; mailbox.discardEvents(); mailbox.yield(.resyncNeeded(.backlogOverflow))
                    } else if event.needsImmediateDelivery { flush() }
                }
                scheduleFlush(active)
            }
        }
        throw ConnectionFailure.streamClosed
    }
    private func scheduleFlush(_ active: Int) {
        guard !pending.isEmpty, flushTask == nil else { return }
        flushTask = Task { [weak self, clock] in
            do { try await clock.sleep(.milliseconds(16)); try Task.checkCancellation() } catch { return }
            await self?.flushIfActive(active)
        }
    }
    private func flushIfActive(_ active: Int) {
        guard isActive(active) else { return }
        flushTask = nil; flush()
    }
    private func flush() {
        guard !pending.isEmpty else { return }
        mailbox.yield(.events(EventBatch(events: pending)))
        pending = []
    }
}

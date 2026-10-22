import Foundation
import Observation
import OCFoundation
import OCModels

@MainActor @Observable public final class Revalidating<Value: Sendable> {
    public private(set) var value: Value?
    public private(set) var isLoading = false
    public private(set) var isStale = true
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var taskID: UUID?
    @ObservationIgnored private var task: Task<Value, any Error>?
    public init(_ value: Value? = nil) { self.value = value }
    deinit { task?.cancel() }
    public func invalidate() { revision += 1; isStale = true }
    public func seed(_ value: Value) { self.value = value }
    public func stop() { task?.cancel(); task = nil; taskID = nil; isLoading = false; invalidate() }
    public func load(_ fetch: @escaping @MainActor () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        if let task {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        }
        if !isStale, let value { return value }
        let id = UUID(); taskID = id
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            self.isLoading = true
            defer { if self.taskID == id { self.isLoading = false; self.task = nil; self.taskID = nil } }
            while true {
                let revision = self.revision
                let value = try await fetch()
                try Task.checkCancellation()
                guard revision == self.revision else { continue }
                self.value = value; self.isStale = false; return value
            }
        }
        self.task = task
        // A disappearing consumer must not cancel another consumer's shared fetch.
        let value = try await task.value
        try Task.checkCancellation()
        return value
    }
}
@MainActor @Observable public final class LocationCatalog {
    public let agents = Revalidating<[AgentInfo]>()
    public let models = Revalidating<[ModelInfo]>()
    public let providers = Revalidating<[ProviderInfo]>()
    public let defaultModel = Revalidating<ModelInfo?>()
    public let commands = Revalidating<JSONValue>()
    public let skills = Revalidating<JSONValue>()
    public let references = Revalidating<JSONValue>()
    public let mcp = Revalidating<[MCPServer]>()
    public let vcs = Revalidating<JSONValue>()
    public var extras: [String: Revalidating<JSONValue>] = [:]
    public init() {}
    public func invalidate() {
        agents.invalidate(); models.invalidate(); providers.invalidate(); defaultModel.invalidate()
        commands.invalidate(); skills.invalidate(); references.invalidate(); mcp.invalidate(); vcs.invalidate()
        for cell in extras.values { cell.invalidate() }
    }
    public func stop() {
        agents.stop(); models.stop(); providers.stop(); defaultModel.stop()
        commands.stop(); skills.stop(); references.stop(); mcp.stop(); vcs.stop()
        for cell in extras.values { cell.stop() }
    }
}

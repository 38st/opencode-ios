import Foundation
import OCFoundation
import OCModels
import OCPersistence
import OCNetworking

extension ReadStore {
    public func catalog(for location: Location) -> LocationCatalog {
        if let catalog = catalogs[location.key] { return catalog }
        let catalog = LocationCatalog(); catalogs[location.key] = catalog; return catalog
    }
    public func refreshCatalogs(_ directory: String) async throws {
        guard let client else { return }
        let api = try await client(), requested = Location(directory: directory), catalog = catalog(for: requested)
        let bind: @MainActor (Location) -> Void = { [weak self] canonical in self?.catalogs[canonical.key] = catalog }
        async let agents: [AgentInfo] = catalog.agents.load {
            let value = try await api.send(ReadEndpoints.agents(directory)); bind(value.location); return value.data
        }
        async let models: [ModelInfo] = catalog.models.load {
            let value = try await api.send(ReadEndpoints.models(directory)); bind(value.location); return value.data
        }
        async let providers: [ProviderInfo] = catalog.providers.load {
            let value = try await api.send(ReadEndpoints.providers(directory)); bind(value.location); return value.data
        }
        async let defaultModel: ModelInfo? = catalog.defaultModel.load { try await api.send(ReadEndpoints.defaultModel(directory)).data }
        _ = try await (agents, models, providers, defaultModel)
        _ = try await catalog.mcp.load { try await api.send(ReadEndpoints.mcp(directory)).data }
        for (kind, cell) in [("command", catalog.commands), ("skill", catalog.skills), ("reference", catalog.references), ("vcs", catalog.vcs)] {
            _ = try await cell.load { try await api.send(ReadEndpoints.catalog(kind, directory: directory)).data }
        }
        if let cache {
            let values: [(String, JSONValue)] = [
                ("agent", .array((catalog.agents.value ?? []).map(\.raw))), ("model", .array((catalog.models.value ?? []).map(\.raw))),
                ("provider", .array((catalog.providers.value ?? []).map(\.raw))), ("model/default", catalog.defaultModel.value.flatMap { $0 }?.raw ?? .null)
            ]
            for (kind, raw) in values { try await cache.writer.saveCatalog(serverID: serverID, locationKey: requested.key, kind: kind, raw: raw) }
        }
    }
    func handleCatalog(_ event: ServerEvent) {
        guard let type = event.header?.type else { return }
        let all = ["credential.updated", "credential.switched", "models-dev.refreshed"].contains(type)
        let locations = all ? Array(catalogs.keys) : [Location(raw: event.header?.location ?? .object([:])).key]
        for key in locations {
            guard let catalog = catalogs[key] else { continue }
            switch type {
            case "agent.updated": catalog.agents.invalidate()
            case "model.updated", "models-dev.refreshed": catalog.models.invalidate(); catalog.defaultModel.invalidate()
            case "provider.updated": catalog.providers.invalidate()
            case "command.updated": catalog.commands.invalidate()
            case "skill.updated": catalog.skills.invalidate()
            case "reference.updated": catalog.references.invalidate()
            case "mcp.status.changed", "mcp.resources.changed": catalog.mcp.invalidate()
            case "vcs.branch.updated":
                var value = catalog.vcs.value ?? .object([:]); value.set(["branch", "current"], event.payload["branch"]); catalog.vcs.seed(value)
            case "location.shutdown", "integration.updated", "credential.updated", "credential.switched", "config.updated", "plugin.updated", "websearch.updated": catalog.invalidate()
            default: return
            }
        }
        if let directory = event.header?.location?["directory"]?.stringValue,
           openSessions.contains(where: { sessions[$0]?.info.location.directory == directory }) {
            owned { [weak self] in try await self?.refreshCatalogs(directory) }
        } else if all {
            for directory in Set(openSessions.compactMap { sessions[$0]?.info.location.directory }) {
                owned { [weak self] in try await self?.refreshCatalogs(directory) }
            }
        }
    }
}

import Foundation
import OCFoundation

public struct ModelGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let models: [ModelInfo]
}
public enum ComposerPickers {
    public static func displayName(_ model: ModelInfo) -> String { model.name.replacingOccurrences(of: "(latest)", with: "").trimmingCharacters(in: .whitespaces) }
    /// The catalog entry for a selection; an empty provider matches any provider, as in older messages.
    public static func model(_ ref: ModelRef, in models: [ModelInfo]) -> ModelInfo? {
        models.first { $0.id == ref.id && (ref.providerID.isEmpty || $0.providerID == ref.providerID) }
    }
    /// The name the composer shows for a selection, falling back to the raw id before the catalog loads.
    public static func displayName(_ ref: ModelRef, in models: [ModelInfo]) -> String {
        model(ref, in: models).map(displayName).flatMap { $0.isEmpty ? nil : $0 } ?? ref.id
    }
    public static let providerOrder = ["opencode-go", "opencode", "anthropic", "github-copilot", "openai", "google", "openrouter", "vercel"]
    public static func key(_ model: ModelRef) -> String { model.providerID + ":" + model.id }
    public static func key(_ model: ModelInfo) -> String { model.providerID + ":" + model.id }
    public static func agentID(_ agent: AgentInfo) -> String { agent.id.isEmpty ? agent.name : agent.id }
    public static func sameSelection(_ left: ModelRef?, _ right: ModelRef?) -> Bool {
        guard let left, let right else { return left == nil && right == nil }
        return left.id == right.id && left.providerID == right.providerID &&
            (left.variant ?? "default") == (right.variant ?? "default")
    }
    public static func agents(_ values: [AgentInfo]) -> [AgentInfo] { values.filter { !$0.hidden && $0.mode != "subagent" } }
    public static func showAgent(_ values: [AgentInfo], setting: Bool) -> Bool { setting || agents(values).contains { $0["native"]?.boolValue == false || !["build", "plan"].contains($0.id) } }
    public static func groups(_ values: [ModelInfo], providers: [ProviderInfo], query: String, showAll: Bool,
                              recent: [String] = [], now: Date = Date()) -> [ModelGroup] {
        let enabled = values.filter(\.enabled)
        let releases = Dictionary(enabled.compactMap { model -> (String, Date)? in
            if let milliseconds = model["time"]?["released"]?.wireNumber, milliseconds.isFinite {
                return (key(model), Date(timeIntervalSince1970: milliseconds / 1_000))
            }
            guard let value = model["time"]?["released"]?.stringValue else { return nil }
            let date = ISO8601DateFormatter().date(from: value + (value.count == 10 ? "T00:00:00Z" : ""))
            return date.map { (key(model), $0) }
        }, uniquingKeysWith: { left, right in max(left, right) })
        let latest = Dictionary(grouping: enabled.filter { model in
            releases[key(model)].map { abs(now.timeIntervalSince($0)) < 6 * 30.436875 * 24 * 60 * 60 } ?? false
        }, by: { $0.providerID + ":" + ($0.family ?? "") }).values.compactMap { family in
            family.max { (releases[key($0)] ?? .distantPast) < (releases[key($1)] ?? .distantPast) }.map(key)
        }
        let visible = enabled.filter { model in
            let provider = providers.first { $0.id == model.providerID }?.name ?? model.providerID
            return (showAll || releases[key(model)] == nil || latest.contains(key(model)) || recent.contains(key(model))) &&
                (query.isEmpty || [model.name, model.id, model.providerID, provider].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var groups = Dictionary(grouping: visible, by: \.providerID).map { id, models in
            ModelGroup(id: id, name: providers.first { $0.id == id }?.name ?? id, models: models)
        }.sorted { left, right in
            let l = providerOrder.firstIndex(of: left.id) ?? Int.max, r = providerOrder.firstIndex(of: right.id) ?? Int.max
            return l == r ? left.name.localizedStandardCompare(right.name) == .orderedAscending : l < r
        }
        let recents = recent.prefix(5).compactMap { id in visible.first { key($0) == id } }
        if !recents.isEmpty { groups.insert(.init(id: "recent", name: "Recent", models: recents), at: 0) }
        return groups
    }
    public static func badges(_ model: ModelInfo, defaultModel: ModelInfo?) -> [String] {
        var result: [String] = []
        if model.providerID == "opencode", (model.cost.first?.input ?? 0) == 0 { result.append("Free") }
        if model.name.contains("(latest)") { result.append("Latest") }
        if let defaultModel, key(model) == key(defaultModel) { result.append("Default") }
        if model.capabilities.input.contains("image") { result.append("Image") }
        if model.capabilities.input.contains("pdf") { result.append("PDF") }
        if model.variants.contains(where: { $0.id != "default" }) { result.append("Variants") }
        return result
    }
}

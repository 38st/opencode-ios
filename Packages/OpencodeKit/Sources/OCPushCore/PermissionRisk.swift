import Foundation
import OCModels

/// Risk tiers for permission requests, from the shared `risk-rules.json` (a byte-identical copy of
/// `server/contracts/risk-rules.json`), so the app and the plugin always agree.
public enum PermissionRisk: String, Sendable, CaseIterable {
    case low, elevated, high

    public static func assess(_ request: PermissionRequest) -> Self {
        classify(action: request.action, resources: request.resources).tier
    }

    /// The tier and the id of the deciding rule. If the rules cannot be read, everything is high.
    public static func classify(action: String, resources: [String]) -> (tier: Self, rule: String) {
        RiskRules.shared?.classify(action: action, resources: resources) ?? (.high, "rules-unavailable")
    }
}

/// The compiled rules. Patterns use the portable dialect of `server/contracts/README.md`, so
/// ICU (`.regularExpression`, no options) evaluates them exactly as ECMAScript does.
struct RiskRules: Sendable {
    private struct File: Decodable {
        struct Pattern: Decodable { let id: String; let tier: String; let pattern: String }
        struct Action: Decodable { let id: String; let actions: [String]; let tier: String; let escalate: [Pattern]? }
        struct Fallback: Decodable { let id: String; let tier: String }
        struct Limits: Decodable { let maxLength: Int; let rule: Fallback }
        let limits: Limits
        let macros: [String: String]
        let actions: [Action]
        let `default`: Fallback
    }
    struct Escalation: Sendable { let id: String; let tier: PermissionRisk; let pattern: String }
    struct Rule: Sendable { let id: String; let actions: Set<String>; let tier: PermissionRisk; let escalate: [Escalation] }
    enum Failure: Error { case tier(String), macro(String), pattern(String) }

    let rules: [Rule]
    let fallback: (tier: PermissionRisk, rule: String)
    /// Joined resources longer than this (UTF-16 code units, like JavaScript's `length`) get `tooLong` without running a pattern.
    let maxLength: Int
    let tooLong: (tier: PermissionRisk, rule: String)

    static let shared: RiskRules? = try? RiskRules(data: ContractResource.data("risk-rules.json"))

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        func tier(_ name: String) throws -> PermissionRisk {
            guard let tier = PermissionRisk(rawValue: name) else { throw Failure.tier(name) }
            return tier
        }
        rules = try file.actions.map { action in
            Rule(id: action.id, actions: Set(action.actions), tier: try tier(action.tier), escalate: try (action.escalate ?? []).map { item in
                let pattern = try Self.expand(item.pattern, macros: file.macros)
                // `.regularExpression` silently matches nothing for an invalid pattern, so reject it here.
                guard (try? NSRegularExpression(pattern: pattern)) != nil else { throw Failure.pattern(item.id) }
                return Escalation(id: item.id, tier: try tier(item.tier), pattern: pattern)
            })
        }
        fallback = (try tier(file.default.tier), file.default.id)
        maxLength = file.limits.maxLength
        tooLong = (try tier(file.limits.rule.tier), file.limits.rule.id)
    }

    /// Replaces `{name}` with its macro; braces around digits are quantifiers and stay.
    static func expand(_ pattern: String, macros: [String: String]) throws -> String {
        var output = "", rest = Substring(pattern)
        while let open = rest.firstIndex(of: "{") {
            output += rest[..<open]
            let tail = rest[rest.index(after: open)...]
            if let close = tail.firstIndex(of: "}"), case let name = tail[..<close], !name.isEmpty, name.allSatisfy({ ("a"..."z").contains($0) }) {
                guard let value = macros[String(name)] else { throw Failure.macro(String(name)) }
                output += value
                rest = tail[tail.index(after: close)...]
            } else {
                output += "{"
                rest = tail
            }
        }
        return output + rest
    }

    func classify(action: String, resources: [String]) -> (tier: PermissionRisk, rule: String) {
        guard let rule = rules.first(where: { $0.actions.contains(action) }) else { return fallback }
        guard !rule.escalate.isEmpty else { return (rule.tier, rule.id) }
        let joined = resources.joined(separator: "\n")
        if joined.utf16.count > maxLength { return tooLong }
        let text = joined.lowercased()
        if let match = rule.escalate.first(where: { text.range(of: $0.pattern, options: .regularExpression) != nil }) {
            return (match.tier, match.id)
        }
        return (rule.tier, rule.id)
    }
}

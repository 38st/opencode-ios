import Foundation
import OCFoundation

/// `GET /api/experimental/session/stats` (`SessionStats.Info`). Days in `activity` are dates in the requested time zone.
public struct SessionStats: WireValue {
    public var raw: JSONValue
    public init(raw: JSONValue) { self.raw = raw }
    public var sessions: Int { self["sessions"]?.wireInt ?? 0 }
    public var subagents: Int { self["subagents"]?.wireInt ?? 0 }
    public var prompts: Int { self["prompts"]?.wireInt ?? 0 }
    public var steps: Int { self["steps"]?.wireInt ?? 0 }
    public var tokens: TokenUsage { object("tokens") }
    public var cost: Double { number("cost") }
    public var activeDays: Int { self["activeDays"]?.wireInt ?? 0 }
    public var streak: Int { self["streak"]?.wireInt ?? 0 }
    public var tools: Tools { object("tools") }
    public var activity: [Day] { self["activity"]?.lossy(Day.self).values ?? [] }
    public var models: [ModelUsage] { self["models"]?.lossy(ModelUsage.self).values ?? [] }
    public var isEmpty: Bool { sessions == 0 && prompts == 0 && steps == 0 }

    public struct Tools: WireValue {
        public var raw: JSONValue
        public init(raw: JSONValue) { self.raw = raw }
        public var calls: Int { raw["totals"]?["calls"]?.wireInt ?? 0 }
        public var succeeded: Int { raw["totals"]?["succeeded"]?.wireInt ?? 0 }
        public var failed: Int { raw["totals"]?["failed"]?.wireInt ?? 0 }
        public var unfinished: Int { raw["totals"]?["unfinished"]?.wireInt ?? 0 }
        /// Per tool, when the request asked for `tools=detail`; most calls first.
        public var byTool: [Tool] {
            (self["usage"]?.lossy(Tool.self).values ?? []).sorted { $0.calls > $1.calls || $0.calls == $1.calls && $0.name < $1.name }
        }
    }
    public struct Tool: WireValue {
        public var raw: JSONValue
        public init(raw: JSONValue) { self.raw = raw }
        public var name: String { string("name") }
        public var calls: Int { self["calls"]?.wireInt ?? 0 }
        public var failed: Int { self["failed"]?.wireInt ?? 0 }
        /// Median duration in milliseconds, when the server measured one.
        public var medianDuration: Double? { self["durationP50"]?.wireNumber }
    }
    public struct Day: WireValue {
        public var raw: JSONValue
        public init(raw: JSONValue) { self.raw = raw }
        public var date: String { string("date") }
        public var steps: Int { self["steps"]?.wireInt ?? 0 }
    }
    public struct ModelUsage: WireValue {
        public var raw: JSONValue
        public init(raw: JSONValue) { self.raw = raw }
        public var model: ModelRef { object("model") }
        public var steps: Int { self["steps"]?.wireInt ?? 0 }
        public var tokens: TokenUsage { object("tokens") }
        public var cost: Double { number("cost") }
    }
}

/// A date range for statistics, in the device's time zone: whole days ending today.
public struct StatsRange: Hashable, Sendable {
    public enum Preset: String, CaseIterable, Sendable {
        case today, week, month, quarter
        public var title: String {
            switch self { case .today: localized("Today", comment: "Statistics range"); case .week: localized("7 days", comment: "Statistics range"); case .month: localized("30 days", comment: "Statistics range"); case .quarter: localized("90 days", comment: "Statistics range") }
        }
        var days: Int { switch self { case .today: 1; case .week: 7; case .month: 30; case .quarter: 90 } }
    }
    public let from: Date
    public let to: Date
    public let timeZone: TimeZone
    public init(_ preset: Preset, now: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        from = calendar.date(byAdding: .day, value: 1 - preset.days, to: today) ?? today
        to = now; self.timeZone = timeZone
    }
    /// Epoch milliseconds, as the server expects them.
    public var query: [(String, String)] {
        [("from", String(Int64(from.timeIntervalSince1970 * 1_000))), ("to", String(Int64(to.timeIntervalSince1970 * 1_000))),
         ("timezone", timeZone.identifier)]
    }
}

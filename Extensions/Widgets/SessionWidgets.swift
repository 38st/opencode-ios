import AppIntents
import OCIntents
import OCShared
import SwiftUI
import WidgetKit

struct SessionsEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
    let size: WidgetSize
}

/// Reads the App Group snapshot and the push store's pending counts; never a server. The app reloads these timelines whenever
/// what they show changes, and the plan adds the moment the content turns stale.
struct SessionsProvider: AppIntentTimelineProvider {
    let kind: WidgetKind
    func placeholder(in context: Context) -> SessionsEntry {
        SessionsEntry(date: .now, content: .placeholder(kind: kind, size: context.family.size), size: context.family.size)
    }
    func snapshot(for configuration: SessionsWidgetIntent, in context: Context) async -> SessionsEntry {
        let now = Date.now, size = context.family.size
        let content = WidgetContent.make(Self.read(), pending: Self.pending(), kind: kind, server: configuration.serverID, size: size, now: now)
        // The gallery shows the sample until the app has data to show.
        if context.isPreview && content.state != .rows { return SessionsEntry(date: now, content: .placeholder(kind: kind, size: size), size: size) }
        return SessionsEntry(date: now, content: content, size: size)
    }
    func timeline(for configuration: SessionsWidgetIntent, in context: Context) async -> Timeline<SessionsEntry> {
        let size = context.family.size
        let plan = WidgetTimelinePlan.make(Self.read(), pending: Self.pending(), kind: kind, server: configuration.serverID, size: size, now: .now)
        return Timeline(entries: plan.entries.map { SessionsEntry(date: $0.date, content: $0.content, size: size) }, policy: .after(plan.refresh))
    }
    static func read() -> SystemSnapshotStore.Read { (try? SystemSnapshotStore.appGroup())?.read() ?? .missing }
    static func pending() -> [String: Int] { (try? PushSnapshotStore.appGroup().pendingCounts()) ?? [:] }
}

extension WidgetFamily {
    var size: WidgetSize {
        switch self {
        case .systemSmall: .small
        case .systemLarge, .systemExtraLarge: .large
        case .accessoryCircular: .circular
        case .accessoryRectangular: .rectangular
        case .accessoryInline: .inline
        default: .medium
        }
    }
}

struct SessionsWidgetEntryView: View {
    let entry: SessionsEntry
    var body: some View {
        SessionWidgetView(content: entry.content, size: entry.size, now: entry.date)
            .widgetURL(entry.content.url)
            .containerBackground(WidgetStyle.background, for: .widget)
    }
}

struct NeedsYouWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.needsYou.rawValue, intent: SessionsWidgetIntent.self, provider: SessionsProvider(kind: .needsYou)) {
            SessionsWidgetEntryView(entry: $0)
        }
        .configurationDisplayName("Needs you")
        .description("Requests waiting for your approval or answer, and failed runs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RunningWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.running.rawValue, intent: SessionsWidgetIntent.self, provider: SessionsProvider(kind: .running)) {
            SessionsWidgetEntryView(entry: $0)
        }
        .configurationDisplayName("Running")
        .description("Sessions that are running now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.recent.rawValue, intent: SessionsWidgetIntent.self, provider: SessionsProvider(kind: .recent)) {
            SessionsWidgetEntryView(entry: $0)
        }
        .configurationDisplayName("Recent")
        .description("Your latest sessions.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

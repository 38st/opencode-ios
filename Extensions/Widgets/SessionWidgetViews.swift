import OCShared
import SwiftUI
import WidgetKit

/// A Needs you, Running or Recent widget: Home Screen sizes list sessions, the Lock Screen shows the waiting count and
/// the top request. Titles are privacy sensitive, so a locked device shows them redacted; counts stay.
struct SessionWidgetView: View {
    let content: WidgetContent
    let size: WidgetSize
    /// The entry's date, which times are shown against.
    let now: Date
    var body: some View {
        switch size {
        case .circular: CircularWidget(content: content)
        case .rectangular: RectangularWidget(content: content)
        case .inline: InlineWidget(content: content)
        case .small, .medium, .large: SystemWidget(content: content, size: size, now: now)
        }
    }
}

struct SystemWidget: View {
    let content: WidgetContent
    let size: WidgetSize
    let now: Date
    var body: some View {
        // A widget's size is fixed: text grows to extra large and no further, so rows never clip.
        VStack(alignment: .leading, spacing: size == .small ? 6 : 10) {
            WidgetHeader(content: content, compact: size == .small)
            if content.state == .rows || content.state == .placeholder {
                VStack(alignment: .leading, spacing: size == .small ? 4 : 8) {
                    ForEach(content.rows) { row in
                        if size != .small, let url = row.url {
                            Link(destination: url) { WidgetRow(row: row, stale: content.stale, compact: false, sensitive: content.state != .placeholder, now: now) }
                        } else {
                            WidgetRow(row: row, stale: content.stale, compact: size == .small, sensitive: content.state != .placeholder, now: now)
                        }
                    }
                }
                Spacer(minLength: 0)
                WidgetFooter(content: content, now: now)
            } else {
                Spacer(minLength: 0)
                WidgetMessage(content: content, compact: size == .small)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .redacted(reason: content.state == .placeholder ? .placeholder : [])
    }
}

/// The widget's name, the server it shows, and its count.
struct WidgetHeader: View {
    let content: WidgetContent
    /// The small size has no room beside the title: the server's name goes under it.
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                KindGlyph(kind: content.kind)
                Text(content.kind.title).font(WidgetStyle.heading).foregroundStyle(WidgetStyle.text).lineLimit(1)
                if !compact, let server = content.serverName { serverName(server) }
                Spacer(minLength: 4)
                if content.kind != .recent, content.state == .rows || content.state == .placeholder {
                    Text("\(content.count)").font(WidgetStyle.heading.monospacedDigit())
                        .foregroundStyle(content.stale ? WidgetStyle.muted : content.kind == .needsYou ? WidgetStyle.warning : WidgetStyle.success)
                        .widgetAccentable().accessibilityLabel(content.kind.countLabel(content.count))
                }
            }
            if compact, let server = content.serverName { serverName(server) }
        }
    }
    private func serverName(_ name: String) -> some View { Text(name).font(WidgetStyle.micro).secondary().lineLimit(1) }
}

struct WidgetRow: View {
    let row: WidgetContent.Row
    let stale: Bool
    let compact: Bool
    /// Titles are privacy sensitive; the gallery's sample is not, so its placeholder redaction applies.
    var sensitive = true
    let now: Date
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusGlyph(status: row.status, unread: row.unread, stale: stale).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(WidgetStyle.small.weight(row.unread ? .semibold : .regular))
                    .foregroundStyle(stale ? WidgetStyle.muted : WidgetStyle.text).lineLimit(compact ? 3 : 1).sensitive(sensitive)
                // Locked (StandBy), the project and server go with the title, as on the Lock Screen; the kind stays.
                HStack(spacing: 0) {
                    Text(row.label(stale: stale)).layoutPriority(1)
                    Text(" · " + row.detail).sensitive(sensitive)
                }.font(WidgetStyle.micro).secondary().lineLimit(1)
            }
            if !compact {
                Spacer(minLength: 4)
                Text(WidgetTime.text(row.date, now: now, locale: locale, timeZone: timeZone)).font(WidgetStyle.micro.monospacedDigit()).secondary().lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rows that did not fit, and how old the data is once it is stale.
struct WidgetFooter: View {
    let content: WidgetContent
    let now: Date
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    var body: some View {
        if content.overflow > 0 || content.stale {
            VStack(alignment: .leading, spacing: 2) {
                if content.overflow > 0 { Text("+\(content.overflow) more").font(WidgetStyle.micro).secondary() }
                if content.stale {
                    Text(content.updated.map { "Updated " + WidgetTime.text($0, now: now, locale: locale, timeZone: timeZone) } ?? "Not updated recently")
                        .font(WidgetStyle.micro).foregroundStyle(WidgetStyle.muted)
                    Text("Open the app to refresh").font(WidgetStyle.micro).secondary()
                }
            }
        }
    }
}

/// What a widget without rows says.
struct WidgetMessage: View {
    let content: WidgetContent
    let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.message.title).font(compact ? WidgetStyle.small.weight(.medium) : WidgetStyle.body.weight(.medium)).foregroundStyle(WidgetStyle.text)
            Text(content.message.detail).font(WidgetStyle.micro).secondary().lineLimit(compact ? 3 : 2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CircularWidget: View {
    let content: WidgetContent
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                AccessoryGlyph(content: content, side: 14)
                Text(content.showsCount ? "\(content.count)" : "–").font(WidgetStyle.inter(20, relativeTo: .title2, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.showsCount ? WidgetKind.needsYou.countLabel(content.count) : content.message.title)
    }
}

struct RectangularWidget: View {
    let content: WidgetContent
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                AccessoryGlyph(content: content, side: 12)
                Text(content.showsCount && content.count > 0 ? WidgetKind.needsYou.countLabel(content.count) : "Needs you").font(WidgetStyle.heading).lineLimit(1)
            }
            .widgetAccentable()
            if let row = content.rows.first {
                let sensitive = content.state != .placeholder
                Text(row.title).font(WidgetStyle.small.weight(.medium)).lineLimit(1).sensitive(sensitive)
                // While locked only the kind of request shows: the project and server are redacted with the title.
                HStack(spacing: 0) {
                    Text(row.label(stale: content.stale)).layoutPriority(1)
                    Text(" · " + row.detail).sensitive(sensitive)
                }.font(WidgetStyle.micro).lineLimit(1)
            } else {
                Text(content.message.title).font(WidgetStyle.small).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct InlineWidget: View {
    let content: WidgetContent
    var body: some View {
        Label(content.showsCount && content.count > 0 ? WidgetKind.needsYou.countLabel(content.count) : content.message.title,
              systemImage: content.accessoryIcon.symbol)
    }
}

extension WidgetContent {
    /// The accessories' glyph: a warning when something waits, a check when nothing does, a clock once that is only
    /// the last known state (the Lock Screen has no room for "Updated"), and the server icon while a message stands in
    /// for the count (no data yet, an update, no server, a removed server). The app's icons where it has one.
    var accessoryIcon: (asset: String?, symbol: String) {
        guard showsCount else { return ("server", "server.rack") }
        if stale { return (nil, "clock") }
        return count > 0 ? ("warning", "exclamationmark.triangle") : ("check", "checkmark")
    }
}

struct AccessoryGlyph: View {
    let content: WidgetContent
    let side: CGFloat
    var body: some View {
        let icon = content.accessoryIcon
        (icon.asset.map { WidgetStyle.icon($0) } ?? Image(systemName: icon.symbol)).resizable().scaledToFit().frame(width: side, height: side)
    }
}

/// Home's session indicator: needs you, failed, running (hollow once stale), unread or idle.
struct StatusGlyph: View {
    let status: SystemSnapshot.Status
    let unread: Bool
    let stale: Bool
    var body: some View {
        Group {
            switch status {
            case .needsYou: WidgetStyle.icon("warning").resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(WidgetStyle.warning)
            case .failed: WidgetStyle.icon("circle-x").resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(WidgetStyle.danger)
            case .running, .retrying:
                if stale { Circle().strokeBorder(lineWidth: 1.5).frame(width: 7, height: 7).foregroundStyle(WidgetStyle.muted) }
                else { Circle().frame(width: 7, height: 7).foregroundStyle(status == .running ? WidgetStyle.success : WidgetStyle.warning) }
            case .idle:
                if unread { Circle().frame(width: 7, height: 7).foregroundStyle(WidgetStyle.info) }
                else { WidgetStyle.icon("check").resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(WidgetStyle.faint) }
            }
        }
        .frame(width: 12, height: 12).widgetAccentable().accessibilityHidden(true)
    }
}

struct KindGlyph: View {
    let kind: WidgetKind
    var body: some View {
        switch kind {
        case .needsYou: WidgetStyle.icon("warning").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(WidgetStyle.warning).widgetAccentable()
        case .running: Circle().frame(width: 8, height: 8).foregroundStyle(WidgetStyle.success).widgetAccentable()
        case .recent: WidgetStyle.icon("server").resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(WidgetStyle.muted)
        }
    }
}

/// A row's time: the time of day for today, else the date, in the view's locale and time zone.
enum WidgetTime {
    static func text(_ date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone; calendar.locale = locale
        let style = calendar.isDate(date, inSameDayAs: now)
            ? Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
            : Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day()
        return date.formatted(style)
    }
}

extension WidgetKind {
    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .running: "Running"
        case .recent: "Recent"
        }
    }
    func countLabel(_ count: Int) -> String {
        switch self {
        case .needsYou: count == 1 ? "1 waiting" : "\(count) waiting"
        case .running: count == 1 ? "1 running" : "\(count) running"
        case .recent: "\(count) sessions"
        }
    }
}

extension WidgetContent {
    /// A count to show: real data, or the gallery's sample (which the system redacts).
    var showsCount: Bool { state == .rows || state == .empty || state == .placeholder }
    var message: (title: String, detail: String) {
        switch state {
        case .noData: ("Open the app", "Your sessions appear here once the app has loaded them.")
        case .needsApp: ("Open the app", "The app was updated; open it once to refresh this widget.")
        case .noServer: ("No servers", "Pair a server in the app to see its sessions here.")
        case .serverRemoved: ("Server removed", "Edit the widget to choose another server.")
        case .empty, .rows, .placeholder:
            switch kind {
            case .needsYou: ("Nothing needs you", "Requests and failed runs appear here.")
            case .running: ("Nothing running", "Running sessions appear here.")
            case .recent: ("No sessions yet", "Your latest sessions appear here.")
            }
        }
    }
}

/// Secondary text: a faint colour in full colour; in the tinted Home Screen and on the Lock Screen, where the system
/// draws every element in one tint, lower opacity keeps the hierarchy.
private struct SecondaryText: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    func body(content: Content) -> some View {
        if mode == .fullColor { content.foregroundStyle(WidgetStyle.faint) } else { content.opacity(0.6) }
    }
}
/// Privacy sensitive, or not marked at all: a view marked even as not sensitive escapes the placeholder's redaction.
private struct Sensitive: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.privacySensitive() } else { content }
    }
}
extension View {
    func secondary() -> some View { modifier(SecondaryText()) }
    func sensitive(_ enabled: Bool) -> some View { modifier(Sensitive(enabled: enabled)) }
}

import SwiftUI

public struct OCProjectAvatar: View {
    let name: String
    @ScaledMetric(relativeTo: .caption2) private var side = OCSpacing.xl
    public init(_ name: String) { self.name = name }
    public var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(OCType.micro)
            .foregroundStyle(OCColor.textMuted).frame(width: side, height: side)
            .background(OCColor.layer2, in: RoundedRectangle(cornerRadius: OCRadius.sm)).accessibilityHidden(true)
    }
}
public struct OCToolChrome<Content: View>: View {
    @Environment(\.ocDisclosureInteraction) private var onDisclosureInteraction
    let title: String
    let subtitle: String
    let icon: String
    let status: String
    let badge: String?
    let failed: Bool
    let inline: Bool
    let onOpen: (() -> Void)?
    let content: Content
    let defaultExpanded: Bool
    @State private var expanded: Bool
    public init(_ title: String, subtitle: String = "", icon: String = "code", status: String = "completed",
                badge: String? = nil, failed: Bool = false, expanded: Bool = false, inline: Bool = false, onOpen: (() -> Void)? = nil,
                @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.status = status; self.onOpen = onOpen
        self.badge = badge; self.failed = failed; self.inline = inline; self.content = content(); defaultExpanded = expanded; _expanded = State(initialValue: expanded)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack(alignment: .top, spacing: 0) { disclosure; if let onOpen { OCIconButton("Open file", icon: "open-file", action: onOpen) } }
            if expanded { content.padding(.leading, OCSpacing.xl) }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: defaultExpanded) { _, value in expanded = value }
    }
    private var disclosure: some View {
        Button { onDisclosureInteraction(); expanded.toggle() } label: {
            HStack(alignment: .top, spacing: OCSpacing.sm) {
                OCIcon(icon).foregroundStyle(failed ? OCColor.danger : OCColor.iconMuted).padding(.top, OCSpacing.xs)
                VStack(alignment: .leading, spacing: OCSpacing.xs) {
                    if inline {
                        Text(title + (subtitle.isEmpty ? "" : " " + subtitle)).font(OCType.small).foregroundStyle(OCColor.textMuted)
                    } else {
                    Text(title).font(OCType.small.weight(.medium))
                    if !subtitle.isEmpty { Text(subtitle).font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(2) }
                    }
                    if status != "completed" || badge != nil {
                        ViewThatFits(in: .horizontal) {
                            HStack { OCBadge(badge ?? status.capitalized, tone: failed ? .danger : .neutral) }
                            OCBadge(badge ?? status.capitalized, tone: failed ? .danger : .neutral)
                        }
                    }
                }
                Spacer(minLength: 0)
                OCIcon(expanded ? "chevron-down" : "chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
            }.frame(minHeight: OCLayout.touchTarget, alignment: .center).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel([title, subtitle, badge ?? (status == "completed" ? "" : status.capitalized)].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityActions { if let onOpen { Button("Open file", action: onOpen) } }
    }
}
private struct OCDisclosureInteractionKey: EnvironmentKey {
    nonisolated static let defaultValue: @MainActor @Sendable () -> Void = {}
}
extension EnvironmentValues {
    public var ocDisclosureInteraction: @MainActor @Sendable () -> Void {
        get { self[OCDisclosureInteractionKey.self] }
        set { self[OCDisclosureInteractionKey.self] = newValue }
    }
}
public struct OCSessionIndicator: View {
    /// `staleRunning` and `offline` are shown while the server is unreachable: the state is only last known.
    public enum State: String, Sendable { case needsYou, failed, running, staleRunning, unread, syncing, offline, idle }
    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    public init(_ state: State) { self.state = state }
    private var tone: OCTone {
        switch state { case .needsYou: .warning; case .failed: .danger; case .running: .success; case .unread: .info; default: .neutral }
    }
    private var accessibilityTitle: String {
        switch state {
        case .needsYou: "Needs you"
        case .staleRunning: "Last seen running"
        default: state.rawValue.capitalized
        }
    }
    public var body: some View {
        Group {
            switch state {
            case .needsYou: OCIcon("warning", size: 12)
            case .failed: OCIcon("circle-x", size: 12)
            case .syncing: OCIcon("refresh", size: 12)
            case .idle: OCIcon("check", size: 12)
            case .offline: OCIcon("circle-ban-sign", size: 12)
            case .running, .unread: Circle().frame(width: 6, height: 6)
            case .staleRunning: Circle().strokeBorder(lineWidth: 1.5).frame(width: 6, height: 6)
            }
        }.foregroundStyle(tone.foreground)
            .opacity(state == .running && !reduceMotion && breathing ? 0.45 : 1)
            .animation(state == .running && !reduceMotion ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil, value: breathing)
            .onAppear { breathing = true }.onChange(of: reduceMotion) { _, _ in breathing = !reduceMotion }
            .accessibilityLabel(accessibilityTitle)
    }
}

public struct OCJumpToLatest: View {
    let count: Int
    let action: () -> Void
    public init(count: Int, action: @escaping () -> Void) { self.count = count; self.action = action }
    public var body: some View {
        Button(action: action) {
            OCLabel(count > 0 ? "Jump to latest (\(count))" : "Jump to latest", icon: "arrow-down-to-line")
                .font(OCType.button).foregroundStyle(OCColor.text)
                .padding(.horizontal, OCSpacing.lg).padding(.vertical, OCSpacing.sm)
                .frame(minHeight: OCLayout.touchTarget)
                .background(OCColor.background, in: Capsule())
                .overlay(Capsule().strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
                .ocElevation(.raised)
        }.buttonStyle(.plain).accessibilityIdentifier("jumpToLatest")
    }
}

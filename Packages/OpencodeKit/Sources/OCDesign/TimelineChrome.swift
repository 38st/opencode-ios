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
    let actions: [OCAccessibilityAction]
    let content: Content
    let defaultExpanded: Bool
    @State private var expanded: Bool
    public init(_ title: String, subtitle: String = "", icon: String = "code", status: String = "completed",
                badge: String? = nil, failed: Bool = false, expanded: Bool = false, inline: Bool = false, onOpen: (() -> Void)? = nil,
                actions: [OCAccessibilityAction] = [], @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.status = status; self.onOpen = onOpen; self.actions = actions
        self.badge = badge; self.failed = failed; self.inline = inline; self.content = content(); defaultExpanded = expanded; _expanded = State(initialValue: expanded)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack(alignment: .top, spacing: 0) { disclosure; if let onOpen { OCIconButton(localized("Open file"), icon: "open-file", action: onOpen) } }
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
                            HStack { OCBadge(badge ?? statusTitle, tone: failed ? .danger : .neutral) }
                            OCBadge(badge ?? statusTitle, tone: failed ? .danger : .neutral)
                        }
                    }
                }
                Spacer(minLength: 0)
                OCIcon(expanded ? "chevron-down" : "chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
            }.frame(minHeight: OCLayout.touchTarget, alignment: .center).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel([title, subtitle, badge ?? (status == "completed" ? "" : statusTitle)].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityValue(expanded ? localized("Expanded") : localized("Collapsed"))
            .accessibilityActions {
                if let onOpen { Button(localized("Open file"), action: onOpen) }
                ForEach(actions) { action in Button(action.name, action: action.perform) }
            }
    }
    private var statusTitle: String {
        switch status {
        case "pending": localized("Pending", comment: "Tool call status")
        case "running": localized("Running", comment: "Tool call status")
        case "streaming": localized("Streaming", comment: "Tool call status")
        case "error": localized("Error", comment: "Tool call status")
        default: status.capitalized
        }
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
        case .needsYou: localized("Needs you", comment: "Session status")
        case .failed: localized("Failed", comment: "Session status")
        case .running: localized("Running", comment: "Session status")
        case .staleRunning: localized("Last seen running", comment: "Session status")
        case .unread: localized("Unread", comment: "Session status")
        case .syncing: localized("Syncing", comment: "Session status")
        case .offline: localized("Offline", comment: "Session status")
        case .idle: localized("Idle", comment: "Session status")
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
            .opacity(state == .running && breathing ? 0.45 : 1)
            // A few breaths when a run starts or the row appears, then a steady dot: an endless animation would keep the
            // app from ever being idle, which UI automation and the system both wait for.
            .task(id: state == .running && !reduceMotion) {
                guard state == .running && !reduceMotion else { breathing = false; return }
                for _ in 0..<3 {
                    withAnimation(.easeInOut(duration: 0.6)) { breathing = true }
                    try? await Task.sleep(for: .milliseconds(600))
                    withAnimation(.easeInOut(duration: 0.6)) { breathing = false }
                    try? await Task.sleep(for: .milliseconds(600))
                    if Task.isCancelled { break }
                }
            }
            .accessibilityLabel(accessibilityTitle)
    }
}

public struct OCJumpToLatest: View {
    let count: Int
    let action: () -> Void
    public init(count: Int, action: @escaping () -> Void) { self.count = count; self.action = action }
    public var body: some View {
        Button(action: action) {
            OCLabel(count > 0 ? localized("Jump to latest (\(count))", comment: "%lld is the number of new messages") : localized("Jump to latest"), icon: "arrow-down-to-line")
                .font(OCType.button).foregroundStyle(OCColor.text)
                .padding(.horizontal, OCSpacing.lg).padding(.vertical, OCSpacing.sm)
                .frame(minHeight: OCLayout.touchTarget)
                .background(OCColor.background, in: Capsule())
                .overlay(Capsule().strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
                .ocElevation(.raised)
        }.buttonStyle(.plain).accessibilityIdentifier("jumpToLatest")
    }
}

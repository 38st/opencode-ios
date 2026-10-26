// Sources: packages/ui/src/data-display/badge/badge.css; packages/app/src/home;
// packages/session-ui/src/components/basic-tool.css and v2/components/session-review-v2.css.
import SwiftUI

public enum OCTone: Sendable {
    case neutral, info, success, warning, danger
    public var foreground: Color { switch self {
    case .neutral: OCColor.textMuted; case .info: OCColor.info; case .success: OCColor.success
    case .warning: OCColor.warning; case .danger: OCColor.danger
    } }
    public var background: Color { switch self {
    case .neutral: OCColor.layer1; case .info: OCColor.infoBackground; case .success: OCColor.successBackground
    case .warning: OCColor.warningBackground; case .danger: OCColor.dangerBackground
    } }
}
public struct OCStatusDot: View {
    let tone: OCTone
    public init(_ tone: OCTone) { self.tone = tone }
    public var body: some View { Circle().fill(tone.foreground).frame(width: 6, height: 6).accessibilityHidden(true) }
}
public struct OCBadge: View {
    let title: String
    let tone: OCTone
    public init(_ title: String, tone: OCTone = .neutral) { self.title = title; self.tone = tone }
    public var body: some View {
        Text(title).font(OCType.micro).foregroundStyle(tone.foreground)
            .padding(.horizontal, OCSpacing.xs).padding(.vertical, OCSpacing.xxs)
            .background(tone.background, in: RoundedRectangle(cornerRadius: OCRadius.xs))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.xs).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
    }
}
public struct OCPill: View {
    let title: String
    let tone: OCTone
    public init(_ title: String, tone: OCTone = .neutral) { self.title = title; self.tone = tone }
    public var body: some View {
        HStack(spacing: OCSpacing.sm) { OCStatusDot(tone); Text(title).font(OCType.small) }
            .foregroundStyle(tone.foreground).padding(.horizontal, OCSpacing.sm).padding(.vertical, OCSpacing.xs)
            .background(tone.background, in: RoundedRectangle(cornerRadius: OCRadius.md))
    }
}
public struct OCSidebarHeader: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title).font(OCType.small.weight(.medium)).foregroundStyle(OCColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}
public struct OCListRow: View {
    public enum Kind: Sendable { case session, project }
    let title: String
    let subtitle: String?
    let kind: Kind
    let selected: Bool
    public init(_ title: String, subtitle: String? = nil, kind: Kind = .session, selected: Bool = false) {
        self.title = title; self.subtitle = subtitle; self.kind = kind; self.selected = selected
    }
    public var body: some View {
        HStack(spacing: OCSpacing.md) {
            OCIcon(kind == .project ? "folder" : "bubble-5").foregroundStyle(OCColor.icon)
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text(title).font(OCType.body)
                if let subtitle { Text(subtitle).font(OCType.small).foregroundStyle(OCColor.textMuted) }
            }
            Spacer(minLength: 0)
        }.padding(OCSpacing.sm).frame(minHeight: OCLayout.touchTarget)
            .background(selected ? OCColor.pressed : .clear, in: RoundedRectangle(cornerRadius: OCRadius.md))
    }
}
public struct OCCodeFrame<Content: View>: View {
    let title: String
    let content: Content
    public init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OCLabel(title, icon: "code").font(OCType.small).foregroundStyle(OCColor.textMuted)
                .padding(OCSpacing.md).frame(maxWidth: .infinity, alignment: .leading).background(OCColor.band)
            content.font(OCType.code).padding(OCSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
        }.background(OCColor.backgroundDeep).clipShape(RoundedRectangle(cornerRadius: OCRadius.md))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
    }
}
public struct OCToolRow<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @State private var expanded = false
    public init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }
    public var body: some View {
        DisclosureGroup(isExpanded: $expanded) { content.font(OCType.code) } label: {
            OCLabel(title, icon: icon).font(OCType.small).frame(minHeight: OCLayout.touchTarget)
        }.tint(OCColor.iconMuted)
    }
}
#Preview("Rows and code") {
    OCForm {
        OCSidebarHeader("Projects")
        OCListRow("opencode-ios", subtitle: "3 sessions", kind: .project)
        OCListRow("Restyle the server screens", selected: true)
        HStack { OCBadge("V2"); OCPill("Connected", tone: .success) }
        OCCodeFrame("Terminal") { Text("opencode serve").textSelection(.enabled) }
        OCToolRow("Read sample.txt", icon: "code") { Text("original fixture line") }
    }.ocTheme()
}

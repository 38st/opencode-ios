// Sources: packages/session-ui/src/v2/components/session-review-v2.css,
// packages/app/src/session and packages/ui/src/components/dock-surface.css.
import SwiftUI

public struct OCWorkspacePanel: View {
    @State private var localSelection = "Changes"
    private var externalSelection: Binding<String>?
    private var title: String = localized("Files Changed")
    private var content: ((String) -> AnyView)?
    public init() {}
    public init<Content: View>(selection: Binding<String>, title: String, @ViewBuilder content: @escaping (String) -> Content) {
        externalSelection = selection; self.title = title; self.content = { AnyView(content($0)) }
    }
    private var selection: String { externalSelection?.wrappedValue ?? localSelection }
    private var binding: Binding<String> { externalSelection ?? $localSelection }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if content == nil { HStack {
                Text(title).font(OCType.button)
                if content == nil { OCBadge(0.formatted()) }
                Spacer(minLength: 0)
                OCIcon("sidebar-right").foregroundStyle(OCColor.iconMuted)
            }.padding(OCSpacing.md).frame(minHeight: OCLayout.touchTarget) }
            if content != nil {
                ScrollView(.horizontal) {
                    OCSegmentedControl(localized("Review panel"), options: ["Changes", "Files", "Terminal", "Context"].map { ($0, $0 == "Changes" ? title : Self.tabTitle($0)) }, selection: binding, equalWidth: false)
                }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
            } else {
                OCSegmentedControl(localized("Review panel"), options: ["Changes", "Files", "Terminal", "Context"].map { ($0, Self.tabTitle($0)) }, selection: binding).padding(.horizontal, OCSpacing.sm)
            }
            if let content { content(selection).frame(maxWidth: .infinity, maxHeight: .infinity) } else {
            HStack(spacing: OCSpacing.sm) {
                OCIcon(selection == "Changes" ? "branch" : selection == "Files" ? "file-tree" : selection == "Terminal" ? "terminal" : "brain")
                Text(selection == "Changes" ? localized("Git changes") : Self.tabTitle(selection)).font(OCType.small)
                Spacer(minLength: 0)
                if selection == "Changes" {
                    Text(verbatim: "+0").foregroundStyle(OCColor.success)
                    Text(verbatim: "−0").foregroundStyle(OCColor.danger)
                }
            }.font(OCType.small).padding(OCSpacing.md)
            Rectangle().fill(OCColor.border).frame(height: OCBorder.hairline)
            ScrollView {
                VStack(spacing: OCSpacing.md) {
                    OCIcon(selection == "Changes" ? "review" : selection == "Files" ? "file-tree" : selection == "Terminal" ? "terminal" : "brain", size: 24)
                    Text(Self.placeholder(selection)).font(OCType.button)
                    Text(localized("Review tools are not available yet.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                }.multilineTextAlignment(.center).foregroundStyle(OCColor.iconMuted)
                    .padding(OCSpacing.xl).frame(maxWidth: .infinity).padding(.top, OCSpacing.section)
            }.frame(maxHeight: .infinity)
            }
        }.background(OCColor.background).clipShape(RoundedRectangle(cornerRadius: OCRadius.xl))
    }
    private static func tabTitle(_ tab: String) -> String {
        switch tab {
        case "Changes": localized("Changes", comment: "Review panel tab")
        case "Files": localized("Files", comment: "Review panel tab")
        case "Terminal": localized("Terminal", comment: "Review panel tab")
        case "Context": localized("Context", comment: "Review panel tab")
        default: tab
        }
    }
    private static func placeholder(_ tab: String) -> String {
        switch tab {
        case "Changes": localized("Changes will appear here")
        case "Files": localized("Files will appear here")
        case "Terminal": localized("Terminal will appear here")
        case "Context": localized("Context will appear here")
        default: localized("\(tab) will appear here", comment: "%@ is a review panel tab name")
        }
    }
}
public struct OCDisabledPromptDock: View {
    public init() {}
    public var body: some View {
        OCPromptDock {
            VStack(alignment: .leading, spacing: OCSpacing.xl) {
                Text(localized("Ask anything, / for commands, @ for context…")).font(OCType.small).foregroundStyle(OCColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: OCSpacing.md) {
                    OCIcon("plus").foregroundStyle(OCColor.iconMuted)
                    OCLabel(localized("Select model"), icon: "cube").font(OCType.small).foregroundStyle(OCColor.textMuted)
                    Spacer(minLength: 0)
                    OCIcon("arrow-up").padding(OCSpacing.xs)
                        .background(OCColor.layer4, in: RoundedRectangle(cornerRadius: OCRadius.sm))
                }
            }
        }.allowsHitTesting(false).accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("Message composer. Ask anything, slash for commands, at for context. Sending is not available yet."))
            .disabled(true)
    }
}
#Preview("Review and dock") {
    VStack { OCWorkspacePanel(); OCDisabledPromptDock() }.padding(OCSpacing.sm).ocTheme()
}

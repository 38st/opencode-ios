// Sources: packages/session-ui/src/v2/components/session-review-v2.css,
// packages/app/src/session and packages/ui/src/components/dock-surface.css.
import SwiftUI

public struct OCWorkspacePanel: View {
    @State private var localSelection = "Changes"
    private var externalSelection: Binding<String>?
    private var title: String = "Files Changed"
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
                if content == nil { OCBadge("0") }
                Spacer(minLength: 0)
                OCIcon("sidebar-right").foregroundStyle(OCColor.iconMuted)
            }.padding(OCSpacing.md).frame(minHeight: OCLayout.touchTarget) }
            if content != nil {
                ScrollView(.horizontal) {
                    OCSegmentedControl("Review panel", options: ["Changes", "Files", "Terminal", "Context"].map { ($0, $0 == "Changes" ? title : $0) }, selection: binding, equalWidth: false)
                }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
            } else {
                OCSegmentedControl("Review panel", options: ["Changes", "Files", "Terminal", "Context"].map { ($0, $0) }, selection: binding).padding(.horizontal, OCSpacing.sm)
            }
            if let content { content(selection).frame(maxWidth: .infinity, maxHeight: .infinity) } else {
            HStack(spacing: OCSpacing.sm) {
                OCIcon(selection == "Changes" ? "branch" : selection == "Files" ? "file-tree" : selection == "Terminal" ? "terminal" : "brain")
                Text(selection == "Changes" ? "Git changes" : selection).font(OCType.small)
                Spacer(minLength: 0)
                if selection == "Changes" {
                    Text("+0").foregroundStyle(OCColor.success)
                    Text("−0").foregroundStyle(OCColor.danger)
                }
            }.font(OCType.small).padding(OCSpacing.md)
            Rectangle().fill(OCColor.border).frame(height: OCBorder.hairline)
            ScrollView {
                VStack(spacing: OCSpacing.md) {
                    OCIcon(selection == "Changes" ? "review" : selection == "Files" ? "file-tree" : selection == "Terminal" ? "terminal" : "brain", size: 24)
                    Text("\(selection) will appear here").font(OCType.button)
                    Text("Review tools are not available yet.").font(OCType.small).foregroundStyle(OCColor.textMuted)
                }.multilineTextAlignment(.center).foregroundStyle(OCColor.iconMuted)
                    .padding(OCSpacing.xl).frame(maxWidth: .infinity).padding(.top, OCSpacing.section)
            }.frame(maxHeight: .infinity)
            }
        }.background(OCColor.background).clipShape(RoundedRectangle(cornerRadius: OCRadius.xl))
    }
}
public struct OCDisabledPromptDock: View {
    public init() {}
    public var body: some View {
        OCPromptDock {
            VStack(alignment: .leading, spacing: OCSpacing.xl) {
                Text("Ask anything, / for commands, @ for context…").font(OCType.small).foregroundStyle(OCColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: OCSpacing.md) {
                    OCIcon("plus").foregroundStyle(OCColor.iconMuted)
                    OCLabel("Select model", icon: "cube").font(OCType.small).foregroundStyle(OCColor.textMuted)
                    Spacer(minLength: 0)
                    OCIcon("arrow-up").padding(OCSpacing.xs)
                        .background(OCColor.layer4, in: RoundedRectangle(cornerRadius: OCRadius.sm))
                }
            }
        }.allowsHitTesting(false).accessibilityElement(children: .ignore)
            .accessibilityLabel("Message composer. Ask anything, slash for commands, at for context. Sending is not available yet.")
            .disabled(true)
    }
}
#Preview("Review and dock") {
    VStack { OCWorkspacePanel(); OCDisabledPromptDock() }.padding(OCSpacing.sm).ocTheme()
}

// Sources: packages/app/src/shell/{shell,mobile-panel-drawer}.tsx,
// session/screen-layout.ts. Direct SwiftUI chrome avoids native toolbar image flattening.
#if os(iOS)
import SwiftUI

public struct OCWorkspaceShell<Sidebar: View, Tabs: View, Main: View, Panel: View>: View {
    let sidebar: Sidebar
    let tabs: Tabs
    let main: Main
    let panel: Panel
    let selectionID: String?
    let allowsPresentation: Bool
    let reviewRequest: UUID?
    let homeDismissal: UUID?
    @State private var homeOpen: Bool
    @State private var reviewOpen = false
    @State private var reviewSheet = false
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(homeInitiallyOpen: Bool = false, selectionID: String? = nil, allowsPresentation: Bool = true, reviewRequest: UUID? = nil, homeDismissal: UUID? = nil, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder tabs: () -> Tabs,
                @ViewBuilder main: () -> Main, @ViewBuilder panel: () -> Panel) {
        _homeOpen = State(initialValue: homeInitiallyOpen)
        self.selectionID = selectionID
        self.allowsPresentation = allowsPresentation
        self.reviewRequest = reviewRequest
        self.homeDismissal = homeDismissal
        self.sidebar = sidebar(); self.tabs = tabs(); self.main = main(); self.panel = panel()
    }
    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= OCLayout.workspaceWide && !typeSize.isAccessibilitySize
            let beside = geometry.size.width >= OCLayout.desktopBreakpoint && !typeSize.isAccessibilitySize
            let available = geometry.size.width - OCSpacing.sm * 3 - (homeOpen && wide ? OCLayout.sidebar + OCSpacing.sm : 0)
            let panelWidth = max(OCLayout.inspector, available - OCLayout.timelineWithReview)
            VStack(spacing: OCSpacing.sm) {
                HStack(spacing: OCSpacing.xs) {
                    OCIconButton("Toggle Home sidebar", icon: "layout-left") { homeOpen.toggle() }
                        .accessibilityIdentifier("toggleHome")
                        // What is visible: the sidebar, or Home as a sheet at narrow widths.
                        .accessibilityValue(homeOpen && (wide || allowsPresentation) ? "open" : "closed")
                    tabs
                    OCIconButton("Toggle review", icon: "sidebar-right") {
                        if beside { reviewOpen.toggle() } else { reviewSheet = true }
                    }
                        .accessibilityIdentifier("toggleReview").keyboardShortcut("r", modifiers: [.command, .shift])
                        .accessibilityValue(reviewOpen && beside || reviewSheet ? "open" : "closed")
                }
                HStack(spacing: OCSpacing.sm) {
                    if homeOpen && wide { sidebar.frame(width: OCLayout.sidebar) }
                    main.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if reviewOpen && beside {
                        panel.frame(width: panelWidth)
                    }
                }.frame(maxHeight: .infinity)
            }.padding(.horizontal, OCSpacing.sm).padding(.bottom, OCSpacing.sm)
                .background(OCColor.backgroundDeep)
                .sheet(isPresented: Binding(get: { homeOpen && !wide && allowsPresentation }, set: { homeOpen = $0 })) {
                    sidebar.ocSheet()
                }
                .onChange(of: reviewRequest) { _, request in if request != nil { if beside { reviewOpen = true } else { reviewSheet = true } } }
                // Home only reopens by itself when it is the sidebar; at narrow widths the sheet would cover
                // the New session composer that a cleared selection shows.
                .onChange(of: selectionID) { _, next in
                    if next == nil { homeOpen = wide }
                    else if !wide { homeOpen = false }
                }
                // Every navigation from Home closes the sheet, even when the selection doesn't change.
                .onChange(of: homeDismissal) { _, request in if request != nil && !wide { homeOpen = false } }
                .onChange(of: wide) { _, isWide in
                    if !isWide && selectionID != nil { homeOpen = false }
                }
                .sheet(isPresented: $reviewSheet) {
                    panel.safeAreaInset(edge: .top) { HStack { Spacer(); OCIconButton("Close review", icon: "close") { reviewSheet = false }.accessibilityIdentifier("closeReview") }.padding(.horizontal, OCSpacing.sm) }.ocSheet()
                }
        }.ocTheme()
    }
}
public struct OCProjectTab: Identifiable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}
public struct OCProjectTabs: View {
    let projects: [OCProjectTab]
    @Binding var selection: String?
    public init(projects: [OCProjectTab], selection: Binding<String?>) { self.projects = projects; _selection = selection }
    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OCSpacing.xs) {
                ForEach(projects) { project in
                    Button { selection = project.id } label: {
                        OCLabel(project.title, icon: "folder").font(OCType.button)
                            .padding(.horizontal, OCSpacing.md).frame(minHeight: OCLayout.touchTarget)
                            .background(selection == project.id || (selection == nil && project.id == projects.first?.id) ? OCColor.layer1 : .clear,
                                        in: RoundedRectangle(cornerRadius: OCRadius.md))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == project.id ? .isSelected : [])
                }
                if projects.isEmpty { OCLabel("Projects", icon: "folder").font(OCType.small).foregroundStyle(OCColor.textMuted) }
            }
        }.scrollIndicators(.hidden).frame(maxWidth: .infinity, alignment: .leading)
    }
}
#Preview("Workspace", traits: .landscapeLeft) {
    OCWorkspaceShell {
        OCForm { OCSidebarHeader("Home"); OCListRow("Design system", selected: true) }
    } tabs: {
        OCProjectTabs(projects: [.init(id: "design", title: "Design system")], selection: .constant("design"))
    } main: {
        VStack { Spacer(); OCDisabledPromptDock().padding(OCSpacing.md) }.background(OCColor.background)
    } panel: { OCWorkspacePanel() }
}
#endif

// Sources: packages/app/src/shell/{shell,mobile-panel-drawer}.tsx,
// session/screen-layout.ts. Direct SwiftUI chrome avoids native toolbar image flattening.
#if os(iOS)
import SwiftUI
import OCModels

/// A window's panel state: whether Home and the review panel are open, and their widths.
public struct OCWorkspaceLayout: Equatable, Sendable {
    /// The review's split-diff preference, which the shell reads to keep the review pane wide enough for it.
    public static let reviewSplitKey = "reviewSplit"
    public var homeOpen: Bool
    public var reviewOpen: Bool
    public var chatWidth: Double
    public var homeWidth: Double
    public init(homeOpen: Bool = true, reviewOpen: Bool = false, chatWidth: Double = WorkspaceWidths.chatDefault, homeWidth: Double = WorkspaceWidths.homeDefault) {
        self.homeOpen = homeOpen; self.reviewOpen = reviewOpen; self.chatWidth = chatWidth; self.homeWidth = homeWidth
    }
}
public struct OCWorkspaceShell<Sidebar: View, Tabs: View, Main: View, Panel: View>: View {
    let sidebar: Sidebar
    let tabs: Tabs
    let main: Main
    let panel: Panel
    let selectionID: String?
    let allowsPresentation: Bool
    let reviewRequest: UUID?
    let homeDismissal: UUID?
    let homeToggle: UUID?
    let reviewToggle: UUID?
    private let external: Binding<OCWorkspaceLayout>?
    @State private var storage: OCWorkspaceLayout
    @State private var reviewSheet = false
    @AppStorage(OCWorkspaceLayout.reviewSplitKey) private var reviewSplit = true
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A shell whose panel state belongs to its window; the toggles are requests from the menu bar.
    public init(layout: Binding<OCWorkspaceLayout>, selectionID: String? = nil, allowsPresentation: Bool = true, reviewRequest: UUID? = nil, homeDismissal: UUID? = nil,
                homeToggle: UUID? = nil, reviewToggle: UUID? = nil, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder tabs: () -> Tabs,
                @ViewBuilder main: () -> Main, @ViewBuilder panel: () -> Panel) {
        external = layout; _storage = State(initialValue: layout.wrappedValue)
        self.selectionID = selectionID; self.allowsPresentation = allowsPresentation; self.reviewRequest = reviewRequest
        self.homeDismissal = homeDismissal; self.homeToggle = homeToggle; self.reviewToggle = reviewToggle
        self.sidebar = sidebar(); self.tabs = tabs(); self.main = main(); self.panel = panel()
    }
    public init(homeInitiallyOpen: Bool = false, selectionID: String? = nil, allowsPresentation: Bool = true, reviewRequest: UUID? = nil, homeDismissal: UUID? = nil, @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder tabs: () -> Tabs,
                @ViewBuilder main: () -> Main, @ViewBuilder panel: () -> Panel) {
        external = nil; _storage = State(initialValue: OCWorkspaceLayout(homeOpen: homeInitiallyOpen))
        self.selectionID = selectionID; self.allowsPresentation = allowsPresentation; self.reviewRequest = reviewRequest
        self.homeDismissal = homeDismissal; homeToggle = nil; reviewToggle = nil
        self.sidebar = sidebar(); self.tabs = tabs(); self.main = main(); self.panel = panel()
    }
    private var layout: Binding<OCWorkspaceLayout> { external ?? $storage }
    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= OCLayout.workspaceWide && !typeSize.isAccessibilitySize
            let beside = geometry.size.width >= OCLayout.desktopBreakpoint && !typeSize.isAccessibilitySize
            let homeOpen = layout.wrappedValue.homeOpen, reviewOpen = layout.wrappedValue.reviewOpen
            // Home never squeezes the session and review panels below the review layout's breakpoint.
            let homeRange = WorkspaceWidths.homeMinimum...max(WorkspaceWidths.homeMinimum, min(WorkspaceWidths.homeMaximum, geometry.size.width - OCLayout.desktopBreakpoint))
            let homeWidth = WorkspaceWidths.clamp(layout.wrappedValue.homeWidth, homeRange)
            let available = geometry.size.width - OCSpacing.sm * 3 - (homeOpen && wide ? homeWidth + OCSpacing.sm : 0)
            // As on the desktop, split diffs ask the session panel to leave the review pane its wider minimum.
            let split = reviewOpen && beside && reviewSplit
            let chatRange = WorkspaceWidths.chatMinimum...WorkspaceWidths.chatMaximum(available: available, split: split)
            let chatWidth = WorkspaceWidths.clampChat(max(WorkspaceWidths.chatMinimum, layout.wrappedValue.chatWidth), available: available, split: split)
            VStack(spacing: OCSpacing.sm) {
                HStack(spacing: OCSpacing.xs) {
                    OCIconButton(localized("Toggle Home sidebar"), icon: "layout-left") { layout.wrappedValue.homeOpen.toggle() }
                        .accessibilityIdentifier("toggleHome")
                        // What is visible: the sidebar, or Home as a sheet at narrow widths.
                        .accessibilityValue(homeOpen && (wide || allowsPresentation) ? localized("open", comment: "Accessibility value: a panel is shown") : localized("closed", comment: "Accessibility value: a panel is hidden"))
                    tabs
                    OCIconButton(localized("Toggle review"), icon: "sidebar-right") { toggleReview(beside: beside) }
                        .accessibilityIdentifier("toggleReview")
                        .accessibilityValue(reviewOpen && beside || reviewSheet ? localized("open", comment: "Accessibility value: a panel is shown") : localized("closed", comment: "Accessibility value: a panel is hidden"))
                }
                HStack(spacing: 0) {
                    if homeOpen && wide {
                        sidebar.frame(width: homeWidth)
                        OCResizeHandle(localized("Resize Home sidebar"), value: layout.homeWidth, range: homeRange, reset: WorkspaceWidths.homeDefault, style: .gap)
                            .accessibilityIdentifier("resizeHome")
                    }
                    if reviewOpen && beside {
                        main.frame(width: chatWidth).frame(maxHeight: .infinity)
                        OCResizeHandle(localized("Resize session panel"), value: Binding(get: { chatWidth }, set: { layout.wrappedValue.chatWidth = $0 }),
                                       range: chatRange, reset: WorkspaceWidths.chatDefault, style: .gap)
                            .accessibilityIdentifier("resizeSession")
                        panel.frame(maxWidth: .infinity)
                    } else {
                        main.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.frame(maxHeight: .infinity)
            }.padding(.horizontal, OCSpacing.sm).padding(.bottom, OCSpacing.sm)
                .background(OCColor.backgroundDeep)
                .sheet(isPresented: Binding(get: { homeOpen && !wide && allowsPresentation }, set: { layout.wrappedValue.homeOpen = $0 })) {
                    sidebar.ocSheet()
                }
                .onChange(of: reviewRequest) { _, request in if request != nil { if beside { layout.wrappedValue.reviewOpen = true } else { reviewSheet = true } } }
                .onChange(of: reviewToggle) { _, request in if request != nil { toggleReview(beside: beside) } }
                .onChange(of: homeToggle) { _, request in if request != nil { layout.wrappedValue.homeOpen.toggle() } }
                // Home only reopens by itself when it is the sidebar; at narrow widths the sheet would cover
                // the New session composer that a cleared selection shows.
                .onChange(of: selectionID) { _, next in
                    if next == nil { layout.wrappedValue.homeOpen = wide }
                    else if !wide { layout.wrappedValue.homeOpen = false }
                }
                // Every navigation from Home closes the sheet, even when the selection doesn't change.
                .onChange(of: homeDismissal) { _, request in if request != nil && !wide { layout.wrappedValue.homeOpen = false } }
                .onChange(of: wide) { _, isWide in
                    if !isWide && selectionID != nil { layout.wrappedValue.homeOpen = false }
                }
                // A restored window showing a session does not open with Home's sheet over it.
                .onAppear { if !wide && selectionID != nil && homeOpen { layout.wrappedValue.homeOpen = false } }
                .sheet(isPresented: $reviewSheet) {
                    panel.safeAreaInset(edge: .top) { HStack { Spacer(); OCIconButton(localized("Close review"), icon: "close") { reviewSheet = false }.accessibilityIdentifier("closeReview") }.padding(.horizontal, OCSpacing.sm) }.ocSheet()
                }
        }.ocTheme()
    }
    private func toggleReview(beside: Bool) {
        if beside { layout.wrappedValue.reviewOpen.toggle() } else { reviewSheet.toggle() }
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
                    // A nil selection is Home's "All projects" filter, so no tab is drawn as selected.
                    Button { selection = project.id } label: { OCLabel(project.title, icon: "folder") }
                        .buttonStyle(OCTabStyle(selected: selection == project.id))
                }
                if projects.isEmpty { OCLabel(localized("Projects"), icon: "folder").font(OCType.small).foregroundStyle(OCColor.textMuted) }
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

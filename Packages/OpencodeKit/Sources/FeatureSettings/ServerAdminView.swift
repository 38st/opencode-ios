#if os(iOS)
import SwiftUI
import OCDesign
import OCModels
import OCSync

/// One server's settings. A wide screen keeps the sections in a sidebar beside the open one, as the desktop's settings
/// do; a narrow one shows the section it was opened with.
public struct ServerAdminView: View {
    let server: ServerStore
    @State private var section: ServerSettingsSection
    /// Wide enough for the sidebar beside a readable section: the iPad sheet or window, not iPhone.
    @State private var wide = false
    public init(server: ServerStore, section: ServerSettingsSection) {
        self.server = server; _section = State(initialValue: section)
    }
    private var admin: ServerAdminModel { server.readPath.admin }
    public var body: some View {
        Group {
            if wide {
                HStack(spacing: 0) {
                    sidebar.frame(width: 200)
                    Rectangle().fill(OCColor.border).frame(width: OCBorder.hairline)
                    detail.frame(maxWidth: .infinity)
                }
            } else { detail }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 500 } action: { wide = $0 }
        .background(OCColor.backgroundDeep)
        .ocNavigationTitle(wide ? server.record.name : section.title)
        .modifier(AdminFeedback(admin: admin))
        .onAppear { admin.appear() }
        .onChange(of: server.projects.map(\.id)) { _, _ in admin.appear() }
        .ocTheme()
    }
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                OCSidebarHeader("Server settings").padding(.bottom, OCSpacing.xs)
                ForEach(ServerSettingsSection.allCases) { item in
                    Button { section = item } label: {
                        OCLabel(item.title, icon: item.icon).font(OCType.body)
                            .frame(maxWidth: .infinity, minHeight: OCLayout.touchTarget, alignment: .leading)
                            .padding(.horizontal, OCSpacing.md)
                            .background(section == item ? OCColor.layer2 : .clear, in: RoundedRectangle(cornerRadius: OCRadius.md))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(section == item ? OCColor.text : OCColor.textMuted)
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                        .accessibilityIdentifier("settingsSidebar-" + item.rawValue)
                }
            }.padding(OCSpacing.md)
        }.background(OCColor.background)
    }
    @ViewBuilder private var detail: some View {
        switch section {
        case .providers: ProvidersSection(admin: admin)
        case .mcp: MCPSection(admin: admin)
        case .permissions: SavedPermissionsSection(admin: admin)
        case .agents: CatalogSection(admin: admin)
        case .configuration: ConfigurationSection(admin: admin)
        case .worktrees: WorktreesSection(admin: admin)
        case .projects: ProjectsSection(admin: admin)
        case .administration: AdministrationSection(server: server, admin: admin)
        }
    }
}

/// The server detail screen's links into its settings.
public struct ServerAdminLinks: View {
    let server: ServerStore
    public init(server: ServerStore) { self.server = server }
    public var body: some View {
        OCSection("Server settings") {
            ForEach(ServerSettingsSection.allCases) { section in
                NavigationLink { ServerAdminView(server: server, section: section) } label: {
                    HStack {
                        OCLabel(section.title, icon: section.icon).font(OCType.body)
                        Spacer()
                        OCIcon("chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
                    }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("serverSettings-" + section.rawValue)
            }
        }
    }
}
#endif

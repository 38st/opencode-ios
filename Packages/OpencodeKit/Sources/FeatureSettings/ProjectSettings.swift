#if os(iOS)
import SwiftUI
import OCDesign
import OCFoundation
import OCModels
import OCSync

// Wording: packages/app/src/settings/workspaces/project.tsx at v2.2.1.
struct ProjectsSection: View {
    @Bindable var admin: ServerAdminModel
    var body: some View {
        OCForm {
            Text(localized("Manage projects and their settings")).foregroundStyle(OCColor.textMuted)
            OCSection(localized("Projects")) {
                if admin.projects.isEmpty { Text(localized("No projects yet")).foregroundStyle(OCColor.textMuted) }
                ForEach(admin.projects) { project in
                    NavigationLink { ProjectEditView(admin: admin, project: project) } label: {
                        HStack(spacing: OCSpacing.md) {
                            OCProjectAvatar(AdminText.name(project))
                            AdminRow(title: AdminText.name(project), detail: project.canonical) {
                                OCIcon("chevron-right", size: 12).foregroundStyle(OCColor.iconMuted)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("project-" + AdminText.name(project))
                }
            }
            OCSection(localized("Archived")) {
                AdminLoadState(cell: admin.archivedProjects, empty: localized("No archived projects")) { (projects: [Project]) in
                    ForEach(projects.filter { $0.time.archived != nil }) { project in
                        AdminRow(AdminText.name(project), detail: project.canonical)
                    }
                }
                Text(localized("opencode archives a project when its folder no longer exists. It returns when you open the folder again."))
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
            }
        }
        .task { await admin.loadArchivedProjects() }
        .refreshable { admin.archivedProjects.invalidate(); await admin.loadArchivedProjects() }
    }
}

struct ProjectEditView: View {
    static let colors = ["orange", "yellow", "cyan", "green", "red", "pink", "blue", "purple", "gray"]
    @Bindable var admin: ServerAdminModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = ""
    @State private var startup = ""
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            OCSection(localized("Project name")) {
                Text(localized("The name shown for this project throughout opencode")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField(localized("Project name"), text: $name).accessibilityIdentifier("projectName")
            }
            OCSection(localized("Color")) {
                Text(project.icon?.override != nil ? localized("This project has a custom icon. Change it from the desktop app.")
                                                   : localized("Used for the project icon when no custom image is set"))
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                Picker(localized("Color"), selection: $color) {
                    Text(localized("Default", comment: "Default project color")).tag("")
                    ForEach(Self.colors, id: \.self) { Text(Self.colorName($0)).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("projectColor")
            }
            OCSection(localized("Worktree startup script")) {
                Text(localized("Runs once after creating a new worktree. Use $OPENCODE_WORKTREE_BASE for the base worktree and $OPENCODE_WORKTREE_PATH for the new one."))
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField(localized("e.g. bun install", comment: "Placeholder; bun install is a shell command"), text: $startup, axis: .vertical).font(OCType.code)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("projectStartup")
            }
            Text(project.canonical).font(OCType.code).foregroundStyle(OCColor.textMuted).textSelection(.enabled)
            Button(localized("Save")) { save() }.buttonStyle(OCButtonStyle(.contrast))
                .disabled(!changed || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || admin.isBusy("project:" + project.id))
                .accessibilityIdentifier("saveProject")
        }
        .ocNavigationTitle(localized("Edit project"))
        .onAppear {
            name = AdminText.name(project); color = project.icon?.color ?? ""
            startup = project.commands?["start"]?.stringValue ?? ""
        }
        .onDisappear { task?.cancel() }
    }
    static func colorName(_ color: String) -> String {
        switch color {
        case "orange": localized("Orange")
        case "yellow": localized("Yellow")
        case "cyan": localized("Cyan")
        case "green": localized("Green")
        case "red": localized("Red")
        case "pink": localized("Pink")
        case "blue": localized("Blue")
        case "purple": localized("Purple")
        case "gray": localized("Gray")
        default: color.capitalized
        }
    }
    private var changed: Bool {
        name != AdminText.name(project) || color != (project.icon?.color ?? "") || startup != (project.commands?["start"]?.stringValue ?? "")
    }
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task {
            let saved = await admin.updateProject(project, name: trimmed == AdminText.name(project) ? nil : trimmed,
                                                  color: color == (project.icon?.color ?? "") ? nil : color, iconOverride: nil,
                                                  startCommand: startup == (project.commands?["start"]?.stringValue ?? "") ? nil : startup)
            if saved { admin.notice = localized("Project saved"); dismiss() }
        }
    }
}

/// Configuration documents, lowest precedence first, with secret-looking values hidden; and the terminal shell.
struct ConfigurationSection: View {
    @Bindable var admin: ServerAdminModel
    @State private var shellChange: String??
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text(localized("The configuration this project's location reads, read-only. Values whose names look secret are hidden.")).foregroundStyle(OCColor.textMuted)
                AdminProjectPicker(admin: admin)
            }
            OCSection(localized("Terminal shell")) {
                Text(localized("Shell used by the terminal and agent tools")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                AdminLoadState(cell: admin.shells, empty: localized("No shells found")) { (shells: [ShellOption]) in
                    Menu {
                        Button(localized("Auto (Default)", comment: "Terminal shell choice")) { shellChange = .some(nil) }
                        ForEach(shells.filter { $0.raw["acceptable"]?.boolValue != false }) { shell in
                            Button(shell.name + "  " + shell.path) { shellChange = .some(shell.path) }
                        }
                    } label: {
                        HStack {
                            Text(admin.configuredShell ?? localized("Auto (Default)", comment: "Terminal shell choice")).font(OCType.body)
                            OCIcon("chevron-down", size: 12)
                        }.frame(minHeight: OCLayout.touchTarget)
                    }.disabled(admin.isBusy("shell")).accessibilityIdentifier("shellPicker")
                }
            }
            AdminLoadState(cell: admin.config, empty: localized("No configuration documents")) { (entries: [ConfigEntry]) in
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    OCSection(Self.title(entry, index: index, count: entries.count)) {
                        if entry.type == "directory" {
                            Text(localized("Searched for agents, commands and skills")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                            Text(entry.path ?? "").font(OCType.code).textSelection(.enabled)
                        } else {
                            if let path = entry.path { Text(path).font(OCType.code).foregroundStyle(OCColor.textMuted).textSelection(.enabled) }
                            CodeBlockView(Self.document(entry), language: "json").accessibilityIdentifier("configDocument")
                        }
                    }
                }
            }
        }
        .task(id: admin.directory) { await admin.loadConfig() }
        .refreshable { admin.config.invalidate(); admin.shells.invalidate(); await admin.loadConfig() }
        .confirmationDialog(localized("Change the terminal shell?"), isPresented: Binding(get: { shellChange != nil }, set: { if !$0 { shellChange = nil } }),
                            titleVisibility: .visible) {
            Button(localized("Change shell")) {
                guard let change = shellChange else { return }
                shellChange = nil
                task = Task { _ = await admin.setShell(change) }
            }.accessibilityIdentifier("confirmShell")
        } message: {
            Text(shellMessage)
        }
        .onDisappear { task?.cancel() }
    }
    private var shellMessage: String {
        if let shell = shellChange ?? nil {
            return localized("This sets shell to \(shell) in the server's global configuration, for every project. New terminals and agent commands use it.", comment: "%@ is a shell path")
        }
        return localized("This sets shell to the server's default in the server's global configuration, for every project. New terminals and agent commands use it.")
    }
    static func title(_ entry: ConfigEntry, index: Int, count: Int) -> String {
        let name = entry.type == "directory" ? localized("Directory") : (entry.path.map(AdminText.shortPath) ?? localized("Inline configuration"))
        guard count > 1 else { return name }
        if index == 0 { return localized("\(name) (lowest precedence)", comment: "%@ is a configuration file name") }
        if index == count - 1 { return localized("\(name) (highest precedence)", comment: "%@ is a configuration file name") }
        return name
    }
    static func document(_ entry: ConfigEntry) -> String {
        (try? ConfigRedaction.redact(entry.info ?? .object([:])).prettyPrinted()) ?? "{}"
    }
}
#endif

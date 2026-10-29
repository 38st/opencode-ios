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
            Text("Manage projects and their settings").foregroundStyle(OCColor.textMuted)
            OCSection("Projects") {
                if admin.projects.isEmpty { Text("No projects yet").foregroundStyle(OCColor.textMuted) }
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
            OCSection("Archived") {
                AdminLoadState(cell: admin.archivedProjects, empty: "No archived projects") { (projects: [Project]) in
                    ForEach(projects.filter { $0.time.archived != nil }) { project in
                        AdminRow(AdminText.name(project), detail: project.canonical)
                    }
                }
                Text("opencode archives a project when its folder no longer exists. It returns when you open the folder again.")
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
            OCSection("Project name") {
                Text("The name shown for this project throughout opencode").font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField("Project name", text: $name).accessibilityIdentifier("projectName")
            }
            OCSection("Color") {
                Text(project.icon?.override != nil ? "This project has a custom icon. Change it from the desktop app."
                                                   : "Used for the project icon when no custom image is set")
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                Picker("Color", selection: $color) {
                    Text("Default").tag("")
                    ForEach(Self.colors, id: \.self) { Text($0.capitalized).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("projectColor")
            }
            OCSection("Worktree startup script") {
                Text("Runs once after creating a new worktree. Use $OPENCODE_WORKTREE_BASE for the base worktree and $OPENCODE_WORKTREE_PATH for the new one.")
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField("e.g. bun install", text: $startup, axis: .vertical).font(OCType.code)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("projectStartup")
            }
            Text(project.canonical).font(OCType.code).foregroundStyle(OCColor.textMuted).textSelection(.enabled)
            Button("Save") { save() }.buttonStyle(OCButtonStyle(.contrast))
                .disabled(!changed || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || admin.isBusy("project:" + project.id))
                .accessibilityIdentifier("saveProject")
        }
        .ocNavigationTitle("Edit project")
        .onAppear {
            name = AdminText.name(project); color = project.icon?.color ?? ""
            startup = project.commands?["start"]?.stringValue ?? ""
        }
        .onDisappear { task?.cancel() }
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
            if saved { admin.notice = "Project saved"; dismiss() }
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
                Text("The configuration this project's location reads, read-only. Values whose names look secret are hidden.").foregroundStyle(OCColor.textMuted)
                AdminProjectPicker(admin: admin)
            }
            OCSection("Terminal shell") {
                Text("Shell used by the terminal and agent tools").font(OCType.small).foregroundStyle(OCColor.textMuted)
                AdminLoadState(cell: admin.shells, empty: "No shells found") { (shells: [ShellOption]) in
                    Menu {
                        Button("Auto (Default)") { shellChange = .some(nil) }
                        ForEach(shells.filter { $0.raw["acceptable"]?.boolValue != false }) { shell in
                            Button(shell.name + "  " + shell.path) { shellChange = .some(shell.path) }
                        }
                    } label: {
                        HStack {
                            Text(admin.configuredShell ?? "Auto (Default)").font(OCType.body)
                            OCIcon("chevron-down", size: 12)
                        }.frame(minHeight: OCLayout.touchTarget)
                    }.disabled(admin.isBusy("shell")).accessibilityIdentifier("shellPicker")
                }
            }
            AdminLoadState(cell: admin.config, empty: "No configuration documents") { (entries: [ConfigEntry]) in
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    OCSection(Self.title(entry, index: index, count: entries.count)) {
                        if entry.type == "directory" {
                            Text("Searched for agents, commands and skills").font(OCType.small).foregroundStyle(OCColor.textMuted)
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
        .confirmationDialog("Change the terminal shell?", isPresented: Binding(get: { shellChange != nil }, set: { if !$0 { shellChange = nil } }),
                            titleVisibility: .visible) {
            Button("Change shell") {
                guard let change = shellChange else { return }
                shellChange = nil
                task = Task { _ = await admin.setShell(change) }
            }.accessibilityIdentifier("confirmShell")
        } message: {
            Text("This sets shell to \((shellChange ?? nil) ?? "the server's default") in the server's global configuration, for every project. New terminals and agent commands use it.")
        }
        .onDisappear { task?.cancel() }
    }
    static func title(_ entry: ConfigEntry, index: Int, count: Int) -> String {
        let order = count > 1 ? (index == 0 ? " (lowest precedence)" : index == count - 1 ? " (highest precedence)" : "") : ""
        if entry.type == "directory" { return "Directory" + order }
        return (entry.path.map(AdminText.shortPath) ?? "Inline configuration") + order
    }
    static func document(_ entry: ConfigEntry) -> String {
        (try? ConfigRedaction.redact(entry.info ?? .object([:])).prettyPrinted()) ?? "{}"
    }
}
#endif

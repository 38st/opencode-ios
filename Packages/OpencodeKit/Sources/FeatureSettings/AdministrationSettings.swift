#if os(iOS)
import SwiftUI
import OCDesign
import OCFoundation
import OCModels
import OCSync

/// Server identity, available updates, booted locations and reloading every location.
struct AdministrationSection: View {
    let server: ServerStore
    @Bindable var admin: ServerAdminModel
    @State private var evicting: Location?
    @State private var reloading = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            OCSection("Server") {
                LabeledContent("Version", value: server.version ?? "Checking…").accessibilityIdentifier("adminVersion")
                LabeledContent("Persistent terminals", value: server.capabilities.persistentPty ? "Available" : "Unavailable")
            }.font(OCType.body)
            if let update = admin.availableUpdate {
                OCSection("Update available") {
                    OCLabel("opencode \(update) is available.", icon: "arrow-up").font(OCType.body)
                    Text("Run opencode upgrade on the computer running the server, then reconnect.").font(OCType.small).foregroundStyle(OCColor.textMuted)
                }.accessibilityIdentifier("updateAvailable")
            }
            OCSection("Loaded locations") {
                Text("Directories whose services the server has started. Evicting one stops them until it is used again.")
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                AdminLoadState(cell: admin.locations, empty: "No locations loaded") { (locations: [Location]) in
                    ForEach(locations, id: \.directory) { location in
                        AdminRow(title: AdminText.shortPath(location.directory), detail: location.directory) {
                            Button("Evict") { evicting = location }.buttonStyle(OCButtonStyle(.ghost))
                                .disabled(admin.isBusy("evict:" + location.directory))
                                .accessibilityIdentifier("evict-" + AdminText.shortPath(location.directory))
                        }
                    }
                }
            }
            OCSection("Configuration") {
                AdminRow(title: "Reload configuration", detail: "Restarts every loaded location so changes to opencode.json, agents, skills and plugins apply.") {
                    Button("Reload") { reloading = true }.buttonStyle(OCButtonStyle()).disabled(admin.isBusy("reload"))
                        .accessibilityIdentifier("reloadLocations")
                }
            }
        }
        .task { await admin.loadLocations() }
        .refreshable { admin.locations.invalidate(); await admin.loadLocations() }
        .confirmationDialog("Evict \(evicting.map { AdminText.shortPath($0.directory) } ?? "")?", isPresented: Binding(get: { evicting != nil }, set: { if !$0 { evicting = nil } }),
                            titleVisibility: .visible) {
            Button("Evict", role: .destructive) {
                guard let location = evicting else { return }
                evicting = nil
                task = Task { await admin.evict(location) }
            }.accessibilityIdentifier("confirmEvict")
        } message: {
            Text("The server stops this location's services. Pending permission requests and questions there are cancelled; running sessions continue at their next step.")
        }
        .confirmationDialog("Reload every location?", isPresented: $reloading, titleVisibility: .visible) {
            Button("Reload", role: .destructive) { task = Task { await admin.reloadLocations() } }.accessibilityIdentifier("confirmReload")
        } message: {
            Text("Pending permission requests and questions on this server are cancelled; running sessions continue at their next step.")
        }
        .onDisappear { task?.cancel() }
    }
}

/// A project's worktrees: create, refresh, and delete after checking for uncommitted changes.
struct WorktreesSection: View {
    @Bindable var admin: ServerAdminModel
    @State private var newName = ""
    @State private var removing: WorktreeInfo?
    @State private var task: Task<Void, Never>?
    var body: some View {
        OCForm {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                Text("Review worktrees and manage disk usage").foregroundStyle(OCColor.textMuted)
                AdminProjectPicker(admin: admin)
            }
            if let project = admin.project {
                OCSection("Worktrees") {
                    AdminLoadState(cell: admin.worktrees(for: project.id), empty: "No worktrees yet",
                                   emptyDetail: "Worktrees created in opencode will appear here.") { (worktrees: [WorktreeInfo]) in
                        // The list includes the project's own checkout, which cannot be deleted here.
                        ForEach(worktrees.filter { $0.directory == project.canonical }) { main in
                            AdminRow(title: "Main checkout", detail: main.directory) { OCBadge("Project") }
                        }
                        ForEach(worktrees.filter { $0.directory != project.canonical }) { worktree in
                            AdminRow(title: worktree.name, detail: worktree.directory) {
                                Button { removing = worktree } label: { OCIcon("outline-trash").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
                                    .buttonStyle(.plain).foregroundStyle(OCColor.danger).disabled(admin.isBusy("worktree:" + worktree.directory))
                                    .accessibilityLabel("Delete worktree \(worktree.name)").accessibilityIdentifier("deleteWorktree-" + worktree.name)
                            }
                        }
                    }
                    Button { task = Task { await admin.refreshWorktrees(projectID: project.id) } } label: { OCLabel("Refresh", icon: "refresh") }
                        .buttonStyle(OCButtonStyle(.ghost)).disabled(admin.isBusy("worktree:refresh"))
                }
                OCSection("New worktree") {
                    TextField("Name (optional)", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("worktreeName")
                    Button { create(project) } label: { OCLabel("Create worktree", icon: "plus") }.buttonStyle(OCButtonStyle(.contrast))
                        .disabled(admin.isBusy("worktree:create")).accessibilityIdentifier("createWorktree")
                    if project.commands?["start"]?.stringValue?.isEmpty == false {
                        Text("The project's startup script runs in the new worktree.").font(OCType.small).foregroundStyle(OCColor.textMuted)
                    }
                }
                .task(id: project.id) { await admin.loadWorktrees(projectID: project.id) }
            } else {
                Text("No projects yet").foregroundStyle(OCColor.textMuted)
            }
        }
        .refreshable {
            guard let project = admin.project else { return }
            admin.worktrees(for: project.id).invalidate(); await admin.loadWorktrees(projectID: project.id)
        }
        .sheet(item: $removing) { worktree in
            if let project = admin.project { WorktreeRemovalSheet(admin: admin, worktree: worktree, projectID: project.id).ocSheet() }
        }
        .onDisappear { task?.cancel() }
    }
    private func create(_ project: Project) {
        let name = newName
        task = Task {
            if let created = await admin.createWorktree(projectID: project.id, name: name) {
                newName = ""; admin.notice = "Created " + created.name
            }
        }
    }
}

/// Lists what a deletion would lose. Force is offered only after the changes are shown and confirmed again.
struct WorktreeRemovalSheet: View {
    /// `unknown` carries the server's refusal when it found changes the status read did not list.
    enum Check: Equatable { case checking, clean, dirty([FileDiff]), unknown(String?) }
    @Bindable var admin: ServerAdminModel
    let worktree: WorktreeInfo
    let projectID: String
    @Environment(\.dismiss) private var dismiss
    @State private var check: Check = .checking
    @State private var confirmingForce = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            OCForm {
                Text(worktree.directory).font(OCType.code).foregroundStyle(OCColor.textMuted).textSelection(.enabled)
                Text("This permanently deletes the worktree and its branch.")
                switch check {
                case .checking:
                    HStack(spacing: OCSpacing.sm) { ProgressView(); Text("Checking for unmerged changes…").foregroundStyle(OCColor.textMuted) }
                case .clean:
                    Text("No uncommitted changes.").foregroundStyle(OCColor.textMuted).accessibilityIdentifier("worktreeClean")
                    Button("Delete worktree", role: .destructive) { remove(force: false) }.buttonStyle(OCButtonStyle(.danger))
                        .accessibilityIdentifier("confirmDeleteWorktree")
                case .dirty(let files):
                    OCLabel("Unmerged changes will be lost.", icon: "warning").foregroundStyle(OCColor.warning)
                        .accessibilityIdentifier("worktreeDirty")
                    OCSection("Uncommitted changes (\(files.count))") {
                        ForEach(files, id: \.file) { file in
                            AdminRow(title: file.file, mono: true) {
                                Text("+\(file.additions) −\(file.deletions)").font(OCType.small).foregroundStyle(OCColor.textMuted)
                            }
                        }
                    }
                    Button("Delete with uncommitted changes", role: .destructive) { confirmingForce = true }
                        .buttonStyle(OCButtonStyle(.danger)).accessibilityIdentifier("forceDeleteWorktree")
                case .unknown(let message):
                    Text(message ?? "Unable to verify git status. Uncommitted changes may be lost.").foregroundStyle(OCColor.warning)
                        .accessibilityIdentifier("worktreeUnknown")
                    Button("Delete anyway", role: .destructive) { confirmingForce = true }.buttonStyle(OCButtonStyle(.danger))
                        .accessibilityIdentifier("forceDeleteWorktree")
                }
            }
            .ocNavigationTitle("Delete “\(worktree.name)”?")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("cancelDeleteWorktree") } }
            .confirmationDialog(forceTitle, isPresented: $confirmingForce, titleVisibility: .visible) {
                Button("Delete worktree and changes", role: .destructive) { remove(force: true) }.accessibilityIdentifier("confirmForceDeleteWorktree")
            } message: { Text("The uncommitted changes cannot be recovered.") }
        }
        .task { await inspect() }
        .onDisappear { task?.cancel() }
    }
    private var forceTitle: String {
        if case .dirty(let files) = check { return "Delete \(files.count) uncommitted \(files.count == 1 ? "change" : "changes")?" }
        return "Delete without checking for changes?"
    }
    private func inspect() async {
        check = .checking
        guard let files = await admin.uncommittedChanges(in: worktree) else { check = .unknown(nil); return }
        check = files.isEmpty ? .clean : .dirty(files)
    }
    private func remove(force: Bool) {
        task = Task {
            switch await admin.removeWorktree(worktree, projectID: projectID, force: force) {
            case .removed: admin.notice = "Deleted " + worktree.name; dismiss()
            // A freshly started location can answer an empty status first; the server's refusal is authoritative.
            case .forceRequired(let message):
                await inspect()
                if check == .clean || check == .unknown(nil) { check = .unknown(message) }
            case .failed: break
            }
        }
    }
}
#endif

#if os(iOS)
import Foundation
import SwiftUI
import OCFoundation
import OCModels
import OCSync
import OCDesign

public struct NewSessionView: View {
    let server: ServerStore
    let opened: (String) -> Void
    let initialDirectory: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var directory = ""
    @State private var projectID = ""
    @State private var worktree = ""
    @State private var worktrees: [WorktreeInfo] = []
    @State private var branch: String?
    @State private var browser = false
    @State private var browserDestination: Destination?
    @State private var choosingBranch = false
    @State private var creatingWorktree = false
    @State private var error: String?
    @State private var choicesError: String?
    @State private var selectionTask: Task<Void, Never>?
    @State private var changingSelection = false
    @State private var pendingSelection: Destination?
    @State private var draftConflict = false
    private struct Destination { let directory: String; let projectID: String; let worktree: String }
    public init(server: ServerStore, directory: String? = nil, opened: @escaping (String) -> Void) { self.server = server; self.initialDirectory = directory; self.opened = opened }
    private var project: Project? { server.projects.first { $0.id == projectID } }
    private var draftDirectory: String { worktree.isEmpty || worktree == "new" ? directory : worktree }
    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: OCSpacing.xxl) {
                    Text("New session").font(OCType.title)
                    if !draftDirectory.isEmpty {
                        ComposerDock(store: server.readPath, model: server.readPath.composer(directory: draftDirectory), start: start, opened: opened)
                            .id(draftDirectory)
                    } else { ProgressView("Loading projects…") }
                    if creatingWorktree { ProgressView("Creating worktree").font(OCType.small) }
                    ViewThatFits(in: .horizontal) {
                        HStack { projectSelector; worktreeSelector }
                        VStack { projectSelector; worktreeSelector }
                    }
                    if let error = error ?? choicesError { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
                }.padding(.horizontal, OCSpacing.lg).padding(.bottom, OCSpacing.lg)
                    .padding(.top, typeSize.isAccessibilitySize || geometry.size.height < OCComposerMetrics.compactHeight
                        ? OCSpacing.lg : geometry.size.height * OCComposerMetrics.newSessionTopFraction)
                    .frame(maxWidth: OCComposerMetrics.newSessionWidth).frame(maxWidth: .infinity)
            }
        }.background(OCColor.background).accessibilityIdentifier("newSessionView")
            .task {
                guard directory.isEmpty else { return }
                do {
                    if let initialDirectory {
                        let location = try await server.readPath.resolveDirectory(initialDirectory)
                        directory = location.directory; projectID = location.project?.id ?? ""
                        error = "Failed to create session. Your prompt has been restored."
                    } else if let project = server.projects.first { directory = project.canonical; projectID = project.id }
                    else {
                        let location = try await server.readPath.resolveDirectory("")
                        directory = location.directory; projectID = location.project?.id ?? ""
                    }
                } catch { if !Task.isCancelled { self.error = "Could not open a project." } }
            }
            .task(id: draftDirectory) {
                guard !draftDirectory.isEmpty else { return }
                choicesError = nil
                do {
                    try await server.readPath.refreshCatalogs(draftDirectory)
                    if !projectID.isEmpty { worktrees = try await server.readPath.worktrees(projectID: projectID) }
                } catch { if !Task.isCancelled { choicesError = "Could not load project choices." } }
            }
            .sheet(isPresented: $browser, onDismiss: {
                if let destination = browserDestination { browserDestination = nil; select(destination) }
            }) {
                DirectoryBrowser(store: server.readPath, directory: directory) { location in
                    browserDestination = .init(directory: location.directory, projectID: location.project?.id ?? "", worktree: "")
                    browser = false
                }.ocSheet()
            }
            .sheet(isPresented: $choosingBranch) {
                BranchPicker(store: server.readPath, directory: directory) { branch = $0; choosingBranch = false }.ocSheet()
            }
            .alert("Which draft would you like to keep?", isPresented: $draftConflict) {
                Button("Keep current draft") { if let pendingSelection { select(pendingSelection, keeping: .current) } }
                Button("Use saved draft") { if let pendingSelection { select(pendingSelection, keeping: .saved) } }
                Button("Cancel", role: .cancel) { pendingSelection = nil }
            } message: { Text("This project already has a draft. Keeping your current draft replaces it. Using the saved draft keeps your current draft in its original project.") }
            .onDisappear { selectionTask?.cancel() }
    }
    private var projectSelector: some View {
        Menu {
            ForEach(server.projects) { value in
                Button(value.name ?? URL(fileURLWithPath: value.canonical).lastPathComponent) {
                    select(.init(directory: value.canonical, projectID: value.id, worktree: ""))
                }
            }
            Divider()
            Button("Open project…") { browser = true }
        } label: { OCLabel(project?.name ?? URL(fileURLWithPath: directory).lastPathComponent, icon: "folder").font(OCType.small).frame(minHeight: OCLayout.touchTarget) }
            .accessibilityLabel("Project").accessibilityIdentifier("newSessionProject").disabled(selectionDisabled)
    }
    private var worktreeSelector: some View {
        HStack {
            Menu {
                Button("Local repository") { selectWorktree("") }
                Button("New worktree") { selectWorktree("new") }.disabled(project?.vcs == nil)
                ForEach(worktrees) { value in Button(value.branch ?? URL(fileURLWithPath: value.directory).lastPathComponent) { selectWorktree(value.directory) } }
            } label: {
                OCLabel(worktree == "new" ? "New worktree" : worktree.isEmpty ? "Local repository" : URL(fileURLWithPath: worktree).lastPathComponent, icon: "branch")
                    .font(OCType.small).frame(minHeight: OCLayout.touchTarget)
            }.accessibilityLabel("Worktree").accessibilityIdentifier("newSessionWorktree").disabled(selectionDisabled)
            if project?.vcs == nil { OCBadge("No Git") }
            else if worktree == "new" {
                Button("from \(branch ?? currentBranch ?? "default")") { choosingBranch = true }.buttonStyle(OCButtonStyle(.ghost))
            }
        }
    }
    private var selectionDisabled: Bool {
        changingSelection || creatingWorktree || (!draftDirectory.isEmpty && server.readPath.composer(directory: draftDirectory).busy)
    }
    private func selectWorktree(_ value: String) { select(.init(directory: directory, projectID: projectID, worktree: value)) }
    private func select(_ destination: Destination, keeping choice: DirectoryDraftChoice? = nil) {
        guard !changingSelection else { return }
        changingSelection = true; error = nil
        selectionTask = Task {
            defer { changingSelection = false }
            do {
                let next = destination.worktree.isEmpty || destination.worktree == "new" ? destination.directory : destination.worktree
                try await server.readPath.moveDirectoryDraft(from: draftDirectory, to: next, keeping: choice)
                if directory != destination.directory { branch = nil }
                directory = destination.directory; projectID = destination.projectID; worktree = destination.worktree
                pendingSelection = nil
            } catch ComposerError.directoryDraftConflict {
                pendingSelection = destination; draftConflict = true
            } catch {
                if !WriteErrorMessage.isCancellation(error) { self.error = WriteErrorMessage.message(error) }
            }
        }
    }
    private var currentBranch: String? { server.readPath.catalog(for: .init(directory: directory)).vcs.value?["branch"]?["current"]?.stringValue }
    private func start(agent: String, model: ModelRef?) async throws -> String {
        var destination = draftDirectory
        if worktree == "new" {
            creatingWorktree = true
            defer { creatingWorktree = false }
            do { destination = try await server.readPath.createWorktree(projectID: projectID, from: project?.canonical ?? directory, branch: branch).directory }
            catch {
                self.error = "Failed to create worktree" + ((error as? WorktreeFailure)?.forceRequired == true ? ". The server requires resolving the worktree conflict first." : ". " + WriteErrorMessage.message(error))
                throw error
            }
        }
        let location = try await server.readPath.resolveDirectory(destination)
        return try await server.readPath.createSession(location: location, agent: agent, model: model, projectID: location.project?.id ?? projectID)
    }
}

private struct DirectoryBrowser: View {
    let store: ReadStore
    let directory: String
    let selected: (Location) -> Void
    @State private var path = ""
    @State private var entries: [FileEntry] = []
    @State private var error: String?
    @State private var resolving: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                TextField("Absolute directory path", text: $path).font(OCType.code).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Parent directory") { path = URL(fileURLWithPath: path).deletingLastPathComponent().path }
                ForEach(entries.filter { $0.type == .directory }) { entry in
                    let resolved = URL(fileURLWithPath: ComposerInput.absolute(entry.path, directory: directory)).standardizedFileURL
                    Button(resolved.lastPathComponent) { path = resolved.path }
                }
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
            }.accessibilityIdentifier("directoryBrowser").font(OCType.body).navigationTitle("Open project…")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Open") {
                        resolving?.cancel(); resolving = Task {
                            do { selected(try await store.resolveDirectory(path)) } catch { self.error = "Could not open directory." }
                        }
                    }.disabled(!path.hasPrefix("/")) }
                }
        }.ocTheme().onAppear { path = directory }
            .task(id: path) {
                guard path.hasPrefix("/") else { return }
                do { entries = try await store.listDirectory(path, directory: directory); error = nil }
                catch is CancellationError {} catch { self.error = "Could not list directory." }
            }.onDisappear { resolving?.cancel() }
    }
}
private struct BranchPicker: View {
    let store: ReadStore
    let directory: String
    let selected: (String) -> Void
    @State private var search = ""
    @State private var branches: [String] = []
    var body: some View {
        NavigationStack {
            List(branches, id: \.self) { branch in Button(branch) { selected(branch) }.font(OCType.body) }
                .navigationTitle("From branch").searchable(text: $search, prompt: "Search branches")
        }.ocTheme().task(id: search) {
            do { branches = try await store.branches(search, directory: directory) } catch { branches = [] }
        }
    }
}
#endif

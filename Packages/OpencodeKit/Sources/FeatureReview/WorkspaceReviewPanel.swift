#if os(iOS)
import SwiftUI
import OCSync
import OCModels
import OCFoundation
import OCDesign
import FeatureFiles

/// Feature composition stays above OCDesign, preserving the architecture's dependency direction.
public struct WorkspaceReviewPanel: View {
    let server: ServerStore
    let sessionID: String
    let openSession: (String) -> Void
    public init(server: ServerStore, sessionID: String, openSession: @escaping (String) -> Void = { _ in }) {
        self.server = server; self.sessionID = sessionID; self.openSession = openSession
    }
    public var body: some View {
        if let session = server.sessions[sessionID] {
            let directory = session.info.location.directory
            PanelContent(server: server, sessionID: sessionID, model: server.readPath.review(sessionID: sessionID, directory: directory),
                         files: server.readPath.files(sessionID: sessionID, directory: directory),
                         composer: server.readPath.composer(sessionID: sessionID, directory: directory), openSession: openSession).id(sessionID)
        } else { OCWorkspacePanel() }
    }
}
private struct PanelContent: View {
    let server: ServerStore
    let sessionID: String
    let model: ReviewModel
    let files: FilesModel
    let composer: ComposerModel
    let openSession: (String) -> Void
    private var store: ReadStore { server.readPath }
    var body: some View {
        OCWorkspacePanel(selection: Binding(get: { model.tab }, set: { model.selectTab($0) }), title: model.files.isEmpty ? "Review" : "Files Changed \(model.files.count)") { tab in
            switch tab {
            case "Changes": ReviewScreen(model: model, composer: composer) { path, line in
                files.open(path, selection: line.map { .init(start: $0) }); model.selectTab("Files")
            }
            case "Files": FilesScreen(model: files, composer: composer, changes: model.files.compactMap { file in
                guard let path = model.path(file.file), path.directory == files.directory else { return nil }
                var file = file; file.raw.set("file", .string(path.path)); return file
            })
                .onAppear { model.appear() }.onDisappear { model.disappear() }
            case "Context": ContextPanel(store: store, sessionID: sessionID, openSession: openSession) { model.selectTab("Changes") }
            default: OCEmptyState("\(tab) will appear here", detail: "Review tools are not available yet.", icon: "terminal") { EmptyView() }
            }
        }.task { await composer.load() }
            .environment(\.ocFileLinks, OCFileLinks(open: { link in store.performWrite { await files.openLink(link) } completion: { _ in }; model.selectTab("Files") }, existing: { await files.existingLinks($0) }, known: { files.knownLinks($0) }, comment: { composer.addComment($0) }, comments: { path in composer.comments.filter { $0.file == ComposerInput.absolute(path, directory: model.directory) } }, updateComment: { composer.updateComment($0) }, removeComment: { composer.removeComment($0) }))
    }
}
#endif

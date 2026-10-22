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
    public init(server: ServerStore, sessionID: String) { self.server = server; self.sessionID = sessionID }
    public var body: some View {
        if let session = server.sessions[sessionID] {
            let directory = session.info.location.directory
            PanelContent(store: server.readPath, model: server.readPath.review(sessionID: sessionID, directory: directory),
                         files: server.readPath.files(sessionID: sessionID, directory: directory),
                         composer: server.readPath.composer(sessionID: sessionID, directory: directory)).id(sessionID)
        } else { OCWorkspacePanel() }
    }
}
private struct PanelContent: View {
    let store: ReadStore
    let model: ReviewModel
    let files: FilesModel
    let composer: ComposerModel
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
            default: OCEmptyState("\(tab) will appear here", detail: "Review tools are not available yet.", icon: tab == "Terminal" ? "terminal" : "brain") { EmptyView() }
            }
        }.task { await composer.load() }
            .environment(\.ocFileLinks, OCFileLinks(open: { link in store.performWrite { await files.openLink(link) } completion: { _ in }; model.selectTab("Files") }, existing: { await files.existingLinks($0) }, known: { files.knownLinks($0) }, comment: { composer.addComment($0) }, comments: { path in composer.comments.filter { $0.file == ComposerInput.absolute(path, directory: model.directory) } }, updateComment: { composer.updateComment($0) }, removeComment: { composer.removeComment($0) }))
    }
}
#endif

#if os(iOS)
import Foundation
import SwiftUI
import OCFoundation
import OCModels
import OCPushCore
import OCDesign
import OCSync
import FeatureFiles

public enum PermissionSheetState: String, CaseIterable { case review, reject, authenticating, sending, failed, settled }

/// Shared sheet content is also used by snapshots without invoking authentication.
public struct PermissionContent: View {
    let request: PermissionRequest
    let directory: String
    let otherRequests: Int
    @Binding var state: PermissionSheetState
    @Binding var note: String
    @Environment(\.dynamicTypeSize) private var typeSize
    let reply: (PermissionDecision, String?) -> Void
    public init(request: PermissionRequest, directory: String, otherRequests: Int = 0,
                state: Binding<PermissionSheetState>, note: Binding<String>, reply: @escaping (PermissionDecision, String?) -> Void) {
        self.request = request; self.directory = directory; self.otherRequests = otherRequests
        _state = state; _note = note; self.reply = reply
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.lg) {
            let headingLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.sm)) : AnyLayout(HStackLayout(alignment: .top, spacing: OCSpacing.sm))
            headingLayout {
                OCLabel("Permission required", icon: "warning").font(OCType.heading)
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                OCBadge(PermissionRisk.assess(request).rawValue.capitalized + " risk", tone: PermissionRisk.assess(request) == .high ? .danger : .warning)
            }
            copyable("Action", values: [request.action])
            if let message = request.message { Text(message).font(OCType.body) }
            copyable("Resources", values: request.resources)
            copyable("Working directory", values: [directory])
            ForEach(Array((request.metadata?["files"]?.lossy(FileDiff.self).values ?? []).enumerated()), id: \.offset) { _, file in
                DiffCardView(file: file.file, patch: file.patch, additions: file.additions, deletions: file.deletions, expanded: true)
            }
            if !request.save.isEmpty {
                copyable("Allow always saves these patterns in this project", values: request.save)
            }
            if state == .reject {
                Text("Rejecting also rejects this session’s \(otherRequests) other pending requests. Without a note, it ends the turn.")
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField("Tell the agent what to do instead (optional)", text: $note, axis: .vertical)
                    .textFieldStyle(OCTextFieldStyle()).accessibilityIdentifier("permissionNote")
                Button("Reject") { reply(.reject, note) }.buttonStyle(OCButtonStyle(.danger)).accessibilityIdentifier("confirmReject")
                Button("Back") { state = .review }.buttonStyle(OCButtonStyle(.ghost))
            } else if state == .settled {
                OCBadge("Already handled", tone: .success)
            } else if state == .authenticating || state == .sending {
                OCLabel(state == .authenticating ? "Confirm with Face ID or passcode…" : "Sending reply…", icon: "status").font(OCType.small)
            } else {
                if state == .failed { Text("Reply could not be sent. Try again.").font(OCType.small).foregroundStyle(OCColor.danger) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OCSpacing.sm) { actions }
                    VStack(alignment: .leading, spacing: OCSpacing.sm) { actions }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textFieldStyle(OCTextFieldStyle())
    }
    @ViewBuilder private var actions: some View {
        Button("Reject") { state = .reject }.buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("rejectPermission")
        Button("Allow always") { reply(.always, nil) }.buttonStyle(OCButtonStyle(.neutral)).accessibilityIdentifier("allowAlways")
        Button("Allow once") { reply(.once, nil) }.buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("allowOnce")
    }
    private func copyable(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack {
                Text(title).font(OCType.small).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                OCIconButton("Copy " + title.lowercased(), icon: "copy") { OCCopy.text(values.joined(separator: "\n")) }
            }
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value).font(OCType.code).fixedSize(horizontal: false, vertical: true).ocSelectableText(value)
            }
        }
    }
    private func bounded(_ value: Double) -> Int { value.isFinite && value >= 0 && value < Double(Int.max) ? Int(value) : 0 }
}

public struct PermissionSheet: View {
    let store: ReadStore
    let request: PermissionRequest
    let directory: String
    @State private var state = PermissionSheetState.review
    @State private var note = ""
    @State private var showingFile = false
    @Environment(\.dismiss) private var dismiss
    public init(store: ReadStore, request: PermissionRequest, directory: String) {
        self.store = store; self.request = request; self.directory = directory
    }
    public var body: some View {
        let composer = store.composer(sessionID: request.sessionID, directory: directory)
        let files = store.files(sessionID: request.sessionID, directory: directory)
        NavigationStack {
            OCForm {
                PermissionContent(request: request, directory: directory, otherRequests: max(0, (store.permissions[request.sessionID]?.count ?? 1) - 1),
                                  state: $state, note: $note, reply: send)
            }.ocNavigationTitle("Permission required")
                .toolbar { ToolbarItem(placement: .cancellationAction) { OCIconButton("Close", icon: "close") { dismiss() } } }
        }
            .task { await composer.load() }
            .environment(\.ocFileLinks, OCFileLinks(open: { link in
                store.performWrite { await files.openLink(link) } completion: { _ in }; showingFile = true
            }, existing: { await files.existingLinks($0) }, known: { files.knownLinks($0) }, comment: { value in
                var value = value; value.file = ComposerInput.absolute(value.file, directory: directory); composer.addComment(value)
            }, comments: { file in composer.comments.filter { $0.file == ComposerInput.absolute(file, directory: directory) } },
            updateComment: { composer.updateComment($0) }, removeComment: { composer.removeComment($0) }))
            .sheet(isPresented: $showingFile) { FilesScreen(model: files, composer: composer).ocSheet() }
            .onChange(of: store.permissions[request.sessionID]?.map(\.id)) { _, ids in
                if !(ids ?? []).contains(request.id) { state = .settled }
            }
    }
    private func send(_ decision: PermissionDecision, _ note: String?) {
        store.respondToPermission(request, decision: decision, message: note)
        dismiss()
    }
}
#endif

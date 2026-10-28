#if os(iOS)
import SwiftUI
import OCModels
import OCDesign
import OCSync

public struct ApprovalDock: View {
    let store: ReadStore
    let sessionID: String
    public init(store: ReadStore, sessionID: String) { self.store = store; self.sessionID = sessionID }
    public var body: some View {
        let requests = store.familyPermissions(sessionID)
        let forms = store.familyForms(sessionID)
        if !requests.isEmpty || !forms.isEmpty {
            // Keep a bounded dock; every request remains reachable at accessibility sizes.
            ScrollView {
                VStack(alignment: .leading, spacing: OCSpacing.md) {
                    ForEach(requests) { request in
                        PermissionCard(store: store, request: request, directory: store.sessions[request.sessionID]?.info.location.directory ?? "", child: request.sessionID != sessionID)
                    }
                    ForEach(forms) { form in QuestionCard(store: store, form: form, child: form.sessionID != sessionID) }
                }
            }.frame(maxHeight: OCLayout.approvalDockHeight)
                .accessibilityIdentifier("approvalDock")
        }
    }
}

public struct PermissionCard: View {
    let store: ReadStore
    let request: PermissionRequest
    let directory: String
    let child: Bool
    @State private var show = false
    public init(store: ReadStore, request: PermissionRequest, directory: String, child: Bool = false) {
        self.store = store; self.request = request; self.directory = directory; self.child = child
    }
    public var body: some View {
        OCPromptDock {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                HStack {
                    OCLabel("Permission required", icon: "warning").font(OCType.button)
                    if child { OCBadge("Subagent") }
                }
                Text(request.action.capitalized).font(OCType.small).foregroundStyle(OCColor.textMuted)
                ForEach(Array(request.resources.enumerated()), id: \.offset) { _, resource in
                    Text(resource).font(OCType.code).fixedSize(horizontal: false, vertical: true)
                }
                if let error = store.approvalErrors[request.id] {
                    Text(error).font(OCType.small).foregroundStyle(OCColor.danger).fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OCSpacing.sm) { actions }
                    VStack(alignment: .leading, spacing: OCSpacing.sm) { actions }
                }
            }
        }.sheet(isPresented: $show) { PermissionSheet(store: store, request: request, directory: directory).ocSheet() }
            // Review next approval (⇧⌘A) opens this request's full review once its card appears.
            .onChange(of: store.reviewRequest, initial: true) { _, id in if id == request.id { store.reviewRequest = nil; show = true } }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("permission-" + request.id)
    }
    @ViewBuilder private var actions: some View {
        Button("Review") { show = true }.buttonStyle(OCButtonStyle(.neutral)).accessibilityIdentifier("reviewPermission")
        Button("Allow once") { store.respondToPermission(request, decision: .once) }
            .buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("dockAllowOnce")
    }
}
public struct QuestionCard: View {
    let store: ReadStore
    let form: FormInfo
    let child: Bool
    @State private var show = false
    public init(store: ReadStore, form: FormInfo, child: Bool = false) { self.store = store; self.form = form; self.child = child }
    public var body: some View {
        OCPromptDock {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                OCLabel("Question", icon: "bubble-5").font(OCType.button)
                if child { OCBadge("Subagent") }
                Text(form.title).font(OCType.body)
                if let error = store.approvalErrors[form.id] {
                    Text(error).font(OCType.small).foregroundStyle(OCColor.danger).fixedSize(horizontal: false, vertical: true)
                }
                Button("Answer question") { show = true }.buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("answerQuestion")
            }
        }.sheet(isPresented: $show) { QuestionSheet(store: store, form: form).ocSheet() }
            .onChange(of: store.reviewRequest, initial: true) { _, id in if id == form.id { store.reviewRequest = nil; show = true } }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("question-" + form.id)
    }
}
#endif

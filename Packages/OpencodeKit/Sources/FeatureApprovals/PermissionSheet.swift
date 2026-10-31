#if os(iOS)
import Foundation
import SwiftUI
import OCFoundation
import OCModels
import OCPushCore
import OCSecurity
import OCDesign
import OCSync
import FeatureFiles

/// Replies are sent optimistically once any authentication passes, so there is no sending state.
public enum PermissionSheetState: String, CaseIterable { case review, reject, authenticating, failed, settled }

/// Shared sheet content is also used by snapshots without invoking authentication.
public struct PermissionContent: View {
    let request: PermissionRequest
    let directory: String
    let otherRequests: Int
    let authentication: DeviceAuthenticationMethod
    let failure: String?
    @Binding var state: PermissionSheetState
    @Binding var note: String
    @Environment(\.dynamicTypeSize) private var typeSize
    let reply: (PermissionDecision, String?) -> Void
    public init(request: PermissionRequest, directory: String, otherRequests: Int = 0, authentication: DeviceAuthenticationMethod = .faceID,
                failure: String? = nil, state: Binding<PermissionSheetState>, note: Binding<String>, reply: @escaping (PermissionDecision, String?) -> Void) {
        self.request = request; self.directory = directory; self.otherRequests = otherRequests
        self.authentication = authentication; self.failure = failure
        _state = state; _note = note; self.reply = reply
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.lg) {
            let headingLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: OCSpacing.sm)) : AnyLayout(HStackLayout(alignment: .top, spacing: OCSpacing.sm))
            headingLayout {
                OCLabel(localized("Permission required"), icon: "warning").font(OCType.heading)
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                OCBadge(Self.riskLabel(PermissionRisk.assess(request)), tone: PermissionRisk.assess(request) == .high ? .danger : .warning)
            }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            copyable(localized("Action", comment: "Label for the requested permission action"), copyLabel: localized("Copy action"), values: [request.action])
            if let message = request.message { Text(message).font(OCType.body) }
            copyable(localized("Resources"), copyLabel: localized("Copy resources"), values: request.resources)
            copyable(localized("Working directory"), copyLabel: localized("Copy working directory"), values: [directory])
            ForEach(Array((request.metadata?["files"]?.lossy(FileDiff.self).values ?? []).enumerated()), id: \.offset) { _, file in
                DiffCardView(file: file.file, patch: file.patch, additions: file.additions, deletions: file.deletions, expanded: true)
            }
            if !request.save.isEmpty {
                copyable(localized("Allow always saves these patterns in this project"), copyLabel: localized("Copy allow always saves these patterns in this project"), values: request.save)
            }
            if state == .reject {
                Group {
                    if otherRequests > 0 { Text(localized("Rejecting also rejects \(otherRequests) other pending requests in this session.", comment: "%lld is the number of other pending permission requests")) }
                    Text(localized("Without a note, rejecting ends the turn."))
                }.font(OCType.small).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true)
                TextField(localized("Tell the agent what to do instead (optional)"), text: $note, axis: .vertical)
                    .textFieldStyle(OCTextFieldStyle()).accessibilityIdentifier("permissionNote")
                Button(localized("Reject")) { reply(.reject, note) }.buttonStyle(OCButtonStyle(.danger)).accessibilityIdentifier("confirmReject")
                Button(localized("Back")) { state = .review }.buttonStyle(OCButtonStyle(.ghost))
            } else if state == .settled {
                OCBadge(localized("Already handled"), tone: .success)
            } else if state == .authenticating {
                OCLabel(authentication.prompt, icon: "status").font(OCType.small)
            } else {
                if state == .failed {
                    Text(failure ?? localized("Reply could not be sent. Try again.")).font(OCType.small).foregroundStyle(OCColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if authentication == .unavailable {
                    Text(PermissionRisk.assess(request) == .high
                         ? localized("Allow always and Allow once on high-risk requests need a device passcode. Set one in Settings.")
                         : localized("Allow always needs a device passcode. Set one in Settings."))
                        .font(OCType.small).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OCSpacing.sm) { actions }
                    VStack(alignment: .leading, spacing: OCSpacing.sm) { actions }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textFieldStyle(OCTextFieldStyle())
    }
    @ViewBuilder private var actions: some View {
        Button(localized("Reject")) { state = .reject }.buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("rejectPermission")
        Button(localized("Allow always")) { reply(.always, nil) }.buttonStyle(OCButtonStyle(.neutral)).accessibilityIdentifier("allowAlways")
            .disabled(authentication == .unavailable)
        Button(localized("Allow once")) { reply(.once, nil) }.buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("allowOnce")
            .disabled(authentication == .unavailable && PermissionRisk.assess(request) == .high)
    }
    /// What VoiceOver says when the sheet opens: the risk tier, the action and every option the person has.
    public static func announcement(_ request: PermissionRequest, authentication: DeviceAuthenticationMethod) -> String {
        let risk = PermissionRisk.assess(request)
        var options = [localized("Reject")]
        if authentication != .unavailable { options.append(localized("Allow always")) }
        if authentication != .unavailable || risk != .high { options.append(localized("Allow once")) }
        return localized("Permission required. \(riskLabel(risk)). \(request.action). Options: \(options.formatted(.list(type: .or))).",
                         comment: "VoiceOver announcement; the first %@ is the risk tier, the second the action, the third the list of choices")
    }
    static func riskLabel(_ risk: PermissionRisk) -> String {
        switch risk {
        case .low: localized("Low risk")
        case .elevated: localized("Elevated risk")
        case .high: localized("High risk")
        }
    }
    private func copyable(_ title: String, copyLabel: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack {
                Text(title).font(OCType.small).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                OCIconButton(copyLabel, icon: "copy") { OCCopy.text(values.joined(separator: "\n")) }
            }
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value).font(OCType.code).fixedSize(horizontal: false, vertical: true).ocSelectableText(value)
                    .frame(maxWidth: .infinity, alignment: .leading).environment(\.layoutDirection, .leftToRight)
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
    @State private var authentication = DeviceAuthenticationMethod.faceID
    @State private var failure: String?
    @State private var replied = false
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
                                  authentication: authentication, failure: failure, state: $state, note: $note, reply: send)
            }.ocNavigationTitle(localized("Permission required"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { OCIconButton(localized("Close", comment: "Closes the sheet"), icon: "close") { dismiss() } } }
        }
            .interactiveDismissDisabled(state == .authenticating)
            .task { await composer.load() }
            .task {
                authentication = await store.biometricGate.method()
                OCAnnouncer.post(PermissionContent.announcement(request, authentication: authentication))
                // A reply that failed after an earlier dismissal reopens in its failed state.
                if let error = store.approvalErrors[request.id], state == .review { failure = error; state = .failed }
            }
            .environment(\.ocFileLinks, OCFileLinks(open: { link in
                store.performWrite { await files.openLink(link) } completion: { _ in }; showingFile = true
            }, existing: { await files.existingLinks($0) }, known: { files.knownLinks($0) }, comment: { value in
                var value = value; value.file = ComposerInput.absolute(value.file, directory: directory); composer.addComment(value)
            }, comments: { file in composer.comments.filter { $0.file == ComposerInput.absolute(file, directory: directory) } },
            updateComment: { composer.updateComment($0) }, removeComment: { composer.removeComment($0) }))
            .sheet(isPresented: $showingFile) { FilesScreen(model: files, composer: composer).ocSheet() }
            .onChange(of: store.permissions[request.sessionID]?.map(\.id)) { _, ids in
                guard !(ids ?? []).contains(request.id) else { return }
                // Our own reply removes the request too; only another client's answer is news.
                if !replied && state != .settled { OCAnnouncer.post(localized("Already handled")) }
                state = .settled
            }
    }
    private func send(_ decision: PermissionDecision, _ note: String?) {
        guard store.permissionNeedsAuthentication(request, decision: decision) else {
            replied = true
            store.respondToPermission(request, decision: decision, message: note); dismiss(); return
        }
        // Stay open while the device confirms the owner; only a confirmed reply dismisses.
        state = .authenticating
        store.authenticatePermission(request, decision: decision) { result in
            switch result {
            case .success:
                replied = true
                store.respondToPermission(request, decision: decision, message: note, authenticated: true); dismiss()
            case .failure(let error):
                guard state == .authenticating else { return }
                if let message = error.message { failure = message; state = .failed } else { state = .review }
            }
        }
    }
}
#endif

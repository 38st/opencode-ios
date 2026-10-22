#if os(iOS)
import SwiftUI
import OCModels
import OCSync
import OCRender
import OCDesign
import FeatureApprovals
import FeatureComposer

public struct TimelineRowView: View {
    let row: TimelineRow
    let transcript: TranscriptModel
    let store: ReadStore?
    let sessionID: String
    let directory: String
    let detail: TimelineDetail
    let openChild: (String) -> Void
    let openRoot: (String) -> Void
    public init(row: TimelineRow, transcript: TranscriptModel, store: ReadStore? = nil, sessionID: String = "", directory: String = "",
                detail: TimelineDetail = .compact, openChild: @escaping (String) -> Void = { _ in }, openRoot: @escaping (String) -> Void = { _ in }) {
        self.row = row; self.transcript = transcript; self.store = store; self.directory = directory; self.detail = detail; self.openChild = openChild; self.openRoot = openRoot
        self.sessionID = sessionID
    }
    @AppStorage("changedFiles") private var changedFiles = true
    @State private var acting = false
    @State private var actionError: String?
    public var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-" + row.kind.rawValue + "-" + row.id)
            .alert("Could not complete action", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: { Text(actionError ?? "") }
            .disabled(acting)
    }
    @ViewBuilder private var content: some View {
        switch row.kind {
        case .userPrompt:
            let commented = hasComments
            HStack {
                Spacer(minLength: OCSpacing.xl)
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    if let badge = row.badge { OCBadge(badge) }
                    if let saved = store?.savedPrompts.first(where: { $0.id == row.id }) {
                        OCBadge(saved.state == "pending" ? "Sending" : saved.state == "failed" ? "Edit and resend" : "Waiting for confirmation", tone: saved.state == "failed" ? .danger : .neutral)
                    }
                    if let fields = transcript.messages[row.id]?.fields {
                        SentPrompt(fields, references: store?.sessions[sessionID].flatMap { store?.catalogs[$0.info.location.key]?.references.value },
                                   pending: store?.sessions[sessionID]?.pendingStatus(row.id) != nil)
                    }
                    else { Text(row.text).font(OCType.body).foregroundStyle(OCColor.accent).ocSelectableText(row.text) }
                    if let store, let status = store.sessions[sessionID]?.pendingStatus(row.id), status == .steering || status == .stranded {
                        HStack {
                            OCBadge("Pending")
                            Button("Move to queue") { run { try await store.changeDelivery(sessionID, itemID: row.id, delivery: .queue) } }.buttonStyle(OCButtonStyle(.ghost))
                            Button("Delete") { run { try await store.cancelPending(sessionID, itemID: row.id, restore: false) } }.buttonStyle(OCButtonStyle(.ghost))
                        }
                    }
                }.padding(commented ? 0 : OCSpacing.md)
                    .background(commented ? .clear : OCColor.infoBackground, in: RoundedRectangle(cornerRadius: OCRadius.lg))
            }.padding(.vertical, OCSpacing.sm)
                .contextMenu {
                    Button("Copy") { OCCopy.text(row.text) }
                    if let store {
                        Button("Revert message") { run { try await store.undo(sessionID, messageID: row.id) } }
                        Button("Fork from here") { run { let next = try await store.forkFromMessage(sessionID, messageID: row.id); openRoot(next.id) } }
                    }
                }
        case .toolGroup:
            OCToolChrome(row.text, icon: "glasses", expanded: detail == .everything) {
                ForEach(row.children) { child in
                    AnyView(TimelineRowView(row: child, transcript: transcript, store: store, sessionID: sessionID, directory: directory, detail: detail, openChild: openChild, openRoot: openRoot))
                }
            }
        case .assistantText, .reasoning, .tool, .subagent:
            if let item = item {
                ContentRow(item: item, reasoning: row.kind == .reasoning, messageCompleted: messageCompleted, store: store, sessionID: sessionID, directory: directory, detail: detail, openChild: openChild)
            }
        case .shell:
            if let item = item {
                ContentRow(item: item, reasoning: false, messageCompleted: messageCompleted, store: store, sessionID: sessionID, directory: directory, detail: detail, openChild: openChild)
            } else if let message = transcript.messages[row.id] {
                StandaloneShell(message: message, store: store, directory: directory, expanded: detail.expanded)
            }
        case .turnEnd:
            if changedFiles, !row.files.isEmpty, let store, let from = row.turnFrom {
                // The desktop's per-turn card replaces the turn label; a turn that did not succeed keeps its badge.
                VStack(alignment: .leading, spacing: OCSpacing.xs) {
                    TurnChangesCard(row: row, model: store.turnDiff(sessionID: sessionID, from: from)) { file in
                        store.review(sessionID: sessionID, directory: directory).choose(.turn(from), file: file, present: true)
                    }
                    outcome
                }
            } else {
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Rectangle().fill(OCColor.borderMuted).frame(height: OCBorder.hairline)
                    HStack {
                        OCLabel(row.text, icon: row.files.isEmpty ? "check" : "edit").font(OCType.small)
                        outcome
                    }.foregroundStyle(OCColor.textMuted)
                    if changedFiles && !row.files.isEmpty {
                        OCToolChrome("View changed files", icon: "code") {
                            ForEach(row.files, id: \.self) { Text($0).font(OCType.code).ocSelectableText($0) }
                        }
                    }
                }.padding(.vertical, OCSpacing.md)
            }
        case .error, .retry, .pendingInput, .compaction:
            if row.kind == .pendingInput, let store, let request = store.permissions.values.joined().first(where: { $0.id == row.id }) {
                PermissionCard(store: store, request: request, directory: directory)
            } else if row.kind == .pendingInput, let store, let form = store.forms.values.joined().first(where: { $0.id == row.id }) {
                QuestionCard(store: store, form: form)
            } else {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                HStack {
                    OCLabel(label, icon: row.kind == .error ? "warning" : row.kind == .retry ? "refresh" : "status").font(OCType.button)
                    if let badge = row.badge { OCBadge(badge) }
                }
                Text(row.text).font(OCType.small).ocSelectableText(row.text)
            }.padding(OCSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
                .background(row.kind == .error ? OCColor.dangerBackground : OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
            }
        case .notice:
            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                Text(row.text).font(OCType.small).foregroundStyle(OCColor.textMuted).ocSelectableText(row.text)
                if let child = row.childID { Button("Open agent") { openChild(child) }.buttonStyle(OCButtonStyle(.ghost)) }
            }.padding(.vertical, OCSpacing.xs)
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !acting, let store else { return }
        acting = true
        store.performWrite(operation) { result in
            acting = false
            if case .failure(let failure) = result { actionError = WriteErrorMessage.message(failure) }
        }
    }
    @ViewBuilder private var outcome: some View {
        if let badge = row.badge, badge != "succeeded" { OCBadge(badge.capitalized, tone: badge == "failed" ? .danger : .neutral) }
    }
    private var hasComments: Bool {
        transcript.messages[row.id].map { !LineComment.restore($0.fields.raw).isEmpty } ?? false
    }
    private var label: String {
        switch row.kind { case .error: "Run failed"; case .retry: "Retrying"; case .pendingInput: "Needs you"; default: "Compaction" }
    }
    private var item: ContentItemModel? {
        guard let ref = row.reference, let message = transcript.messages[ref.messageID], message.items.indices.contains(ref.index) else { return nil }
        return message.items[ref.index]
    }
    private var messageCompleted: Bool {
        row.reference.flatMap { transcript.messages[$0.messageID] }?.fields.time.completed != nil
    }
}

private struct ContentRow: View {
    let item: ContentItemModel
    let reasoning: Bool
    let messageCompleted: Bool
    let store: ReadStore?
    let sessionID: String
    let directory: String
    let detail: TimelineDetail
    let openChild: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            if item.joinedMidStream { OCBadge("Catching up", tone: .info) }
            if item.fields.type == "tool" {
                ToolRowView(presentation: ToolPresenterRegistry().presentation(item.fields), store: store, directory: directory,
                            expanded: detail.expanded, openChild: openChild)
                if let store, let request = store.permissionForTool(item.fields.id, sessionID: sessionID) {
                    PermissionCard(store: store, request: request, directory: directory)
                }
            } else if reasoning {
                OCToolChrome("Thinking", icon: "brain", expanded: detail == .everything) {
                    StreamingMarkdownView(item.text, complete: messageCompleted || item.fields.time.completed != nil).foregroundStyle(OCColor.textMuted).ocSelectableText(item.text)
                }
            } else {
                StreamingMarkdownView(item.text, complete: messageCompleted || item.fields.time.completed != nil).ocSelectableText(item.text)
                    .accessibilityIdentifier("assistantText")
            }
        }
    }
}
private struct StandaloneShell: View {
    let message: MessageModel
    let store: ReadStore?
    let directory: String
    let expanded: Bool
    private var presentation: ToolPresentation {
        let f = message.fields
        var value = ToolPresentation(title: "Shell", status: f.status ?? "running")
        value.style = .shell; value.icon = "terminal"; value.subtitle = f.command ?? ""
        value.input = f.command ?? ""; value.output = f.output?.output ?? ""; value.shellID = f.shellID
        if let exit = f.exit, exit >= Double(Int.min), exit < Double(Int.max) { value.badge = "Exit \(Int(exit))"; value.failed = exit != 0 }
        return value
    }
    var body: some View { ToolRowView(presentation: presentation, store: store, directory: directory, expanded: expanded) }
}
#endif

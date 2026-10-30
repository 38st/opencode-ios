#if os(iOS)
import Foundation
import SwiftUI
import OCModels
import OCFoundation
import OCSync
import OCDesign
import OCRender

public struct SessionActions: View {
    let store: ReadStore
    let session: SessionModel
    let opened: (String) -> Void
    let deleted: () -> Void
    @Binding var command: ComposerCommand?
    @State private var rename = false
    @State private var title = ""
    @State private var deleting = false
    @State private var forking = false
    @State private var moving = false
    @State private var exporting = false
    @State private var error: String?
    @Environment(\.ocPushController) private var notifications
    @State private var task: Task<Void, Never>?
    public init(store: ReadStore, session: SessionModel, command: Binding<ComposerCommand?>, opened: @escaping (String) -> Void, deleted: @escaping () -> Void) {
        self.store = store; self.session = session; _command = command; self.opened = opened; self.deleted = deleted
    }
    public var body: some View {
        Menu {
            SessionMenuOptions(canRedo: session.info.revert != nil, canMove: session.info.parentID == nil,
                               muted: notifications?.isMuted(server: store.serverID, sessionID: session.id)) { action in
                switch action {
                case .rename: title = session.info.title ?? ""; rename = true
                case .fork: forking = true
                case .compact: perform(.compact)
                case .undo: perform(.undo)
                case .redo: perform(.redo)
                case .move: moving = true
                case .export: exporting = true
                case .mute:
                    if let notifications {
                        notifications.setMuted(!notifications.isMuted(server: store.serverID, sessionID: session.id), server: store.serverID, sessionID: session.id)
                    }
                case .delete: deleting = true
                }
            }
        } label: { OCIcon("dot-grid").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
            .accessibilityLabel("Session actions").accessibilityIdentifier("sessionActions")
            .alert("Rename session", isPresented: $rename) {
                TextField("Session title", text: $title)
                Button("Cancel", role: .cancel) {}
                Button("Save") { run { try await store.renameSession(session.id, title: title) } }
            } message: { Text("Leave the title empty to generate a new one.") }
            .sheet(isPresented: $deleting) {
                OCConfirmationSheet("Delete session", message: "Delete session \"\(session.info.title ?? "Untitled session")\"?" + (store.family(session.id).count > 1 ? " Its subagent sessions will be deleted too." : ""),
                                    confirmTitle: "Delete session", cancel: { deleting = false }, confirm: {
                    store.deleteSession(session.id) { result in
                        switch result {
                        case .success: deleting = false; deleted()
                        case .failure(let failure): if !WriteErrorMessage.isCancellation(failure) { error = WriteErrorMessage.message(failure) }
                        }
                    }
                }).ocSheet()
            }
            .sheet(isPresented: $forking) { forkSheet.ocSheet() }
            .sheet(isPresented: $moving) { MoveSessionSheet(store: store, session: session) { moving = false }.ocSheet() }
            .sheet(isPresented: $exporting) {
                OCExportSheet(prepare: { try await store.exportFile(session.id, format: $0, sanitize: $1) }) { exporting = false }.ocSheet()
            }
            .alert("Could not complete action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onChange(of: command) { _, next in if let next { command = nil; perform(next) } }
            .onDisappear { task?.cancel() }
    }
    private var forkMessages: [SessionMessage] {
        guard let transcript = session.transcript else { return [] }
        return transcript.visibleOrder(revert: session.info.revert?.messageID, pending: session.pending)
            .compactMap { transcript.messages[$0]?.fields }.filter { $0.type == "user" }.map { SessionMessage(raw: $0.raw) }
    }
    private var forkSheet: some View {
        NavigationStack {
            List {
                ForEach(forkMessages.reversed(), id: \.id) { message in
                    Button {
                        run { let next = try await store.forkFromMessage(session.id, messageID: message.id); forking = false; opened(next.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: OCSpacing.xs) {
                            Text(message.fields.text).font(OCType.body).lineLimit(3)
                            Text(Date(timeIntervalSince1970: message.time.created / 1_000).formatted(date: .abbreviated, time: .shortened))
                                .font(OCType.micro).foregroundStyle(OCColor.textMuted)
                        }.frame(minHeight: OCLayout.touchTarget)
                    }.buttonStyle(.plain).listRowBackground(OCColor.background)
                }
            }.scrollContentBackground(.hidden).background(OCColor.background).navigationTitle("Fork from message")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { forking = false } } }
        }.ocTheme()
    }
    private func perform(_ command: ComposerCommand) {
        switch command {
        case .fork: forking = true
        case .undo: run { try await store.undo(session.id) }
        case .redo: run { try await store.redo(session.id) }
        case .compact: run { _ = try await store.compact(session.id) }
        default: break
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        task = Task { defer { task = nil }; do { try await operation() } catch { if !WriteErrorMessage.isCancellation(error) { self.error = WriteErrorMessage.message(error) } } }
    }
}

public struct SentPrompt: View {
    @State private var showAllComments = false
    let input: MessageFields
    let references: JSONValue?
    let pending: Bool
    /// Decoded once per input; the body and the attachment filter both read it.
    private let comments: [LineComment]
    public init(_ input: MessageFields, references: JSONValue? = nil, pending: Bool = false) {
        self.input = input; self.references = references; self.pending = pending; comments = LineComment.restore(input.raw)
    }
    private var styledText: AttributedString {
        var value = ComposerInput.restoreText(input.raw, references: references)
        for run in value.runs {
            let kind = run[MentionAttribute.self]?.kind
            value[run.range].foregroundColor = pending ? OCColor.text : OCColor.accent
            if let kind, ["file", "reference", "agent"].contains(kind) {
                value[run.range].font = OCType.body.weight(.semibold)
                if value[run.range].characters.first == "@" {
                    let end = value.characters.index(after: run.range.lowerBound)
                    value[run.range.lowerBound..<end].foregroundColor = pending ? OCColor.text : OCMentionStyle.sentPrefix
                }
            }
        }
        return value
    }
    public var body: some View {
        let styledText = styledText
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            if !styledText.characters.isEmpty {
                OCPromptText(styledText).ocSelectableText(input.text)
                    .padding(comments.isEmpty ? 0 : OCSpacing.md)
                    .background(comments.isEmpty ? .clear : OCColor.infoBackground, in: RoundedRectangle(cornerRadius: OCRadius.lg))
            }
            ForEach(Array((showAllComments || styledText.characters.isEmpty ? comments : Array(comments.prefix(5))).enumerated()), id: \.offset) { _, comment in
                HStack { Spacer(minLength: 0); OCCommentCard(comment) }
            }
            if !showAllComments && !styledText.characters.isEmpty && comments.count > 5 { Button("Show more") { showAllComments = true }.buttonStyle(OCButtonStyle(.ghost)) }
            if let files = input["files"]?.arrayValue {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    if file["mention"] == nil && !isCommentFile(file) {
                        if let image = TranscriptImage(name: file["name"]?.stringValue, mime: file["mime"]?.stringValue ?? "", uri: file["uri"]?.stringValue, base64: attachmentBase64(file)) {
                            OCTranscriptImage(image)
                        } else {
                            OCAttachmentChip(name: file["name"]?.stringValue ?? "Attachment", mime: file["mime"]?.stringValue ?? "text/plain",
                                             base64: attachmentBase64(file))
                        }
                    }
                }
            }
        }
    }
    private func isCommentFile(_ file: JSONValue) -> Bool {
        let uri = file["uri"]?.stringValue ?? file["source"]?["uri"]?.stringValue ?? ""
        guard uri.hasPrefix("file://"), file["mention"] == nil else { return false }
        let path = FileLink(uri).path
        return comments.contains { comment in
            let expected = comment.file.replacingOccurrences(of: "\\", with: "/")
            return path == expected || path.hasSuffix("/" + expected) || LineComment.mentions(comment.comment).contains { path == $0 || path.hasSuffix("/" + $0) }
        }
    }
    private func attachmentBase64(_ file: JSONValue) -> String? {
        if let data = file["data"]?.stringValue { return data }
        guard let uri = file["uri"]?.stringValue, uri.hasPrefix("data:"), let encoded = uri.split(separator: ",", maxSplits: 1).last else { return nil }
        return String(encoded)
    }
}
#endif

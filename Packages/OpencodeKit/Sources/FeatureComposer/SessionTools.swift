#if os(iOS)
import Foundation
import SwiftUI
import OCModels
import OCFoundation
import OCRender
import OCSync
import OCDesign

public extension EnvironmentValues {
    /// The device's notification settings, for the session menu's mute action; nil where push is unavailable.
    @Entry var ocPushController: PushController?
}

/// Moves a session to another worktree or the project checkout (`POST /api/session/{id}/move`).
struct MoveSessionSheet: View {
    let store: ReadStore
    let session: SessionModel
    let close: () -> Void
    @State private var targets: [MoveTarget]?
    @State private var queued = false
    private var delivery: Delivery { queued ? .queue : .steer }
    @State private var confirming: MoveTarget?
    @State private var error: String?
    @State private var moving = false
    private var running: Bool { session.status.isRunning }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Current: " + session.info.location.directory).font(OCType.small).foregroundStyle(OCColor.textMuted)
                        .textSelection(.enabled).listRowBackground(OCColor.background)
                    if running {
                        OCSegmentedControl("When", options: [(false, "Next step"), (true, "After queued prompts")], selection: $queued)
                            .listRowBackground(OCColor.background).accessibilityIdentifier("moveDelivery")
                    }
                }
                Section("Move to") {
                    if let targets {
                        ForEach(targets) { target in
                            Button { choose(target) } label: {
                                HStack(spacing: OCSpacing.sm) {
                                    OCIcon(target.kind == .newWorktree ? "plus" : target.kind == .checkout ? "folder" : "outline-worktree")
                                    VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                                        Text(target.title).font(OCType.body)
                                        if target.kind != .newWorktree {
                                            Text((target.branch.map { $0 + " · " } ?? "") + target.directory).font(OCType.micro).foregroundStyle(OCColor.textMuted)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(moving).listRowBackground(OCColor.background)
                                .accessibilityIdentifier("moveTarget-" + (target.kind == .newWorktree ? "new" : (target.directory as NSString).lastPathComponent))
                        }
                    } else if error == nil {
                        ProgressView().frame(maxWidth: .infinity).listRowBackground(OCColor.background)
                    }
                    if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).listRowBackground(OCColor.background).ocAnnounce(error, initial: true) }
                }
            }.scrollContentBackground(.hidden).background(OCColor.background).navigationTitle("Move session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) } }
                .overlay { if moving { ProgressView("Moving session…").padding(OCSpacing.lg).background(OCColor.layer2, in: RoundedRectangle(cornerRadius: OCRadius.lg)) } }
        }.ocTheme()
            .task {
                do { targets = try await store.moveTargets(session.id) }
                catch { self.error = "Failed to load worktrees. " + WriteErrorMessage.message(error) }
            }
            .sheet(item: $confirming) { target in
                OCConfirmationSheet("Move a running session?", message: Self.confirmation(target, delivery: delivery),
                                    detail: nil, confirmTitle: "Move session", destructive: false, cancel: { confirming = nil }) {
                    confirming = nil; move(target)
                }.ocSheet()
            }
    }
    static func confirmation(_ target: MoveTarget, delivery: Delivery) -> String {
        let place = target.kind == .newWorktree ? "a new worktree" : "“" + target.directory + "”"
        let when = delivery == .queue ? "after the prompts already queued" : "at its next step"
        return "The session keeps working here and moves to \(place) \(when). Its next steps read and change files there, not in the current directory."
    }
    private func choose(_ target: MoveTarget) {
        if running { confirming = target } else { move(target) }
    }
    private func move(_ target: MoveTarget) {
        moving = true; error = nil
        store.performWrite { try await store.moveSession(session.id, to: target, delivery: running ? delivery : .steer) } completion: { result in
            moving = false
            switch result {
            case .success: close()
            case .failure(let failure): if !WriteErrorMessage.isCancellation(failure) { error = "Failed to move session. " + WriteErrorMessage.message(failure) }
            }
        }
    }
}

/// The session's move while it waits for a delivery boundary, and its outcome.
public struct PendingMoveBanner: View {
    let store: ReadStore
    let sessionID: String
    public init(store: ReadStore, sessionID: String) { self.store = store; self.sessionID = sessionID }
    public var body: some View {
        if let state = store.moveState(sessionID) {
            HStack(spacing: OCSpacing.sm) {
                switch state {
                case .pending(let directory, let delivery):
                    ProgressView().controlSize(.small)
                    Text("Moving session to " + name(directory) + (delivery == .queue ? " after queued prompts…" : "…")).font(OCType.small)
                case .applied(let directory):
                    OCIcon("check-small").foregroundStyle(OCColor.success)
                    Text("Moved to " + name(directory)).font(OCType.small)
                case .failed(_, let message):
                    OCIcon("warning").foregroundStyle(OCColor.danger)
                    Text("Failed to move session. " + message).font(OCType.small).foregroundStyle(OCColor.danger)
                }
                Spacer(minLength: 0)
                if case .pending = state {} else { OCIconButton("Dismiss", icon: "close-small") { store.dismissMove(sessionID) } }
            }.padding(.horizontal, OCSpacing.md).frame(minHeight: OCLayout.touchTarget)
                .background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md))
                .accessibilityElement(children: .combine).accessibilityIdentifier("pendingMove")
        }
    }
    private func name(_ directory: String) -> String { directory.isEmpty ? "a new worktree" : (directory as NSString).lastPathComponent }
}

/// The `/btw` answer: a card above the composer, dismissed by the user; never part of the transcript.
public struct SideQuestionCard: View {
    let store: ReadStore
    let sessionID: String
    public init(store: ReadStore, sessionID: String) { self.store = store; self.sessionID = sessionID }
    public var body: some View {
        if let side = store.sideQuestions[sessionID] {
            VStack(alignment: .leading, spacing: OCSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: OCSpacing.sm) {
                    OCIcon("speech-bubble").foregroundStyle(OCColor.textMuted)
                    Text(side.question).font(OCType.small.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    OCIconButton("Dismiss side question", icon: "close-small") { store.dismissSideQuestion(sessionID) }
                        .accessibilityIdentifier("dismissSideQuestion")
                }
                ScrollView {
                    switch side.state {
                    case .asking: ProgressView("Working").font(OCType.small).frame(maxWidth: .infinity, alignment: .leading)
                    case .answered(let text): StreamingMarkdownView(text).accessibilityIdentifier("sideAnswer")
                    case .failed(let message):
                        VStack(alignment: .leading, spacing: OCSpacing.sm) {
                            Text("Couldn’t answer that question. " + message).font(OCType.small).foregroundStyle(OCColor.danger)
                            Button("Retry") { store.askSideQuestion(sessionID, question: side.question) }.buttonStyle(OCButtonStyle(.ghost))
                        }
                    }
                }.frame(maxHeight: 220).scrollBounceBehavior(.basedOnSize)
                Text("Side question · not added to the conversation").font(OCType.micro).foregroundStyle(OCColor.textMuted)
            }.padding(OCSpacing.md).background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: OCRadius.lg).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
                .accessibilityElement(children: .contain).accessibilityIdentifier("sideQuestionCard")
        }
    }
}
/// Earlier prompts of this session and its project, newest first; choosing one puts it in the composer to edit.
struct PromptHistorySheet: View {
    let entries: [PromptHistory.Entry]
    let current: String?
    let choose: (String) -> Void
    let cancel: () -> Void
    @State private var query = ""
    private var shown: [PromptHistory.Entry] {
        query.isEmpty ? entries : entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                if shown.isEmpty { Text("No matching prompts").font(OCType.small).foregroundStyle(OCColor.textMuted).listRowBackground(OCColor.background) }
                ForEach(shown) { entry in
                    Button { choose(entry.text) } label: {
                        VStack(alignment: .leading, spacing: OCSpacing.xs) {
                            Text(entry.text).font(OCType.body).lineLimit(3)
                            Text((entry.sessionID == current ? "This session · " : "Project · ") +
                                 Date(timeIntervalSince1970: entry.created / 1_000).formatted(date: .abbreviated, time: .shortened))
                                .font(OCType.micro).foregroundStyle(OCColor.textMuted)
                        }.frame(maxWidth: .infinity, minHeight: OCLayout.touchTarget, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(OCColor.background).accessibilityIdentifier("historyEntry")
                }
            }.scrollContentBackground(.hidden).background(OCColor.background)
                .searchable(text: $query, prompt: "Search prompts")
                .navigationTitle("Prompt history").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }.ocTheme()
    }
}

/// The live transcript above the editor while voice input runs.
struct VoicePanel: View {
    let voice: VoiceModel
    let insert: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            HStack(spacing: OCSpacing.sm) {
                OCIcon("waveform").foregroundStyle(listening ? OCColor.accent : OCColor.textMuted)
                Text(status).font(OCType.small.weight(.semibold)).accessibilityIdentifier("voiceStatus")
                Spacer(minLength: 0)
                actions
            }
            if !voice.transcript.isEmpty {
                Text("\(voice.final)\(voice.final.isEmpty || voice.volatile.isEmpty ? "" : " ")\(Text(voice.volatile).foregroundStyle(OCColor.textMuted))")
                    .font(OCType.body).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("voiceTranscript")
            }
            Text("Audio stays on this device. Only the text you send leaves it.").font(OCType.micro).foregroundStyle(OCColor.textMuted)
        }.padding(OCSpacing.md).background(OCColor.layer1, in: RoundedRectangle(cornerRadius: OCRadius.md)).padding(OCSpacing.sm)
            .accessibilityElement(children: .contain).accessibilityIdentifier("voicePanel")
    }
    private var listening: Bool { voice.state == .listening }
    private var status: String {
        switch voice.state {
        case .idle: ""
        case .starting: "Starting…"
        case .listening: voice.mode == .handsFree ? "Listening · sends after a pause" : "Listening…"
        case .countdown(let seconds): "Sending in \(seconds)…"
        case .waitingForReply: "Waiting for the reply…"
        case .speaking: "Reading the reply"
        case .denied(let reason): reason
        case .failed(let reason): reason
        }
    }
    @ViewBuilder private var actions: some View {
        switch voice.state {
        case .countdown:
            Button("Cancel") { voice.cancelCountdown() }.buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("voiceCancelSend")
            Button("Send now") { voice.sendNow() }.buttonStyle(OCButtonStyle())
        case .denied, .failed:
            Button("OK") { voice.dismissError() }.buttonStyle(OCButtonStyle(.ghost))
        default:
            if voice.mode == .dictation {
                Button("Done") { insert(voice.stop()) }.buttonStyle(OCButtonStyle()).accessibilityIdentifier("voiceDone")
                Button("Cancel") { voice.stop() }.buttonStyle(OCButtonStyle(.ghost))
            } else {
                Button("End") { voice.stop() }.buttonStyle(OCButtonStyle()).accessibilityIdentifier("voiceEnd")
            }
        }
    }
}
#endif

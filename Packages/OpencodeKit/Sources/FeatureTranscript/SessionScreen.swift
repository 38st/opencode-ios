#if os(iOS)
import Foundation
import SwiftUI
import OCModels
import OCSync
import OCRender
import OCDesign
import FeatureApprovals
import FeatureComposer
import FeatureReview

public struct SessionScreen: View {
    let server: ServerStore
    let sessionID: String
    let requestID: String?
    let openChild: (String) -> Void
    let openRoot: (String) -> Void
    let newSession: () -> Void
    let deleted: () -> Void
    @AppStorage("timelineDetail") private var detail = TimelineDetail.compact.rawValue
    @State private var error: String?
    @State private var review = false
    @State private var composerCommand: ComposerCommand?
    @State private var selection: Selection?
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var sizeClass
    public init(server: ServerStore, sessionID: String, requestID: String? = nil, newSession: @escaping () -> Void = {}, deleted: @escaping () -> Void = {}, openRoot: @escaping (String) -> Void = { _ in }, openChild: @escaping (String) -> Void) {
        self.server = server; self.sessionID = sessionID; self.requestID = requestID; self.openChild = openChild; self.newSession = newSession; self.deleted = deleted; self.openRoot = openRoot
    }
    public var body: some View {
        VStack(spacing: 0) {
            if let session = server.sessions[sessionID] {
                SessionHeader(server: server, session: session, composer: server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory), showsTitle: sizeClass == .regular)
                HStack {
                    Menu {
                        Picker("Timeline detail", selection: $detail) {
                            ForEach(TimelineDetail.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        Button("Copy session link") {
                            OCCopy.text("opencodeios://server/" + server.id.rawValue.uuidString + "/session/" + sessionID)
                        }
                        Button("Select text") { selection = Selection(text: selectionText(session)) }
                    } label: { OCLabel(TimelineDetail(rawValue: detail)?.title ?? "Compact", icon: "sliders").font(OCType.small) }
                        .buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("timelineDetail")
                    Spacer(minLength: 0)
                    SessionActions(store: server.readPath, session: session, command: $composerCommand, opened: openRoot, deleted: deleted)
                    if session.info.parentID != nil { OCBadge("Subagent · read only") }
                    if sizeClass != .regular {
                        OCIconButton("Review panel", icon: "sidebar-right") { review = true }.accessibilityIdentifier("sessionReview")
                    }
                }.padding(.horizontal, OCSpacing.lg)
                if let transcript = session.transcript {
                    SessionTimeline(store: server.readPath, session: session, transcript: transcript,
                                    detail: TimelineDetail(rawValue: detail) ?? .compact, requestID: requestID, openChild: openChild, openRoot: openRoot)
                } else { Spacer(); ProgressView("Loading conversation…").font(OCType.small); Spacer() }
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.md) }
                if let error = server.readPath.writeError { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.md) }
                PendingInputPanel(store: server.readPath, session: session).padding(.horizontal, OCSpacing.md)
                ApprovalDock(store: server.readPath, sessionID: sessionID).padding(.horizontal, OCSpacing.md)
                ComposerDock(store: server.readPath, model: server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory),
                             newSession: newSession, clientCommand: { composerCommand = $0 }).padding(OCSpacing.md).layoutPriority(1)
                #if DEBUG
                if ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"] != nil, let elapsed = server.readPath.lastApprovalRoundTrip {
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel("Approval round trip")
                        .accessibilityValue(String(elapsed)).accessibilityIdentifier("approvalTiming")
                }
                if ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"] != nil, let elapsed = server.readPath.lastAnswerRoundTrip {
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel("Answer round trip")
                        .accessibilityValue(String(elapsed)).accessibilityIdentifier("answerTiming")
                }
                #endif
            } else {
                Spacer()
                OCEmptyState(error == nil ? "Opening session…" : "Session unavailable", detail: error ?? "Loading the conversation from your server.", icon: "bubble-5") { EmptyView() }
                Spacer()
            }
        }.environment(\.ocFileLinks, fileLinks)
            .background(OCColor.background).clipShape(RoundedRectangle(cornerRadius: OCRadius.xl))
            .navigationTitle(server.sessions[sessionID]?.info.title ?? "Session").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $review) {
                WorkspaceReviewPanel(server: server, sessionID: sessionID)
                    .safeAreaInset(edge: .top) { HStack { Spacer(); OCIconButton("Close review", icon: "close") { review = false }.accessibilityIdentifier("closeReview") }.padding(.horizontal, OCSpacing.sm) }.ocSheet()
            }
            .onChange(of: panelRequest) { _, request in if request != nil && sizeClass != .regular { review = true } }
            .sheet(item: $selection) { OCTextSelectionSheet(text: $0.text).ocSheet() }
            .task(id: sessionID) {
                do {
                    try await server.readPath.open(sessionID)
                    try Task.checkCancellation()
                    try await server.readPath.loadFamily(sessionID)
                    error = nil
                } catch is CancellationError {} catch { self.error = "Could not refresh this session. Cached messages are shown when available." }
            }
            .task(id: ViewStamp(idle: server.sessions[sessionID]?.info.time.idle, active: phase == .active)) {
                guard phase == .active else { return }
                do { try await server.readPath.markViewed(sessionID) }
                catch is CancellationError {} catch { self.error = "Could not mark this session read." }
            }
            .onDisappear { server.readPath.close(sessionID) }
    }
    private var fileLinks: OCFileLinks? {
        guard let session = server.sessions[sessionID] else { return nil }
        let files = server.readPath.files(sessionID: sessionID, directory: session.info.location.directory)
        return OCFileLinks(open: { href in
            server.readPath.review(sessionID: sessionID, directory: session.info.location.directory).selectTab("Files")
            server.readPath.performWrite { await files.openLink(href) } completion: { _ in }
        }, existing: { await files.existingLinks($0) }, known: { files.knownLinks($0) }, comment: { value in
            var value = value; value.file = ComposerInput.absolute(value.file, directory: session.info.location.directory)
            server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory).addComment(value)
        }, comments: { file in
            server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory).comments.filter {
                $0.file == ComposerInput.absolute(file, directory: session.info.location.directory)
            }
        }, updateComment: { value in
            server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory).updateComment(value)
        }, removeComment: { id in
            server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory).removeComment(id)
        })
    }
    private var panelRequest: UUID? {
        guard let session = server.sessions[sessionID] else { return nil }
        let model = server.readPath.review(sessionID: sessionID, directory: session.info.location.directory)
        return model.tab == "Files" ? server.readPath.files(sessionID: sessionID, directory: session.info.location.directory).presentRequest : model.presentRequest
    }
    private func selectionText(_ session: SessionModel) -> String {
        guard let transcript = session.transcript else { return "" }
        return transcript.visibleOrder(revert: session.info.revert?.messageID, pending: session.pending).compactMap { id in
            guard let message = transcript.messages[id] else { return nil }
            return message.fields.type == "assistant" ? message.items.map(\.text).joined(separator: "\n\n") : message.fields.text
        }.joined(separator: "\n\n")
    }
    private struct Selection: Identifiable { let id = UUID(); let text: String }
    private struct ViewStamp: Equatable { let idle: Double?; let active: Bool }
}

private struct SessionHeader: View {
    let server: ServerStore
    let session: SessionModel
    let composer: ComposerModel
    let showsTitle: Bool
    private var lastAssistant: MessageFields? {
        guard let transcript = session.transcript else { return nil }
        for id in transcript.order.reversed() {
            if let fields = transcript.messages[id]?.fields, fields.type == "assistant" { return fields }
        }
        return nil
    }
    private var usage: String {
        let last = session.transcript?.order.reversed().compactMap { session.transcript?.messages[$0]?.fields }.first { $0.type == "assistant" && $0.tokens != nil }
        guard let tokens = last?.tokens, let model = last?.model ?? session.info.model,
              let limit = server.catalogs[session.info.location.key]?.models.value?.first(where: {
                  $0.id == model.id && (model.providerID.isEmpty || $0.providerID == model.providerID)
              })?.limit.context, limit > 0, limit.isFinite else { return "Context —" }
        let fraction = (tokens.input + tokens.output + tokens.reasoning + tokens.cacheRead + tokens.cacheWrite) / limit
        guard fraction.isFinite, fraction >= 0 else { return "Context —" }
        return "Context " + fraction.formatted(.percent.precision(.fractionLength(0)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            if showsTitle {
                Text(session.info.title ?? "Untitled session").font(OCType.heading).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OCSpacing.sm) { labels }
                VStack(alignment: .leading, spacing: OCSpacing.xs) { labels }
            }
        }.padding(OCSpacing.lg).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(OCColor.borderMuted).frame(height: OCBorder.hairline) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sessionHeader-" + server.id.rawValue.uuidString)
    }
    @ViewBuilder private var labels: some View {
        Text((session.info.agent ?? lastAssistant?.agent)?.capitalized ?? "Agent").font(OCType.small).foregroundStyle(OCColor.textMuted)
        Text(session.info.model?.id ?? lastAssistant?.model?.id ?? "Model —").font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(1)
        if let variant = session.info.model?.variant, variant != "default" {
            Text(variant).font(OCType.small).foregroundStyle(OCColor.textMuted)
        }
        if composer.pendingSelection { OCBadge("Pending").accessibilityLabel("Agent or model choice pending") }
        OCBadge(usage)
        Text(server.readPath.family(session.id).reduce(0) { $0 + $1.info.cost }.formatted(.currency(code: "USD")))
            .font(OCType.micro).foregroundStyle(OCColor.textMuted).accessibilityLabel("Family cost")
    }
}
#endif

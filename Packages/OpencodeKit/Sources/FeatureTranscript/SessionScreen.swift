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
    let openSettings: () -> Void
    let reviewToggle: UUID?
    let ownsCommands: Bool
    @AppStorage("timelineDetail") private var detail = TimelineDetail.compact.rawValue
    @State private var error: String?
    @State private var review = false
    @State private var context = false
    /// Compact chrome stays while Session information is open: its menu would close as the keyboard leaves.
    @State private var informationOpen = false
    @State private var composerCommand: ComposerCommand?
    @State private var selection: Selection?
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    /// - Parameter ownsCommands: whether this screen is on top, so the menu bar's composer commands and Toggle review act
    ///   here; false for a parent session under a subagent or under New session.
    public init(server: ServerStore, sessionID: String, requestID: String? = nil, newSession: @escaping () -> Void = {}, deleted: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {}, reviewToggle: UUID? = nil, ownsCommands: Bool = true, openRoot: @escaping (String) -> Void = { _ in }, openChild: @escaping (String) -> Void) {
        self.server = server; self.sessionID = sessionID; self.requestID = requestID; self.openChild = openChild; self.newSession = newSession; self.deleted = deleted; self.openRoot = openRoot
        self.openSettings = openSettings; self.reviewToggle = reviewToggle; self.ownsCommands = ownsCommands
    }
    public var body: some View {
        GeometryReader { geometry in
            let compactChrome = typeSize.isAccessibilitySize || geometry.size.height < OCLayout.sessionCompactHeight || informationOpen
            VStack(spacing: 0) {
                if let session = server.sessions[sessionID] {
                    let header = SessionHeader(server: server, session: session, composer: server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory),
                                               showsTitle: sizeClass == .regular, showContext: showContext)
                    if !compactChrome { header }
                    HStack {
                        if compactChrome {
                            OCMenuButton("Session information", identifier: "sessionInformation",
                                         items: header.metadata + [OCMenuItem("Context details", action: showContext)], isOpen: $informationOpen) {
                                OCIcon("info").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget)
                            }
                        }
                        Menu {
                            Picker("Timeline detail", selection: $detail) {
                                ForEach(TimelineDetail.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                            }
                            Button("Copy session link") {
                                OCCopy.text("opencodeios://server/" + server.id.rawValue.uuidString + "/session/" + sessionID)
                            }
                            Button("Select text") { selection = Selection(text: selectionText(session)) }
                        } label: {
                            if compactChrome { OCIcon("sliders").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
                            else { OCLabel(TimelineDetail(rawValue: detail)?.title ?? "Compact", icon: "sliders").font(OCType.small).padding(.horizontal, OCSpacing.md).frame(minHeight: OCLayout.touchTarget) }
                        }.buttonStyle(.plain).accessibilityLabel("Timeline detail").accessibilityValue(TimelineDetail(rawValue: detail)?.title ?? "Compact")
                            .accessibilityIdentifier("timelineDetail")
                        Spacer(minLength: 0)
                        SessionActions(store: server.readPath, session: session, command: $composerCommand, opened: openRoot, deleted: deleted)
                        if session.info.parentID != nil && !compactChrome { OCBadge("Subagent · read only") }
                        if sizeClass != .regular {
                            OCIconButton("Review panel", icon: "sidebar-right") { review = true }.accessibilityIdentifier("sessionReview")
                        }
                    }.padding(.horizontal, OCSpacing.lg)
                    if server.connectionNotice != nil { connectionBanner.padding(.horizontal, OCSpacing.md) }
                    if let transcript = session.transcript {
                        SessionTimeline(store: server.readPath, session: session, transcript: transcript,
                                        detail: TimelineDetail(rawValue: detail) ?? .compact, requestID: requestID, openChild: openChild, openRoot: openRoot)
                            .frame(minHeight: OCLayout.timelineMinimumHeight)
                    } else { Spacer(); ProgressView("Loading conversation…").font(OCType.small); Spacer() }
                    if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.md).ocAnnounce(error, initial: true) }
                    if let error = server.readPath.writeError { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.md).ocAnnounce(error, initial: true) }
                    if hasPendingInput(session) {
                        VStack(spacing: 0) {
                            PendingInputPanel(store: server.readPath, session: session)
                            ApprovalDock(store: server.readPath, sessionID: sessionID)
                        }.frame(maxHeight: compactChrome ? geometry.size.height * OCLayout.sessionPendingFraction : nil)
                            .padding(.horizontal, OCSpacing.md)
                    }
                    ComposerDock(store: server.readPath, model: server.readPath.composer(sessionID: sessionID, directory: session.info.location.directory),
                                 newSession: newSession, clientCommand: { composerCommand = $0 }, ownsCommands: ownsCommands).padding(OCSpacing.md)
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
            }
        }.environment(\.ocFileLinks, fileLinks)
            .background(OCColor.background).clipShape(RoundedRectangle(cornerRadius: OCRadius.xl))
            .navigationTitle(server.sessions[sessionID]?.info.title ?? "Session").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $review) {
                // Close the sheet first, as the context sheet does, so the session does not open beneath it.
                WorkspaceReviewPanel(server: server, sessionID: sessionID, openSession: { id in review = false; openSession(id) })
                    .safeAreaInset(edge: .top) { HStack { Spacer(); OCIconButton("Close review", icon: "close") { review = false }.accessibilityIdentifier("closeReview") }.padding(.horizontal, OCSpacing.sm) }.ocSheet()
            }
            .sheet(isPresented: $context) {
                ContextSheet(store: server.readPath, sessionID: sessionID, openSession: { id in context = false; openSession(id) }, showChanges: {
                    context = false
                    if let session = server.sessions[sessionID] { server.readPath.review(sessionID: sessionID, directory: session.info.location.directory).present("Changes") }
                }) { context = false }.ocSheet()
            }
            .onChange(of: panelRequest) { _, request in if request != nil && sizeClass != .regular { review = true } }
            .onChange(of: reviewToggle) { _, request in if request != nil && sizeClass != .regular && ownsCommands { review.toggle() } }
            .onChange(of: pendingInputStamp) { old, next in
                // A request arriving while focus is in the composer or earlier output would otherwise be silent.
                guard old.sessionID == next.sessionID, let text = TimelineAnnouncement.pendingInput(previous: Set(old.ids),
                    permissions: server.readPath.familyPermissions(sessionID), forms: server.readPath.familyForms(sessionID)) else { return }
                OCAnnouncer.post(text, priority: .high)
            }
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
    /// The cached transcript stays readable while the server is unreachable; say so, with a way back.
    private var connectionBanner: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let notice = server.notice(now: .now) {
                OCConnectionBanner(notice.title, detail: notice.detail, actionTitle: notice.actionTitle) {
                    switch notice.action {
                    case .repair, .details: openSettings()
                    case let action?: Task { await server.perform(action) }
                    case nil: break
                    }
                }
            }
        }
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
    /// The header's context label: the Context tab on iPad, a sheet on iPhone.
    private func showContext() {
        guard let session = server.sessions[sessionID] else { return }
        if sizeClass == .regular { server.readPath.review(sessionID: sessionID, directory: session.info.location.directory).present("Context") }
        else { context = true }
    }
    private func openSession(_ id: String) {
        if server.sessions[id]?.info.parentID != nil { openChild(id) } else { openRoot(id) }
    }
    private struct PendingInputStamp: Equatable { let sessionID: String; let ids: [String] }
    private var pendingInputStamp: PendingInputStamp {
        .init(sessionID: sessionID, ids: server.readPath.familyPermissions(sessionID).map(\.id) + server.readPath.familyForms(sessionID).map(\.id))
    }
    private func hasPendingInput(_ session: SessionModel) -> Bool {
        session.pending.contains { $0.type == "user" && $0.delivery == .queue } ||
            server.readPath.savedPrompts.contains { $0.sessionID == sessionID } ||
            !server.readPath.familyPermissions(sessionID).isEmpty || !server.readPath.familyForms(sessionID).isEmpty
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
    var showContext: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize
    private var models: [ModelInfo] { server.catalogs[session.info.location.key]?.models.value ?? [] }
    /// The server's selection, named as the composer names it (docs/design.md: the dock marks unapplied choices Pending).
    private var modelName: String? { (session.info.model ?? lastAssistant?.model).map { ComposerPickers.displayName($0, in: models) } }
    private var lastAssistant: MessageFields? {
        guard let transcript = session.transcript else { return nil }
        for id in transcript.order.reversed() {
            if let fields = transcript.messages[id]?.fields, fields.type == "assistant" { return fields }
        }
        return nil
    }
    /// The Context tab's calculation: the step after the last compaction and before the revert boundary.
    private var usage: String {
        let messages = session.transcript.map { transcript in transcript.order.compactMap { transcript.messages[$0]?.fields } } ?? []
        return ContextUsage.label(ContextUsage.compute(messages, boundary: session.info.revert?.messageID, models: models, session: session.info.model))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            if showsTitle {
                Text(session.info.title ?? "Untitled session").font(OCType.heading).fixedSize(horizontal: false, vertical: true)
            }
            // One line where the model name truncates, so a long id or a new selection never reflows the header.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OCSpacing.xs) { labels }
            } else {
                HStack(spacing: OCSpacing.sm) { labels }
            }
        }.padding(OCSpacing.lg).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(OCColor.borderMuted).frame(height: OCBorder.hairline) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sessionHeader-" + server.id.rawValue.uuidString)
    }
    /// The header's labels as the compact chrome's Session information rows.
    var metadata: [OCMenuItem] {
        var rows = [OCMenuItem("Agent: " + ((session.info.agent ?? lastAssistant?.agent)?.capitalized ?? "Agent")), OCMenuItem("Model: " + (modelName ?? "—"))]
        if let variant = session.info.model?.variant, variant != "default" { rows.append(OCMenuItem("Variant: " + variant)) }
        if composer.pendingSelection { rows.append(OCMenuItem("Agent or model choice pending")) }
        rows.append(OCMenuItem(usage))
        rows.append(OCMenuItem("Family cost: " + server.readPath.family(session.id).reduce(0) { $0 + $1.info.cost }.formatted(.currency(code: "USD"))))
        if session.info.parentID != nil { rows.append(OCMenuItem("Subagent · read only")) }
        return rows
    }
    @ViewBuilder private var labels: some View {
        let fixed = !typeSize.isAccessibilitySize
        Text((session.info.agent ?? lastAssistant?.agent)?.capitalized ?? "Agent").font(OCType.small).foregroundStyle(OCColor.textMuted)
            .lineLimit(1).fixedSize(horizontal: fixed, vertical: false)
        Text(modelName ?? "Model —").font(OCType.small).foregroundStyle(OCColor.textMuted)
            .lineLimit(fixed ? 1 : nil).truncationMode(.middle).layoutPriority(-1)
        if let variant = session.info.model?.variant, variant != "default" {
            Text(variant).font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(1).fixedSize(horizontal: fixed, vertical: false)
        }
        Button(action: showContext) { OCBadge(usage) }.buttonStyle(.plain).ocHover(RoundedRectangle(cornerRadius: OCRadius.xs))
            .accessibilityHint("Shows context and token usage").accessibilityIdentifier("sessionContext")
            .fixedSize(horizontal: fixed, vertical: false)
        Text(server.readPath.family(session.id).reduce(0) { $0 + $1.info.cost }.formatted(.currency(code: "USD")))
            .font(OCType.micro).foregroundStyle(OCColor.textMuted).accessibilityLabel("Family cost")
            .lineLimit(1).fixedSize(horizontal: fixed, vertical: false)
    }
}
#endif

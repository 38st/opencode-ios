#if os(iOS)
import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import OCFoundation
import OCModels
import OCSync
import OCDesign

public struct ComposerDock: View {
    let store: ReadStore
    @Bindable var model: ComposerModel
    let newSession: () -> Void
    let clientCommand: (ComposerCommand) -> Void
    let start: (@MainActor (String, ModelRef?) async throws -> String)?
    let opened: (String) -> Void
    let ownsCommands: Bool
    @AppStorage("followUpBehavior") private var followUp = "steer"
    @AppStorage("showAgent") private var showAgentSetting = false
    @AppStorage("composerModelHistory") private var history = "{}"
    @AppStorage("composerVariants") private var variants = "{}"
    @State private var contentHeight: CGFloat = OCComposerMetrics.editorMinimum
    @State private var suggestionHeight: CGFloat = OCLayout.touchTarget
    @State private var caret = 0
    @State private var suggestions: [ComposerSuggestion] = []
    @State private var active = 0
    @State private var closedTrigger: ComposerTrigger?
    @State private var showModels = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var action: Task<Void, Never>?
    @State private var composing = false
    @State private var historyCursor = PromptHistory.Cursor()
    @State private var showHistory = false
    @State private var gitAction: GitQuickAction?
    @State private var voice: VoiceModel?
    /// Names this composer to the menu bar.
    @State private var commandOwner = UUID()
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var editorLineHeight = OCType.lineHeight
    /// - Parameter ownsCommands: whether the menu bar's composer commands act here; false while another screen covers
    ///   this one.
    public init(store: ReadStore, model: ComposerModel, newSession: @escaping () -> Void = {},
                clientCommand: @escaping (ComposerCommand) -> Void = { _ in },
                start: (@MainActor (String, ModelRef?) async throws -> String)? = nil, opened: @escaping (String) -> Void = { _ in },
                ownsCommands: Bool = true) {
        self.store = store; self.model = model; self.newSession = newSession; self.clientCommand = clientCommand
        self.start = start; self.opened = opened; self.ownsCommands = ownsCommands
    }
    private var running: Bool { model.session?.status.isRunning == true }
    private var showAgent: Bool { ComposerPickers.showAgent(model.catalog.agents.value ?? [], setting: showAgentSetting) }
    private var trigger: ComposerTrigger? { model.options.shell ? nil : ComposerTrigger.detect(model.text, caret: caret) }
    private var placeholder: String {
        if model.options.shell { return "Enter shell command… git status" }
        return running || model.session?.pending.isEmpty == false ? "Add follow-up, / for commands, @ for context…" : "Ask anything, / for commands, @ for context…"
    }
    private var preference: Delivery { followUp == "queue" ? .queue : .steer }
    private var minimumEditorHeight: CGFloat { max(OCComposerMetrics.editorMinimum, editorLineHeight + OCSpacing.lg + OCSpacing.sm) }
    public var body: some View {
        VStack(spacing: OCSpacing.xs) {
            if model.session?.info.parentID != nil {
                OCComposerSurface {
                    Text("Subagent sessions are read only. Send prompts to the parent session.")
                        .font(OCType.small).foregroundStyle(OCColor.textMuted).padding(OCSpacing.lg)
                }
            } else {
                if let trigger, trigger != closedTrigger { suggestionList.zIndex(1) }
                OCComposerSurface {
                    ScrollView {
                        editorContent.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }.scrollBounceBehavior(.basedOnSize).scrollDismissesKeyboard(.interactively)
                        .frame(minHeight: minimumEditorHeight, idealHeight: max(minimumEditorHeight, contentHeight), maxHeight: max(minimumEditorHeight, contentHeight))
                    toolbar.fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .focusedSceneValue(\.ocComposerCommands, ownsCommands ? OCComposerCommands(owner: commandOwner, session: model.sessionID, state: commandState, perform: perform) : nil)
        .task { await model.load(); caret = String(model.text.characters).utf16.count }
        .task(id: trigger) { await updateSuggestions() }
        .popover(isPresented: $showModels) {
            ModelPicker(model: model, history: recent, select: selectModel).ocSheet().presentationCompactAdaptation(.sheet)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photos, matching: .images)
        .onChange(of: photos) { _, selection in
            run {
                for item in selection {
                    if let bytes = try await item.loadTransferable(type: Data.self) {
                        await model.addAttachment(bytes, mime: item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg", name: "Photo")
                    }
                }
                photos = []
            }
        }
        .sheet(isPresented: $showCamera) { ComposerCamera { data in if let data { run { await model.addAttachment(data, mime: "image/jpeg", name: "Camera.jpg") } } }.ignoresSafeArea() }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .pdf, .text, .data], allowsMultipleSelection: true) { result in
            run { for url in try result.get() { try await importFile(url) } }
        }
        // Drops on the editor itself go through its paste configuration; this takes the rest of the dock.
        .onDrop(of: [UTType(exportedAs: ComposerDrop.mentionType), .fileURL, .image, .pdf, .text, .audiovisualContent], isTargeted: nil) { providers in
            guard model.session?.info.parentID == nil else { return false }
            run { for provider in providers { try await drop(provider) } }; return true
        }
        .sheet(isPresented: $showHistory) {
            PromptHistorySheet(entries: promptEntries, current: model.sessionID) { text in showHistory = false; recallText(text) } cancel: { showHistory = false }.ocSheet()
        }
        .sheet(item: $gitAction) { action in
            OCConfirmationSheet(action.title, message: action.message, detail: action.prompt, confirmTitle: action.confirmTitle, destructive: false,
                                cancel: { gitAction = nil }) { gitAction = nil; sendGitAction(action) }.ocSheet()
        }
        .sheet(isPresented: $model.confirmRevert) {
            OCConfirmationSheet("Discard reverted messages?", message: "The reverted messages and their file changes will be permanently discarded when you send this prompt.",
                                confirmTitle: "Discard and send", cancel: { model.confirmRevert = false }, confirm: { model.confirmSend() }).ocSheet()
        }
        .sheet(isPresented: Binding(get: { model.sessionID != nil && store.replacingDraftSessionID == model.sessionID },
                                    set: { if !$0 { store.resolveDraftReplacement(false) } })) {
            OCConfirmationSheet("Replace your draft?", message: "Your unsent text and attachments will be replaced by this prompt.",
                                confirmTitle: "Replace", cancel: { store.resolveDraftReplacement(false) },
                                confirm: { store.resolveDraftReplacement(true) }).ocSheet()
        }
        .onDisappear {
            action?.cancel(); voice?.stop()
            if model.sessionID != nil && store.replacingDraftSessionID == model.sessionID { store.resolveDraftReplacement(false) }
        }
    }
    private var editorContent: some View {
        VStack(spacing: 0) {
            if let voice, voice.state != .idle { VoicePanel(voice: voice, insert: insertDictation) }
            if model.session?.info.revert != nil { revertNotice }
            if model.options.editingOutboxID != nil {
                HStack {
                    Text("Edit and resend").font(OCType.small)
                    Spacer(minLength: 0)
                    Button("Cancel") { model.cancelEditingOutbox() }.buttonStyle(OCButtonStyle(.ghost))
                }.padding(.horizontal, OCSpacing.sm).accessibilityIdentifier("editingOutbox")
            }
            if !model.options.shell && !model.comments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: OCSpacing.sm) {
                        ForEach(model.comments) { comment in
                            HStack(spacing: 0) {
                                Button { model.focusComment(comment.id) } label: {
                                    VStack(alignment: .leading, spacing: OCSpacing.xs) {
                                        Text(comment.comment).font(OCType.small).lineLimit(1)
                                        HStack(spacing: OCSpacing.xs) {
                                            OCFileIcon(comment.file)
                                            Text((comment.file as NSString).lastPathComponent + (comment.selection.map { ":\($0.lower)" + ($0.upper == $0.lower ? "" : "-\($0.upper)") } ?? "")).font(OCType.micro).lineLimit(1)
                                        }.foregroundStyle(OCColor.textMuted)
                                    }.frame(width: 116, alignment: .leading).frame(minHeight: 44)
                                }.buttonStyle(.plain)
                                OCIconButton("Remove attachment", icon: "close") { model.removeComment(comment.id) }
                            }.frame(width: 160).padding(.vertical, OCSpacing.xs).background(OCColor.layer2, in: RoundedRectangle(cornerRadius: OCRadius.md))
                        }
                    }.padding(OCSpacing.sm)
                }.accessibilityIdentifier("commentAttachments")
            }
            if model.options.shell {
                HStack {
                    OCLabel("Shell command", icon: "terminal").font(OCType.small)
                    Spacer()
                    Button("Exit") { model.shellMode(false) }.buttonStyle(OCButtonStyle(.ghost))
                }.padding(.horizontal, OCSpacing.sm)
            } else if !model.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: OCSpacing.sm) {
                        ForEach(model.attachments) { file in DraftAttachmentChip(model: model, file: file) }
                    }.padding(OCSpacing.sm)
                }
                if let warning = capabilityWarning {
                    Text(warning).font(OCType.small).foregroundStyle(OCColor.warning).padding(.horizontal, OCSpacing.lg)
                }
            }
            PromptEditor(text: Binding(get: { model.text }, set: { historyCursor.reset(); model.setText($0) }), caret: $caret,
                         shell: model.options.shell, enabled: model.loaded && !model.busy,
                         placeholder: placeholder,
                         suggestionsActive: trigger != nil && trigger != closedTrigger,
                         historyActive: historyActive,
                         focusRequest: model.focusRequest,
                         pasteAttachment: { provider in run { try await importProvider(provider) } },
                         dropMention: { path, offset in caret = model.mentionFile(path, atUTF16: offset) },
                         composing: { composing = $0 }, key: handleKey)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.sm).accessibilityIdentifier("composerError").ocAnnounce(error, initial: true) }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var toolbar: some View {
        VStack(spacing: OCSpacing.xs) {
            if typeSize.isAccessibilitySize {
                HStack {
                    attachmentMenu
                    Menu {
                        Button("Choose model") { showModels = true }
                        if showAgent { Menu("Choose agent") { AgentOptions(agents: model.catalog.agents.value ?? [], selected: model.effectiveAgent, select: model.selectAgent) } }
                        if let selected = model.selectedModel {
                            Menu("Choose variant") { VariantOptions(variants: selected.variants, selected: model.effectiveModel?.variant, select: selectVariant) }
                        }
                    } label: { OCIcon("sliders").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
                        .accessibilityLabel("Agent and model").disabled(model.options.shell || model.busy)
                    Spacer(minLength: 0)
                    voiceButton
                    deliveryControls
                }
            } else {
                HStack(spacing: OCSpacing.xxs) { attachmentMenu; selectionControls; Spacer(minLength: 0); voiceButton; deliveryControls }
            }
        }.padding(.horizontal, OCSpacing.sm).padding(.bottom, OCSpacing.xs).frame(minHeight: OCComposerMetrics.toolbar)
    }
    private var attachmentMenu: some View {
            Menu {
                Button("Photos") { showPhotos = true }
                Button("Camera") { showCamera = true }.disabled(!ComposerCamera.available)
                Button("Files") { showFiles = true }
                PasteButton(supportedContentTypes: [.image, .pdf, .text]) { providers in run { for provider in providers { try await importProvider(provider) } } }
                Divider()
                Button("Commands") { insert("/") }
                Button("Context") { insert("@") }
                Button("Shell command") { model.shellMode(true) }
                Button("Prompt history") { showHistory = true }.disabled(promptEntries.isEmpty).accessibilityIdentifier("promptHistory")
                if model.sessionID != nil && model.session?.info.parentID == nil {
                    Divider()
                    ForEach(GitQuickAction.allCases) { action in
                        Button(action.title) { gitAction = action }.disabled(!gitAvailable)
                    }
                }
            } label: { OCIcon("plus").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
                .accessibilityLabel("Add attachment or context").accessibilityIdentifier("composerAdd").disabled(model.busy)
    }
    private var selectionControls: some View {
            ScrollView(.horizontal) {
                HStack(spacing: typeSize.isAccessibilitySize ? OCSpacing.lg : OCSpacing.sm) {
                    if showAgent {
                        Menu {
                            AgentOptions(agents: model.catalog.agents.value ?? [], selected: model.effectiveAgent, select: model.selectAgent)
                        } label: { OCComposerChoice(model.effectiveAgent.capitalized)
                            .foregroundStyle(OCMentionStyle.agentAccent(model.catalog.agents.value?.first { ComposerPickers.agentID($0) == model.effectiveAgent }?.color)) }
                            .accessibilityLabel("Choose agent").accessibilityValue(model.effectiveAgent.capitalized).accessibilityIdentifier("composerAgent")
                    }
                    Button { showModels = true } label: {
                        OCComposerChoice(model.selectedModel.map { ComposerPickers.displayName($0) } ?? model.effectiveModel?.id ?? "Choose model")
                    }.accessibilityIdentifier("composerModel").accessibilityLabel("Choose model").accessibilityValue(model.selectedModel.map { ComposerPickers.displayName($0) } ?? model.effectiveModel?.id ?? "")
                    if let modelInfo = model.selectedModel, modelInfo.variants.contains(where: { $0.id != "default" }) {
                        Menu {
                            VariantOptions(variants: modelInfo.variants, selected: model.effectiveModel?.variant, select: selectVariant)
                        } label: { OCComposerChoice(variantTitle) }
                            .accessibilityLabel("Choose variant").accessibilityValue(variantTitle).accessibilityIdentifier("composerVariant")
                    }
                    if model.pendingSelection { OCBadge("Pending") }
                }.foregroundStyle(OCColor.textMuted)
            }.scrollIndicators(.hidden).opacity(model.options.shell ? 0.4 : 1).disabled(model.options.shell || model.busy)
    }
    @ViewBuilder private var deliveryControls: some View {
            if running && !model.blank && !model.options.shell {
                Button(followUp == "queue" ? "Steer" : "Queue") { send(alternate: true) }.font(OCType.small)
                    .buttonStyle(OCButtonStyle(.ghost)).accessibilityHint("Send without interrupting").accessibilityIdentifier("alternateDelivery")
            }
            Button { send() } label: {
                OCIcon(running && model.blank ? "stop" : "arrow-up")
            }.buttonStyle(OCSubmitIconButtonStyle()).accessibilityLabel(running && model.blank ? "Stop" : "Send")
                .accessibilityIdentifier("composerSend").disabled(model.busy || !model.loaded || model.blank && !running)
                .contextMenu {
                    if running && !model.blank {
                        SendOptions(alternate: followUp == "queue" ? "Steer" : "Queue", sendAlternate: { send(alternate: true) }, interrupt: { send(interrupt: true) })
                    }
                }
    }
    private var suggestionList: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    if suggestions.isEmpty { Text("No matching items").font(OCType.small).padding(OCSpacing.lg) }
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                        Button { select(item) } label: {
                            HStack(spacing: OCSpacing.sm) {
                                suggestionIcon(item)
                                VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                                    Text(item.label).font(OCType.small)
                                    if !item.description.isEmpty { Text(item.description).font(OCType.micro).foregroundStyle(OCColor.textMuted).lineLimit(2) }
                                }
                            }.frame(maxWidth: .infinity, minHeight: OCLayout.touchTarget, alignment: .leading).padding(.horizontal, OCSpacing.md)
                                .background(index == active ? OCColor.hover : OCColor.background)
                        }.buttonStyle(.plain).id(item.id).accessibilityIdentifier("suggestion-" + item.id)
                    }
                }.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { suggestionHeight = $0 }
            }.frame(height: min(220, suggestionHeight))
                .background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.dock)).ocElevation(.floating)
                .onChange(of: active) { _, next in if suggestions.indices.contains(next) { scroll.scrollTo(suggestions[next].id) } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("composerSuggestions")
    }
    @ViewBuilder private func suggestionIcon(_ item: ComposerSuggestion) -> some View {
        switch item.mention?.kind {
        case "agent": OCIcon("brain").foregroundStyle(OCMentionStyle.color("agent"))
        case "skill": OCIcon("post-skill")
        case "reference": OCIcon("folder").foregroundStyle(OCMentionStyle.color("reference"))
        case "file": OCFileIcon(item.mention?.value ?? item.label, directory: item.description == "Directory")
        default: OCIcon("terminal")
        }
    }
    private var revertNotice: some View {
        HStack {
            Text("\(revertedCount) \(revertedCount == 1 ? "message" : "messages") reverted").font(OCType.small)
            Spacer()
            Button("Redo") { clientCommand(.redo) }.buttonStyle(OCButtonStyle(.ghost))
        }.padding(.horizontal, OCSpacing.md).accessibilityIdentifier("revertNotice")
    }
    private var revertedCount: Int {
        guard let session = model.session, let boundary = session.info.revert?.messageID,
              let order = session.transcript?.order, let index = order.firstIndex(of: boundary) else { return 0 }
        return order.count - index
    }
    private var capabilityWarning: String? {
        guard let selected = model.selectedModel else { return nil }
        if model.attachments.contains(where: { $0.mime.hasPrefix("image/") }) && !selected.capabilities.input.contains("image") { return "This model does not support image input. Choose another model before sending." }
        if model.attachments.contains(where: { $0.mime == "application/pdf" }) && !selected.capabilities.input.contains("pdf") { return "This model does not support PDF input. Choose another model before sending." }
        return nil
    }
    private var recent: [String] { (try? JSONDecoder().decode([String: [String]].self, from: Data(history.utf8)))?[store.serverID] ?? [] }
    private func send(alternate: Bool = false, interrupt: Bool = false) {
        guard model.loaded, !model.busy else { return }
        historyCursor.reset()
        if !model.options.shell, let question = ComposerSuggestions.sideQuestion(String(model.text.characters)) {
            guard let sessionID = model.sessionID else { model.error = "Side questions need a session with a conversation. Send a prompt first."; return }
            if question.isEmpty { model.error = "Add a question after /btw"; return }
            store.askSideQuestion(sessionID, question: question)
            model.setText(AttributedString()); caret = 0; closedTrigger = nil
            return
        }
        if !model.options.shell, let command = ComposerSuggestions.submittedCommand(String(model.text.characters),
            server: model.catalog.commands.value, session: model.sessionID != nil, showAgent: showAgent,
            hasPrompts: hasVisiblePrompts, reverted: model.session?.info.revert != nil) {
            select(command); return
        }
        let usedModel = model.options.shell ? nil : model.effectiveModel
        model.submit(preference: preference, alternate: alternate, interrupt: interrupt, start: start) { id in
            if let usedModel { remember(usedModel) }
            caret = 0; closedTrigger = nil; opened(id)
        }
    }
    private func selectModel(_ value: ModelInfo) {
        var raw: JSONValue = .object(["id": .string(value.id), "providerID": .string(value.providerID)])
        let remembered = (try? JSONDecoder().decode([String: String].self, from: Data(variants.utf8)))?[ComposerPickers.key(value)]
        if let remembered, value.variants.contains(where: { $0.id == remembered }) { raw.set("variant", .string(remembered)) }
        model.selectModel(.init(raw: raw)); showModels = false
    }
    private func remember(_ value: ModelRef) {
        var records = (try? JSONDecoder().decode([String: [String]].self, from: Data(history.utf8))) ?? [:]
        let key = ComposerPickers.key(value)
        records[store.serverID] = Array(([key] + recent.filter { $0 != key }).prefix(5))
        if let data = try? JSONEncoder().encode(records), let string = String(data: data, encoding: .utf8) { history = string }
    }
    private var variantTitle: String { model.effectiveModel?.variant == "default" ? "Default" : model.effectiveModel?.variant ?? "Default" }
    private func selectVariant(_ value: String?) {
        guard var selection = model.effectiveModel else { return }
        selection["variant"] = value.map(JSONValue.string); model.selectModel(selection)
        var records = (try? JSONDecoder().decode([String: String].self, from: Data(variants.utf8))) ?? [:]
        records[ComposerPickers.key(selection)] = value
        if let data = try? JSONEncoder().encode(records), let string = String(data: data, encoding: .utf8) { variants = string }
    }
    private var hasVisiblePrompts: Bool {
        guard let session = model.session, let transcript = session.transcript else { return false }
        return transcript.visibleOrder(revert: session.info.revert?.messageID, pending: session.pending)
            .contains { transcript.messages[$0]?.fields.type == "user" }
    }
    private func updateSuggestions() async {
        guard let trigger, trigger != closedTrigger else { suggestions = []; return }
        active = 0
        if trigger.kind == .command {
            suggestions = ComposerSuggestions.commands(query: trigger.query, server: model.catalog.commands.value,
                session: model.sessionID != nil, showAgent: showAgent, hasPrompts: hasVisiblePrompts, reverted: model.session?.info.revert != nil)
        } else {
            suggestions = ComposerSuggestions.context(query: trigger.query, references: model.catalog.references.value, skills: model.catalog.skills.value, agents: model.catalog.agents.value ?? [], files: [])
            do {
                try await Task.sleep(for: .milliseconds(120))
                let files = try await store.findFiles(trigger.query, directory: model.directory)
                try Task.checkCancellation()
                model.clearSearchError()
                suggestions = ComposerSuggestions.context(query: trigger.query, references: model.catalog.references.value, skills: model.catalog.skills.value, agents: model.catalog.agents.value ?? [], files: files)
            } catch {
                if !Task.isCancelled && !WriteErrorMessage.isCancellation(error) { model.error = "Could not search files." }
            }
        }
    }
    private func select(_ item: ComposerSuggestion) {
        if let command = item.command {
            model.setText(AttributedString()); caret = 0
            switch command {
            case .model: showModels = true
            case .agent:
                let agents = ComposerPickers.agents(model.catalog.agents.value ?? [])
                if !agents.isEmpty { model.selectAgent(ComposerPickers.agentID(agents[((agents.firstIndex { ComposerPickers.agentID($0) == model.effectiveAgent } ?? -1) + 1) % agents.count])) }
            case .new: newSession()
            case .btw: insert("/btw ")
            default: clientCommand(command)
            }
        } else {
            var replacement = AttributedString(item.serverCommand.map { "/" + $0 } ?? (item.label.hasPrefix("@") ? item.label : "@" + item.label))
            replacement[MentionAttribute.self] = item.mention.map { .init(kind: $0.kind, value: $0.value) }
            replacement.append(AttributedString(" "))
            replaceTrigger(replacement)
        }
        suggestions = []; closedTrigger = trigger
    }
    private func replaceTrigger(_ replacement: AttributedString) {
        let plain = String(model.text.characters)
        var value = model.text
        if let trigger, let range = Range(trigger.range, in: plain), let a = AttributedString.Index(range.lowerBound, within: value), let b = AttributedString.Index(range.upperBound, within: value) {
            value.replaceSubrange(a..<b, with: replacement); caret = trigger.range.location + String(replacement.characters).utf16.count
        } else { value.append(replacement); caret = String(value.characters).utf16.count }
        model.setText(value)
    }
    private func insert(_ value: String) {
        closedTrigger = nil
        var text = model.text
        if !text.characters.isEmpty { text.append(AttributedString(" ")) }
        text.append(AttributedString(value)); caret = String(text.characters).utf16.count; model.setText(text)
    }
    private var commandState: ComposerCommandState {
        ComposerCommandState(loaded: model.loaded, busy: model.busy, blank: model.blank, running: running, shell: model.options.shell,
                             composing: composing, child: model.session?.info.parentID != nil,
                             hasVariants: model.selectedModel?.variants.contains { $0.id != "default" } == true,
                             sendTitle: running && !model.blank && !model.options.shell ? (followUp == "queue" ? "Steer" : "Queue") : "Send")
    }
    /// The menu bar's composer commands. ⌘↩ sends with the alternate delivery, as it did from the editor.
    private func perform(_ command: WorkspaceCommand) {
        switch command {
        case .send: send(alternate: true)
        case .stop: stop()
        case .chooseModel: showModels = true
        case .cycleVariant:
            let values = [String?](arrayLiteral: nil) + (model.selectedModel?.variants.filter { $0.id != "default" }.map { Optional($0.id) } ?? [])
            selectVariant(values[((values.firstIndex(of: model.effectiveModel?.variant) ?? 0) + 1) % values.count])
        case .addFiles: showFiles = true
        default: break
        }
    }
    private func handleKey(_ key: ComposerKey) -> Bool {
        #if DEBUG
        if key == .send || key == .escape { OCCommandTrace.shared.record(key == .send ? "key.return" : "key.escape") }
        #endif
        if trigger != nil && trigger != closedTrigger {
            switch key {
            case .escape: closedTrigger = trigger; return true
            case .up, .down:
                if !suggestions.isEmpty { active = (active + (key == .up ? -1 : 1) + suggestions.count) % suggestions.count }; return true
            case .send, .tab: if suggestions.indices.contains(active) { select(suggestions[active]) }; return true
            default: break
            }
        }
        if (key == .up || key == .down) && historyActive { return recall(older: key == .up) }
        switch key {
        case .send: send()
        case .escape:
            if model.options.shell { model.shellMode(false) } else if running { stop() }
        case .emptyBackspace: if model.options.shell { model.shellMode(false) } else { return false }
        case .menu(let command):
            // A menu key the text system would take first: run the menu's command here, once, or nothing when disabled.
            guard WorkspaceCommandRouter.composerAllows(command, commandState) else { return true }
            perform(command)
            #if DEBUG
            OCCommandTrace.shared.record("editor." + command.id)
            #endif
        default: return false
        }
        return true
    }
    private var promptEntries: [PromptHistory.Entry] { store.promptHistory(model.sessionID, directory: model.directory) }
    private var historyActive: Bool {
        !model.options.shell && (trigger == nil || trigger == closedTrigger) &&
            (historyCursor.index != nil || model.text.characters.isEmpty && caret == 0)
    }
    /// ↑ steps to older prompts, ↓ back towards the draft. The recalled text can be edited before sending.
    private func recall(older: Bool) -> Bool {
        let entries = promptEntries
        let text = older ? historyCursor.older(entries, current: String(model.text.characters)) : historyCursor.newer(entries)
        guard let text else { return older ? historyCursor.index != nil : false }
        model.setText(AttributedString(text)); caret = text.utf16.count
        return true
    }
    private func recallText(_ text: String) {
        historyCursor.reset(); model.setText(AttributedString(text)); caret = text.utf16.count; model.requestFocus()
    }
    private var gitAvailable: Bool {
        guard let session = model.session else { return false }
        if let vcs = store.projects.first(where: { $0.id == session.info.projectID })?.vcs { return vcs == "git" }
        let review = store.review(sessionID: session.id, directory: model.directory)
        return !review.providerKnown || review.vcs.provider != nil
    }
    private func sendGitAction(_ action: GitQuickAction) {
        run { try await model.sendAgentPrompt(action.prompt) }
    }
    @ViewBuilder private var voiceButton: some View {
        if model.session?.info.parentID == nil && !model.options.shell {
            Menu {
                Button("Dictate") { startVoice(.dictation) }
                Button("Hands-free conversation") { startVoice(.handsFree) }.disabled(model.sessionID == nil)
            } label: { OCIcon("waveform").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) } primaryAction: { startVoice(.dictation) }
                .accessibilityLabel("Voice input").accessibilityHint("Tap to dictate; hold for a hands-free conversation")
                .accessibilityIdentifier("composerVoice").disabled(model.busy || voice?.active == true)
        }
    }
    private func startVoice(_ mode: VoiceModel.Mode) {
        let voice = voice ?? VoiceModel(recognizer: DeviceSpeechRecognizer(), speaker: DeviceSpeaker())
        self.voice = voice
        voice.send = { text in await sendSpoken(text) }
        let files = model.session.map { session in store.review(sessionID: session.id, directory: model.directory).files.map(\.file) } ?? []
        let texts = model.session?.transcript.map { transcript in
            transcript.order.suffix(20).compactMap { transcript.messages[$0] }.map { $0.fields.type == "assistant" ? $0.items.map(\.text).joined(separator: "\n") : $0.fields.text }
        } ?? []
        let agents = (model.catalog.agents.value ?? []).map { ComposerPickers.agentID($0) }
        voice.start(mode, contextualStrings: VoiceVocabulary.strings(files: files + model.comments.map(\.file), texts: texts, agents: agents))
    }
    /// Dictation ends: the transcript joins the draft at the caret, ready to edit.
    private func insertDictation(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let plain = String(model.text.characters)
        let spaced = plain.isEmpty || plain.hasSuffix(" ") || plain.hasSuffix("\n") ? text : " " + text
        caret = model.insertText(spaced, atUTF16: caret)
    }
    /// Hands-free: sends the transcript, waits for the turn to end and returns the reply as plain text.
    private func sendSpoken(_ text: String) async -> String? {
        guard let sessionID = model.sessionID else { return nil }
        do {
            let id = try await store.sendPrompt(sessionID, input: PromptInput(text: text, delivery: running ? preference : .steer),
                                                prelude: WritePrelude(agent: model.options.agent, model: model.options.model))
            return try await store.reply(to: id, sessionID: sessionID)
        } catch { if !WriteErrorMessage.isCancellation(error) { model.error = WriteErrorMessage.message(error) }; return nil }
    }
    private func drop(_ provider: NSItemProvider) async throws {
        switch ComposerDrop.classify(provider.registeredTypeIdentifiers, named: provider.suggestedName) {
        case .mention:
            let data = try await ComposerMedia.data(provider, type: ComposerDrop.mentionType)
            if let path = ComposerDrop.mentionPath(data) { caret = model.mentionFile(path, atUTF16: caret) }
        case .attachment: try await importProvider(provider)
        case .text(let type):
            let data = try await ComposerMedia.data(provider, type: type)
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) { caret = model.insertText(text, atUTF16: caret) }
        case .refused: model.refuseDrop()
        }
    }
    private func stop() { if let id = model.sessionID { run { _ = try await store.interrupt(id, resume: true) } } }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        action?.cancel(); action = Task { do { try await work() } catch is CancellationError {} catch { model.error = WriteErrorMessage.message(error) } }
    }
    private func importFile(_ url: URL) async throws {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try await ComposerMedia.read(url)
        await model.addAttachment(data, mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", name: url.lastPathComponent)
    }
    private func importProvider(_ provider: NSItemProvider) async throws {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let data = try await ComposerMedia.data(provider, type: UTType.fileURL.identifier)
            if let url = URL(dataRepresentation: data, relativeTo: nil) { try await importFile(url); return }
        }
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true || UTType($0)?.conforms(to: .pdf) == true || UTType($0)?.conforms(to: .text) == true }
        guard let type else { return }
        let data = try await ComposerMedia.data(provider, type: type)
        await model.addAttachment(data, mime: UTType(type)?.preferredMIMEType ?? "text/plain", name: provider.suggestedName ?? "Attachment")
    }
}

private struct DraftAttachmentChip: View {
    let model: ComposerModel
    let file: ComposerAttachment
    @State private var url: URL?
    var body: some View {
        OCAttachmentChip(name: file.name, mime: file.mime, url: url) { model.removeAttachment(file.id) }
            .task { url = await model.attachmentURL(file) }
    }
}
#endif

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
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var editorLineHeight = OCType.lineHeight
    public init(store: ReadStore, model: ComposerModel, newSession: @escaping () -> Void = {},
                clientCommand: @escaping (ComposerCommand) -> Void = { _ in },
                start: (@MainActor (String, ModelRef?) async throws -> String)? = nil, opened: @escaping (String) -> Void = { _ in }) {
        self.store = store; self.model = model; self.newSession = newSession; self.clientCommand = clientCommand
        self.start = start; self.opened = opened
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
        .dropDestination(for: String.self) { paths, _ in
            for path in paths where path.hasPrefix("/") { model.mentionFile(path) }
            return paths.contains { $0.hasPrefix("/") }
        }
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
        .onDrop(of: [.fileURL, .image, .pdf, .text], isTargeted: nil) { providers in
            run { for provider in providers { try await importProvider(provider) } }; return true
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
            action?.cancel()
            if model.sessionID != nil && store.replacingDraftSessionID == model.sessionID { store.resolveDraftReplacement(false) }
        }
    }
    private var editorContent: some View {
        VStack(spacing: 0) {
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
            PromptEditor(text: Binding(get: { model.text }, set: { model.setText($0) }), caret: $caret,
                         shell: model.options.shell, enabled: model.loaded && !model.busy,
                         placeholder: placeholder,
                         suggestionsActive: trigger != nil && trigger != closedTrigger,
                         focusRequest: model.focusRequest,
                         pasteAttachment: { provider in run { try await importProvider(provider) } }, key: handleKey)
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
                    deliveryControls
                }
            } else {
                HStack(spacing: OCSpacing.xxs) { attachmentMenu; selectionControls; Spacer(minLength: 0); deliveryControls }
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
    private func handleKey(_ key: ComposerKey) -> Bool {
        if trigger != nil && trigger != closedTrigger {
            switch key {
            case .escape: closedTrigger = trigger; return true
            case .up, .down:
                if !suggestions.isEmpty { active = (active + (key == .up ? -1 : 1) + suggestions.count) % suggestions.count }; return true
            case .send, .tab: if suggestions.indices.contains(active) { select(suggestions[active]) }; return true
            default: break
            }
        }
        switch key {
        case .send: send()
        case .alternate: send(alternate: true)
        case .escape:
            if model.options.shell { model.shellMode(false) } else if running { stop() }
        case .emptyBackspace: if model.options.shell { model.shellMode(false) } else { return false }
        case .stop: stop()
        case .model: showModels = true
        case .variant:
            let values = [String?](arrayLiteral: nil) + (model.selectedModel?.variants.filter { $0.id != "default" }.map { Optional($0.id) } ?? [])
            selectVariant(values[((values.firstIndex(of: model.effectiveModel?.variant) ?? 0) + 1) % values.count])
        case .attach: showFiles = true
        case .newSession: newSession()
        default: return false
        }
        return true
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

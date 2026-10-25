#if os(iOS)
import SwiftUI
import Foundation
import OCDesign
import OCRender
import OCSync
import OCModels

public struct ToolRowView: View {
    let presentation: ToolPresentation
    let store: ReadStore?
    let directory: String
    let expanded: Bool
    let openChild: (String) -> Void
    @State private var shell = ShellOutputModel()
    @State private var visible = false
    @Environment(\.ocFileLinks) private var fileLinks
    @Environment(\.scenePhase) private var phase
    @Environment(\.timelineCellVisible) private var cellVisible
    public init(presentation: ToolPresentation, store: ReadStore? = nil, directory: String = "", expanded: Bool = false,
                openChild: @escaping (String) -> Void = { _ in }) {
        self.presentation = presentation; self.store = store; self.directory = directory; self.expanded = expanded; self.openChild = openChild
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.xs) {
            OCToolChrome(presentation.title, subtitle: presentation.subtitle, icon: presentation.icon, status: presentation.status,
                         badge: badge, failed: presentation.failed, expanded: expanded, inline: presentation.style == .explore, onOpen: openFile) { details }
            if let error = presentation.errorMessage {
                Text(error).font(OCType.small).foregroundStyle(OCColor.danger).ocSelectableText(error)
            }
            if let child = presentation.childID {
                Button { openChild(child) } label: { OCLabel("Open agent", icon: "subagent") }
                    .buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("openSubagent")
            }
        }
        .onScrollVisibilityChange(threshold: 0.01) {
            guard cellVisible == nil, presentation.style == .shell, visible != $0 else { return }
            visible = $0; updatePolling()
        }
        .onAppear { if let cellVisible { visible = cellVisible; updatePolling() } }
        .onChange(of: cellVisible) { _, value in if let value { visible = value; updatePolling() } }
        .onChange(of: phase) { _, _ in updatePolling() }
        .onChange(of: presentation.status) { _, _ in updatePolling() }
        .onChange(of: presentation.shellID) { _, _ in updatePolling() }
        .onDisappear { shell.stop() }
    }
    @ViewBuilder private var details: some View {
        switch presentation.style {
        case .diff:
            ForEach(Array(presentation.files.enumerated()), id: \.offset) { _, file in
                DiffCardView(file: file.file, patch: file.patch, additions: file.additions, deletions: file.deletions, expanded: expanded)
            }
            if presentation.files.isEmpty { genericDetails }
        case .addedFile: CodeBlockView(presentation.output, language: language(presentation.subtitle))
        case .shell:
            CodeBlockView(presentation.input, language: "bash")
            CodeBlockView(shell.output.isEmpty ? presentation.output : shell.output, language: "output", closed: !running)
            if let error = shell.error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
        case .links:
            ForEach(presentation.links, id: \.self) { url in
                Link(destination: url) { OCLabel(url.absoluteString, icon: "square-arrow-top-right").font(OCType.small).foregroundStyle(OCColor.accent) }
            }
            if presentation.links.isEmpty { genericDetails }
        case .execute:
            CodeBlockView(presentation.input, language: "typescript")
            ForEach(Array(presentation.nested.enumerated()), id: \.offset) { _, call in
                OCToolChrome(call.title, status: call.status, failed: call.failed) {
                    CodeBlockView(call.input, language: "json")
                    CodeBlockView(call.output)
                }
            }
            if !presentation.output.isEmpty { CodeBlockView(presentation.output) }
        case .question:
            Text(presentation.input).font(OCType.body).ocSelectableText(presentation.input)
            Text(presentation.output).font(OCType.small).foregroundStyle(OCColor.textMuted).ocSelectableText(presentation.output)
        default: genericDetails
        }
    }
    @ViewBuilder private var genericDetails: some View {
        if !presentation.input.isEmpty { CodeBlockView(presentation.input, language: "json") }
        if !presentation.output.isEmpty { CodeBlockView(presentation.output) }
    }
    /// Opens the file the tool acted on, when there is one and the host can show files.
    private var openFile: (() -> Void)? {
        guard let fileLinks, let path = presentation.path, !path.isEmpty else { return nil }
        return { fileLinks.open(path) }
    }
    private var running: Bool { ["running", "streaming", "pending"].contains(presentation.status) }
    private var badge: String? {
        guard presentation.style == .generic else { return presentation.badge }
        return [presentation.status.capitalized, presentation.badge].compactMap { $0 }.joined(separator: " · ")
    }
    private func updatePolling() {
        guard visible, phase == .active, let store, let id = presentation.shellID else { shell.stop(); return }
        shell.start(store: store, shellID: id, directory: directory, running: running)
    }
    private func bounded(_ number: Double) -> Int { number.isFinite && number >= 0 && number < Double(Int.max) ? Int(number) : 0 }
    private func language(_ path: String) -> String? { URL(fileURLWithPath: path).pathExtension }
}
#endif

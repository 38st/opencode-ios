// Sources: packages/gui-plugins/src/terminal/{panel,tab,label,terminal}.tsx and i18n/en.ts at v2.2.0.
#if os(iOS)
import SwiftUI
import OCModels
import OCSync
import OCDesign

/// One terminal: its status, what it could not show, and the terminal itself.
public struct TerminalScreen: View {
    let list: TerminalListModel
    let session: TerminalSession
    let showsHeader: Bool
    let autoFocus: Bool
    let back: (() -> Void)?
    let runCommand: () -> Void
    @AppStorage(TerminalSettings.fontSizeKey) private var fontSize = TerminalSettings.defaultFontSize
    @AppStorage(TerminalSettings.optionAsMetaKey) private var optionAsMeta = true
    @State private var engine: SwiftTermEngine?
    @State private var owner = UUID()
    @State private var closing = false
    @State private var renaming = false
    @State private var title = ""

    public init(list: TerminalListModel, session: TerminalSession, showsHeader: Bool, autoFocus: Bool = true,
                back: (() -> Void)? = nil, runCommand: @escaping () -> Void) {
        self.list = list; self.session = session; self.showsHeader = showsHeader; self.autoFocus = autoFocus
        self.back = back; self.runCommand = runCommand
    }
    public var body: some View {
        let phase = session.link.phase, status = TerminalStatusText.status(phase)
        VStack(spacing: 0) {
            if showsHeader { header }
            if let status, !TerminalStatusText.transient(phase) { banner(status) }
            if let gap = session.gap {
                HStack(alignment: .top) {
                    OCBanner(TerminalStatusText.gap(gap), tone: .warning)
                    OCIconButton("Dismiss", icon: "close") { session.gap = nil }
                }.padding(.horizontal, OCSpacing.sm).accessibilityIdentifier("terminalGap")
            }
            // A passing connection state floats over the terminal, so its size, and the program's, stay put.
            ZStack(alignment: .top) {
                if let engine { TerminalEngineView(engine: engine, focused: autoFocus) } else { Color.clear }
                if let status, TerminalStatusText.transient(phase) { banner(status).allowsHitTesting(false) }
            }
        }
        .background(OCColor.background)
        .navigationTitle(session.info?.title ?? "Terminal")
        .toolbar { if !showsHeader { ToolbarItem(placement: .topBarTrailing) { menu } } }
        .task(id: ObjectIdentifier(session)) { engine = TerminalEngines.shared.engine(for: session, fontSize: fontSize, optionAsMeta: optionAsMeta) }
        .onChange(of: fontSize) { engine?.update(fontSize: fontSize, optionAsMeta: optionAsMeta) }
        .onChange(of: optionAsMeta) { engine?.update(fontSize: fontSize, optionAsMeta: optionAsMeta) }
        .onChange(of: session.removedFromServer) { _, removed in if removed { TerminalEngines.shared.drop(session); back?() } }
        .focusedSceneValue(\.ocTerminalCommand, OCTerminalCommand(owner: owner, id: session.id) { requestClose() })
        .sheet(isPresented: $closing) {
            OCConfirmationSheet("Close \(session.info?.title ?? "terminal")?", message: "Its process is still running and will be stopped.",
                                confirmTitle: "Close terminal", cancel: { closing = false }) { closing = false; list.close(session.id) }.ocSheet()
        }
        .alert("Rename terminal", isPresented: $renaming) {
            TextField("Title", text: $title).accessibilityIdentifier("terminalTitleField")
            Button("Rename") { list.rename(session.id, title: title) }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func banner(_ status: String) -> some View {
        OCBanner(status, tone: session.link.phase == .gone ? .warning : .info).padding(OCSpacing.sm).accessibilityIdentifier("terminalStatus")
    }
    private var header: some View {
        HStack(spacing: OCSpacing.sm) {
            if let back { OCIconButton("All terminals", icon: "chevron-left", action: back).accessibilityIdentifier("terminalBack") }
            Text(session.info?.title ?? "Terminal").font(OCType.button).lineLimit(1)
            Spacer(minLength: 0)
            menu
        }.padding(.horizontal, OCSpacing.sm).frame(minHeight: OCLayout.touchTarget)
    }
    private var menu: some View {
        Menu {
            Button("Rename") { title = session.info?.title ?? ""; renaming = true }
            Button("Run a command", action: runCommand)
            Divider()
            Button("Close terminal", role: .destructive) { requestClose() }
        } label: { OCIcon("dot-grid").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
            .buttonStyle(.plain).accessibilityLabel("Terminal actions").accessibilityIdentifier("terminalActions")
    }
    /// Closing ends the process, so a running one asks first; an exited terminal closes at once.
    private func requestClose() {
        if session.info?.status == .running { closing = true } else { list.close(session.id) }
    }
}

enum TerminalStatusText {
    /// Connecting, catching up and reconnecting pass; an exit or a removal stays.
    static func transient(_ phase: TerminalLink.Phase) -> Bool {
        switch phase {
        case .idle, .connecting, .replaying, .waiting, .checking: true
        case .live, .suspended, .exited, .gone: false
        }
    }
    static func status(_ phase: TerminalLink.Phase) -> String? {
        switch phase {
        case .idle, .connecting: "Connecting…"
        case .replaying: "Catching up…"
        case .live, .suspended: nil
        case .waiting, .checking: "Connection lost. Reconnecting…"
        case .exited(let code?): code == 0 ? "The process exited." : "The process exited with code \(code)."
        case .exited(nil): "The process exited."
        case .gone: "This terminal was closed."
        }
    }
    static func gap(_ gap: TerminalGap) -> String {
        switch gap {
        case .lost(let units):
            "About \(units.formatted()) characters of output were lost while this terminal was disconnected: the server keeps only its latest 2 MiB."
        case .trimmed(let units): "The first \(units.formatted()) characters of output are no longer on the server."
        case .positionReset: "The server's output no longer matches this screen, so it was redrawn from what the server kept."
        case .skipped: "Output printed while this screen was saved is not shown."
        case .exitedWhileAway: "The process exited while this terminal was disconnected; output after the saved screen is not available."
        }
    }
}
#endif

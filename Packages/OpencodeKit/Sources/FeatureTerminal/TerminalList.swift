// Sources: packages/gui-plugins/src/terminal/{panel,model,label}.tsx at v2.2.0. Unlike the desktop, which keeps a tab
// per terminal it opened and drops one when it exits, the list is the server's: every terminal of the location,
// running or exited with its code, until it is closed.
#if os(iOS)
import SwiftUI
import OCModels
import OCSync
import OCDesign

public struct TerminalListView: View {
    let list: TerminalListModel
    let open: (PtyInfo) -> Void
    let runCommand: () -> Void
    @State private var renaming: PtyInfo?
    @State private var title = ""
    @State private var closing: PtyInfo?
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(list: TerminalListModel, open: @escaping (PtyInfo) -> Void, runCommand: @escaping () -> Void) {
        self.list = list; self.open = open; self.runCommand = runCommand
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OCSpacing.sm) {
                Text(localized("Terminals")).font(OCType.button).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                newMenu
                Menu {
                    Button(localized("Run a command"), action: runCommand).accessibilityIdentifier("runCommand")
                    Button(localized("Clear exited terminals")) { list.clearExited() }.disabled(!list.hasExited)
                } label: { OCIcon("dot-grid").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
                    .buttonStyle(.plain).accessibilityLabel(localized("More terminal actions")).accessibilityIdentifier("terminalListActions")
            }.padding(.horizontal, OCSpacing.md).frame(minHeight: OCLayout.touchTarget)
            if let error = list.error { OCBanner(error, tone: .danger).padding(.horizontal, OCSpacing.md) }
            if list.terminals.isEmpty {
                if list.loaded {
                    OCEmptyState(localized("No terminals"), detail: localized("Start a shell on your server in this folder."), icon: "terminal") {
                        Button(localized("New terminal")) { list.create() }.buttonStyle(OCButtonStyle(.contrast)).accessibilityIdentifier("newTerminalEmpty")
                    }
                } else { Spacer(); OCSpinner(localized("Loading terminals…")); Spacer() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list.terminals) { terminal in row(terminal) }
                    }.padding(.horizontal, OCSpacing.sm)
                }
            }
        }
        .background(OCColor.background)
        .onAppear { list.appear() }.onDisappear { list.disappear() }
        .alert(localized("Rename terminal"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(localized("Title", comment: "Placeholder for the terminal title field"), text: $title).accessibilityIdentifier("terminalTitleField")
            Button(localized("Rename")) { if let renaming { list.rename(renaming.id, title: title) } }
            Button(localized("Cancel"), role: .cancel) {}
        }
        .sheet(item: $closing) { terminal in
            OCConfirmationSheet(localized("Close \(terminal.title)?", comment: "%@ is the terminal title"), message: localized("Its process is still running and will be stopped."), confirmTitle: localized("Close terminal"),
                                cancel: { closing = nil }) { closing = nil; list.close(terminal.id) }.ocSheet()
        }
    }
    private var newMenu: some View {
        Menu {
            Button(localized("Default shell")) { list.create() }.accessibilityIdentifier("newTerminalDefault")
            if !list.shells.isEmpty {
                Section(localized("Shells")) { ForEach(list.shells) { shell in Button(shell.name) { list.create(shell: shell) } } }
            }
        } label: {
            if list.creating { ProgressView().frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
            else { OCIcon("plus").frame(width: OCLayout.touchTarget, height: OCLayout.touchTarget) }
        }.buttonStyle(.plain).disabled(list.creating).accessibilityLabel(localized("New terminal")).accessibilityIdentifier("newTerminal")
    }
    /// At the accessibility sizes the status moves under the text, which may wrap.
    private func row(_ terminal: PtyInfo) -> some View {
        let stacked = typeSize.isAccessibilitySize, lines = stacked ? 3 : 1
        return HStack(spacing: OCSpacing.sm) {
            Button { open(terminal) } label: {
                HStack(spacing: OCSpacing.md) {
                    if !stacked { OCIcon("terminal").foregroundStyle(OCColor.iconMuted) }
                    VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                        Text(terminal.title).font(OCType.button).foregroundStyle(OCColor.text).lineLimit(lines)
                        Text(terminal.commandLine).font(OCType.code).foregroundStyle(OCColor.textMuted).lineLimit(lines)
                        Text(terminal.cwd).font(OCType.micro).foregroundStyle(OCColor.textFaint).lineLimit(lines).truncationMode(.head)
                        if stacked { status(terminal) }
                    }
                    Spacer(minLength: 0)
                    if !stacked { status(terminal) }
                }.frame(minHeight: OCLayout.touchTarget).contentShape(Rectangle())
            }.buttonStyle(.plain).hoverEffect(.highlight)
                .accessibilityElement(children: .combine).accessibilityIdentifier("terminalRow-" + terminal.title)
            OCIconButton(localized("Close \(terminal.title)", comment: "%@ is the terminal title"), icon: "close") { terminal.status == .running ? (closing = terminal) : list.close(terminal.id) }
        }.padding(.vertical, OCSpacing.xs)
            .contextMenu {
                Button(localized("Open", comment: "Opens the terminal")) { open(terminal) }
                Button(localized("Rename")) { title = terminal.title; renaming = terminal }
                Button(localized("Close terminal"), role: .destructive) { terminal.status == .running ? (closing = terminal) : list.close(terminal.id) }
            }
    }
    @ViewBuilder private func status(_ terminal: PtyInfo) -> some View {
        switch terminal.status {
        case .running: OCPill(localized("Running", comment: "Terminal status"), tone: .success)
        case .exited:
            if let code = terminal.exitCode, code != 0 { OCPill(localized("Exited \(code)", comment: "Terminal status; %lld is the exit code"), tone: .danger) } else { OCPill(localized("Exited", comment: "Terminal status")) }
        case .unknown(let value): OCPill(value.isEmpty ? localized("Unknown") : value)
        }
    }
}

/// The review panel's Terminal tab: the list, or one terminal in its place. In a compact window the terminal opens
/// on its own screen instead.
public struct TerminalPanel: View {
    let list: TerminalListModel
    let shells: ShellRunModel
    let openCompact: ((String) -> Void)?
    @State private var running = false
    public init(list: TerminalListModel, shells: ShellRunModel, openCompact: ((String) -> Void)? = nil) {
        self.list = list; self.shells = shells; self.openCompact = openCompact
    }
    public var body: some View {
        Group {
            if openCompact == nil, let id = list.selected {
                TerminalScreen(list: list, session: list.session(id), showsHeader: true, back: { list.selected = nil }) { running = true }
                    .id(id)
            } else {
                TerminalListView(list: list, open: { terminal in
                    if let openCompact { openCompact(terminal.id) } else { list.selected = terminal.id }
                }) { running = true }
            }
        }.sheet(isPresented: $running) { RunCommandSheet(model: shells).ocSheet() }
    }
}

/// A location's terminals on their own screen (iPhone), each opening on a screen of its own.
public struct TerminalsScreen: View {
    let list: TerminalListModel
    let shells: ShellRunModel
    @Binding var open: String?
    @State private var running = false
    public init(list: TerminalListModel, shells: ShellRunModel, open: Binding<String?>) { self.list = list; self.shells = shells; _open = open }
    public var body: some View {
        TerminalListView(list: list, open: { open = $0.id }) { running = true }
            .navigationTitle(localized("Terminals")).navigationBarTitleDisplayMode(.inline)
            // A terminal started here opens at once, as the panel shows it.
            .onChange(of: list.selected) { _, id in if let id { open = id; list.selected = nil } }
            .navigationDestination(item: $open) { id in
                TerminalScreen(list: list, session: list.session(id), showsHeader: false, back: { open = nil }) { running = true }
            }
            .sheet(isPresented: $running) { RunCommandSheet(model: shells).ocSheet() }
    }
}
#endif

// Sources: packages/app/src/shell/commands/{command.tsx,desktop-menu.ts}. The menu bar owns every app shortcut:
// each item reads the key window's focused values, so it acts on that window's session, and is disabled where it
// does not apply. Holding ⌘ lists every item by name.
#if os(iOS)
import SwiftUI
import OCModels
import OCDesign

public struct WorkspaceCommands: Commands {
    @FocusedValue(\.ocWindowCommands) private var window
    @FocusedValue(\.ocComposerCommands) private var composer
    @FocusedValue(\.ocFindCommand) private var find
    @FocusedValue(\.ocCommenting) private var commenting
    @FocusedValue(\.ocTerminalCommand) private var terminal
    public init() {}
    public var body: some Commands {
        #if DEBUG
        let _ = { OCCommandTrace.shared.menuEnabled = WorkspaceCommand.all.filter(enabled).map(\.id) }()
        #endif
        CommandGroup(replacing: .newItem) {
            item(.newSession); item(.newWindow)
            Divider()
            item(.addFiles)
        }
        CommandGroup(replacing: .textEditing) { item(.find) }
        // The prompt has no rich text: the Format menu's ⌘B, ⌘I and ⌘U would do nothing, and ⌘U adds files.
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .sidebar) {
            item(.toggleSidebar); item(.toggleReview)
            Divider()
            item(.commandPalette)
        }
        CommandMenu(WorkspaceMenu.session.rawValue) {
            item(.send); item(.stop)
            Divider()
            item(.reviewNextApproval)
            Divider()
            item(.previousSession); item(.nextSession); item(.previousUnread); item(.nextUnread)
            Divider()
            ForEach(1...9, id: \.self) { item(.session($0)) }
        }
        CommandMenu(WorkspaceMenu.model.rawValue) {
            item(.chooseModel); item(.cycleVariant)
        }
        CommandMenu(WorkspaceMenu.terminal.rawValue) {
            item(.newTerminal); item(.closeTerminal)
        }
    }
    private var composerState: ComposerCommandState? {
        composer.map { var state = $0.state; state.commenting = commenting ?? false; return state }
    }
    private func enabled(_ command: WorkspaceCommand) -> Bool {
        WorkspaceCommandRouter.isEnabled(command, window: window?.state, composer: composerState, find: find != nil, terminal: terminal != nil)
    }
    private func item(_ command: WorkspaceCommand) -> some View {
        Button(title(command)) { run(command) }
            .keyboardShortcut(command.menuOwnsKey ? command.chord.keyboardShortcut : nil)
            .disabled(!enabled(command))
    }
    private func title(_ command: WorkspaceCommand) -> String {
        switch command {
        case .send: composer?.state.sendTitle ?? command.title
        case .session(let index):
            window?.state.sessionTitles.indices.contains(index - 1) == true ? window?.state.sessionTitles[index - 1] ?? command.title : command.title
        default: command.title
        }
    }
    private func run(_ command: WorkspaceCommand) {
        let performed = WorkspaceCommandRouter.perform(command, window: window?.state, composer: composerState, find: find != nil, terminal: terminal != nil,
            windowAction: { window?.perform($0) }, composerAction: { composer?.perform($0) }, findAction: { find?.perform() },
            terminalAction: { terminal?.perform() })
        #if DEBUG
        if performed { OCCommandTrace.shared.record("menu." + command.id) }
        #else
        _ = performed
        #endif
    }
}
#endif

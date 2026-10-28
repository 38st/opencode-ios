// Sources: packages/app/src/shell/commands/{command.tsx,desktop-menu.ts,palette.ts}, settings/keybinds/,
// shell/titlebar/{tab-strip,tab-order}.ts, composer/{commands.tsx,model.ts}. Titles follow the desktop's
// strings; keys follow the iPad shortcut table, with the desktop's keys for the rows it does not cover.
import Foundation

/// A key and its modifiers, as the menu bar renders it and the key-ownership checks compare it.
public struct KeyChord: Hashable, Sendable, CustomStringConvertible {
    public enum Key: Hashable, Sendable { case character(Character), `return`, escape, tab, up, down, left, right }
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }
    public var key: Key
    public var modifiers: Modifiers
    public init(_ key: Key, _ modifiers: Modifiers = []) { self.key = key; self.modifiers = modifiers }
    public init(_ character: Character, _ modifiers: Modifiers = .command) {
        self.init(.character(Character(character.lowercased())), modifiers)
    }
    /// Apple's order: ⌃ ⌥ ⇧ ⌘, then the key.
    public var description: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        switch key {
        case .character(let character): value += character.uppercased()
        case .return: value += "↩"
        case .escape: value += "⎋"
        case .tab: value += "⇥"
        case .up: value += "↑"
        case .down: value += "↓"
        case .left: value += "←"
        case .right: value += "→"
        }
        return value
    }
}

/// The menus, in the desktop's command categories.
public enum WorkspaceMenu: String, CaseIterable, Sendable { case file = "File", edit = "Edit", view = "View", session = "Session", model = "Model" }

public enum WorkspaceCommand: Hashable, Sendable {
    case newSession, newWindow, addFiles
    case find
    case toggleSidebar, toggleReview, commandPalette
    case send, stop, reviewNextApproval, previousSession, nextSession, previousUnread, nextUnread
    /// The Nth session in Home's order, 1 to 9.
    case session(Int)
    case chooseModel, cycleVariant

    public static let all: [WorkspaceCommand] = [.newSession, .newWindow, .addFiles, .find, .toggleSidebar, .toggleReview, .commandPalette,
        .send, .stop, .reviewNextApproval, .previousSession, .nextSession, .previousUnread, .nextUnread]
        + (1...9).map(WorkspaceCommand.session) + [.chooseModel, .cycleVariant]
    /// The desktop's command ID where it has one.
    public var id: String {
        switch self {
        case .newSession: "session.new"
        case .newWindow: "window.new"
        case .addFiles: "file.attach"
        case .find: "session.find"
        case .toggleSidebar: "sidebar.toggle"
        case .toggleReview: "review.toggle"
        case .commandPalette: "command.palette"
        case .send: "prompt.submit"
        case .stop: "session.stop"
        case .reviewNextApproval: "permissions.next"
        case .previousSession: "session.previous"
        case .nextSession: "session.next"
        case .previousUnread: "session.previous.unseen"
        case .nextUnread: "session.next.unseen"
        case .session(let index): "session.\(index)"
        case .chooseModel: "model.choose"
        case .cycleVariant: "model.variant.cycle"
        }
    }
    public var title: String {
        switch self {
        case .newSession: "New session"
        case .newWindow: "New Window"
        case .addFiles: "Add files"
        case .find: "Find"
        case .toggleSidebar: "Toggle sidebar"
        case .toggleReview: "Toggle review"
        case .commandPalette: "Command palette"
        case .send: "Send"
        case .stop: "Stop"
        case .reviewNextApproval: "Review next approval"
        case .previousSession: "Previous session"
        case .nextSession: "Next session"
        case .previousUnread: "Previous unread session"
        case .nextUnread: "Next unread session"
        case .session(let index): "Session \(index)"
        case .chooseModel: "Choose model"
        case .cycleVariant: "Cycle thinking effort"
        }
    }
    public var menu: WorkspaceMenu {
        switch self {
        case .newSession, .newWindow, .addFiles: .file
        case .find: .edit
        case .toggleSidebar, .toggleReview, .commandPalette: .view
        case .send, .stop, .reviewNextApproval, .previousSession, .nextSession, .previousUnread, .nextUnread, .session: .session
        case .chooseModel, .cycleVariant: .model
        }
    }
    /// Whether the menu item carries the key. A menu item's ⌘F does not run on iPadOS, whose own Edit ▸ Find menu
    /// carries the same key, so the Files viewer's Find button owns ⌘F while the viewer shows a text file
    /// (`WorkspaceKeys.local(.filesViewer)`) and the menu's Find runs the same Find without repeating the key.
    public var menuOwnsKey: Bool { self != .find }
    public var chord: KeyChord {
        switch self {
        case .newSession: KeyChord("n")
        case .newWindow: KeyChord("n", [.command, .shift])
        case .addFiles: KeyChord("u")
        case .find: KeyChord("f")
        case .toggleSidebar: KeyChord("\\")
        case .toggleReview: KeyChord("r", [.command, .shift])
        case .commandPalette: KeyChord("k")
        case .send: KeyChord(.return, .command)
        case .stop: KeyChord(".")
        case .reviewNextApproval: KeyChord("a", [.command, .shift])
        // The desktop's ⌥↑ and ⌥↓ (with ⇧ for unread) move or extend the caret by paragraph in an iPadOS text view,
        // which takes them ahead of the menu, so these keys add ⌘: neither text views nor iPadOS use them.
        case .previousSession: KeyChord(.up, [.option, .command])
        case .nextSession: KeyChord(.down, [.option, .command])
        case .previousUnread: KeyChord(.up, [.option, .shift, .command])
        case .nextUnread: KeyChord(.down, [.option, .shift, .command])
        case .session(let index): KeyChord(Character(String(index)))
        case .chooseModel: KeyChord("'")
        case .cycleVariant: KeyChord("d", [.command, .shift])
        }
    }
}

/// Keys that belong to a focused view rather than the menu bar, and keys the system keeps.
public enum WorkspaceKeys {
    public enum Scope: String, CaseIterable, Sendable { case promptEditor, commentEditor, codeList, commandPalette, filesViewer }
    /// The views build their key commands from these, so the ownership checks cover what ships.
    public enum PromptEditor {
        public static let send = KeyChord(.return), escape = KeyChord(.escape)
        /// Live only while the suggestions show.
        public static let up = KeyChord(.up), down = KeyChord(.down), accept = KeyChord(.tab)
        public static let next = KeyChord("n", .control), previous = KeyChord("p", .control)
        public static let suggestions = [up, down, accept, next, previous]
    }
    public enum CommentEditor { public static let submit = KeyChord(.return), cancel = KeyChord(.escape) }
    public enum CodeList { public static let previous = KeyChord(.left), next = KeyChord(.right) }
    public enum Palette {
        public static let up = KeyChord(.up), down = KeyChord(.down), cancel = KeyChord(.escape)
        /// Return reaches the field's delegate; ⌥↩ opens the entry in a new window.
        public static let open = KeyChord(.return), openInNewWindow = KeyChord(.return, .option)
    }
    public enum FilesViewer { public static let find = WorkspaceCommand.find.chord }
    /// Each scope's keys are live only while that view is the first responder; the Files viewer's while it shows a
    /// text file.
    public static func local(_ scope: Scope) -> [KeyChord] {
        switch scope {
        case .promptEditor: [PromptEditor.send, PromptEditor.escape] + PromptEditor.suggestions
        case .commentEditor: [CommentEditor.submit, CommentEditor.cancel]
        case .codeList: [CodeList.previous, CodeList.next]
        case .commandPalette: [Palette.up, Palette.down, Palette.open, Palette.openInNewWindow, Palette.cancel]
        case .filesViewer: [FilesViewer.find]
        }
    }
    /// Menu keys a focused view takes first and forwards to the menu's own command, which then runs once. UIKit gives
    /// Return chords in a text view to its text system ahead of a menu item, and SwiftUI's menu items cannot ask for
    /// priority (`UIKeyCommand.wantsPriorityOverSystemBehavior`), so the prompt editor forwards ⌘↩ to Send.
    public static func forwarded(_ scope: Scope) -> [WorkspaceCommand] {
        switch scope {
        case .promptEditor: [.send]
        case .commentEditor, .codeList, .commandPalette, .filesViewer: []
        }
    }
    /// iPadOS and its text system keep these: app switching, screenshots, the Dock, Spotlight, the pasteboard, undo,
    /// selection and window commands. The Format menu's ⌘B, ⌘I and ⌘U are removed by the menu bar, which has no
    /// rich text to format, so ⌘U can add files as on the desktop.
    public static let reserved: [KeyChord] = [
        KeyChord("h"), KeyChord(" "), KeyChord(.tab, .command), KeyChord("3", [.command, .shift]), KeyChord("4", [.command, .shift]),
        KeyChord("5", [.command, .shift]), KeyChord("d", [.command, .option]), KeyChord("c"), KeyChord("x"), KeyChord("v"),
        KeyChord("z"), KeyChord("z", [.command, .shift]), KeyChord("a"), KeyChord("w"), KeyChord("q"), KeyChord("m"),
        KeyChord("g"), KeyChord("g", [.command, .shift]), KeyChord("e"),
    ]
}

/// What the key window offers the menu bar. Values only: the menu decides from these, then calls the window.
public struct WindowCommandState: Equatable, Sendable {
    /// A palette, Settings or a sheet is up: the desktop suspends its keybinds while a dialog is active.
    public var modal = false
    public var loaded = false
    public var canCreateSession = false
    public var supportsWindows = false
    public var sidebarAvailable = false
    /// The window's open session, by its root.
    public var current: SessionRef?
    /// Home's root sessions in Home's order, with their titles for the ⌘1–9 items.
    public var sessions: [SessionRef] = []
    public var sessionTitles: [String] = []
    /// IDs (`SessionRef.id`) of the sessions with unread output.
    public var unread: Set<String> = []
    /// Pending permissions and questions, in Home's order, each as the session and request to open.
    public var approvals: [SessionRef] = []
    public var openRequest: String?
    public init(modal: Bool = false, loaded: Bool = false, canCreateSession: Bool = false, supportsWindows: Bool = false,
                sidebarAvailable: Bool = false, current: SessionRef? = nil, sessions: [SessionRef] = [], sessionTitles: [String] = [],
                unread: Set<String> = [], approvals: [SessionRef] = [], openRequest: String? = nil) {
        self.modal = modal; self.loaded = loaded; self.canCreateSession = canCreateSession; self.supportsWindows = supportsWindows
        self.sidebarAvailable = sidebarAvailable; self.current = current; self.sessions = sessions; self.sessionTitles = sessionTitles
        self.unread = unread; self.approvals = approvals; self.openRequest = openRequest
    }
}
/// What the focused window's composer offers.
public struct ComposerCommandState: Equatable, Sendable {
    public var loaded = false
    public var busy = false
    public var blank = true
    public var running = false
    public var shell = false
    /// An input method holds marked text: the composition owns the keyboard.
    public var composing = false
    public var child = false
    /// A line comment is being written; ⌘↩ must not send the prompt behind it.
    public var commenting = false
    public var hasVariants = false
    /// "Send" while idle; while running ⌘↩ uses the other delivery, so the menu names it.
    public var sendTitle = "Send"
    public init(loaded: Bool = false, busy: Bool = false, blank: Bool = true, running: Bool = false, shell: Bool = false,
                composing: Bool = false, child: Bool = false, commenting: Bool = false, hasVariants: Bool = false, sendTitle: String = "Send") {
        self.loaded = loaded; self.busy = busy; self.blank = blank; self.running = running; self.shell = shell
        self.composing = composing; self.child = child; self.commenting = commenting; self.hasVariants = hasVariants; self.sendTitle = sendTitle
    }
}

public enum WorkspaceCommandRouter {
    public enum Target: Equatable, Sendable { case window, composer, find }
    public static func target(_ command: WorkspaceCommand) -> Target {
        switch command {
        case .send, .stop, .addFiles, .chooseModel, .cycleVariant: .composer
        case .find: .find
        default: .window
        }
    }
    public static func isEnabled(_ command: WorkspaceCommand, window: WindowCommandState?, composer: ComposerCommandState?, find: Bool) -> Bool {
        guard let window, window.loaded, !window.modal else { return false }
        switch command {
        case .newSession: return window.canCreateSession
        case .newWindow: return window.supportsWindows
        case .commandPalette: return true
        case .toggleSidebar: return window.sidebarAvailable
        case .toggleReview: return window.current != nil
        case .find: return find
        case .reviewNextApproval: return nextApproval(window) != nil
        case .previousSession, .nextSession, .previousUnread, .nextUnread, .session: return session(command, window: window) != nil
        case .send, .stop, .addFiles, .chooseModel, .cycleVariant: return composer.map { composerAllows(command, $0) } ?? false
        }
    }
    /// The composer's rules alone, for a key its editor forwards: while the editor is first responder the window is
    /// loaded and no dialog is up.
    public static func composerAllows(_ command: WorkspaceCommand, _ composer: ComposerCommandState) -> Bool {
        switch command {
        case .send: composer.loaded && !composer.busy && !composer.composing && !composer.child && !composer.commenting && !composer.blank
        case .stop: !composer.composing && !composer.child && composer.running
        case .addFiles, .chooseModel, .cycleVariant:
            composer.loaded && !composer.busy && !composer.shell && !composer.composing && !composer.child && (command != .cycleVariant || composer.hasVariants)
        default: false
        }
    }
    /// The session a navigation command opens.
    public static func session(_ command: WorkspaceCommand, window: WindowCommandState) -> SessionRef? {
        let ids = window.sessions.map(\.id)
        let key: String?
        switch command {
        case .session(let index): return (1...9).contains(index) && index <= window.sessions.count ? window.sessions[index - 1] : nil
        case .previousSession: key = adjacent(ids, current: window.current?.id, offset: -1)
        case .nextSession: key = adjacent(ids, current: window.current?.id, offset: 1)
        case .previousUnread: key = adjacent(ids, current: window.current?.id, offset: -1) { window.unread.contains($0) }
        case .nextUnread: key = adjacent(ids, current: window.current?.id, offset: 1) { window.unread.contains($0) }
        default: return nil
        }
        return key.flatMap { key in window.sessions.first { $0.id == key } }
    }
    /// The request after the one the window shows, wrapping; the first one otherwise.
    public static func nextApproval(_ window: WindowCommandState) -> SessionRef? {
        guard !window.approvals.isEmpty else { return nil }
        guard let open = window.openRequest, let index = window.approvals.firstIndex(where: { $0.requestID == open }) else { return window.approvals[0] }
        return window.approvals.count > 1 ? window.approvals[(index + 1) % window.approvals.count] : nil
    }
    /// The nearest accepted key in either direction, wrapping; nil without a current key (desktop `adjacentTabKey`).
    public static func adjacent(_ order: [String], current: String?, offset: Int, include: (String) -> Bool = { _ in true }) -> String? {
        guard let current, let index = order.firstIndex(of: current), order.count > 1 else { return nil }
        return (1..<order.count).lazy.map { order[(index + offset * $0 + order.count) % order.count] }.first(where: include)
    }
    /// Calls the one target that owns the command, and nothing when it is disabled.
    @discardableResult
    public static func perform(_ command: WorkspaceCommand, window: WindowCommandState?, composer: ComposerCommandState?, find: Bool,
                               windowAction: (WorkspaceCommand) -> Void, composerAction: (WorkspaceCommand) -> Void, findAction: () -> Void) -> Bool {
        guard isEnabled(command, window: window, composer: composer, find: find) else { return false }
        switch target(command) {
        case .window: windowAction(command)
        case .composer: composerAction(command)
        case .find: findAction()
        }
        return true
    }
}

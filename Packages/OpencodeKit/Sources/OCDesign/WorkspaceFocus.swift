// What the key window offers the menu bar. Each window publishes its own targets as focused scene values, so a
// command always acts on the key window's session. The menu only reads the values; the router decides.
#if os(iOS)
import SwiftUI
import UIKit
import OCModels

/// A window's commands. Equality includes the window, so the menu never keeps another window's action.
public struct OCWindowCommands: Equatable {
    public var window: UUID
    public var state: WindowCommandState
    public var perform: @MainActor (WorkspaceCommand) -> Void
    public init(window: UUID, state: WindowCommandState, perform: @escaping @MainActor (WorkspaceCommand) -> Void) {
        self.window = window; self.state = state; self.perform = perform
    }
    /// The action reads live state when it runs, so the same window with an equal state needs no new menu.
    public static func == (a: Self, b: Self) -> Bool { a.window == b.window && a.state == b.state }
}
/// A composer's commands. `owner` names the composer on screen and `session` its session, so two composers with equal
/// states, in two sessions or two windows, are never mistaken for each other.
public struct OCComposerCommands: Equatable {
    public var owner: UUID
    public var session: String?
    public var state: ComposerCommandState
    public var perform: @MainActor (WorkspaceCommand) -> Void
    public init(owner: UUID, session: String?, state: ComposerCommandState, perform: @escaping @MainActor (WorkspaceCommand) -> Void) {
        self.owner = owner; self.session = session; self.state = state; self.perform = perform
    }
    public static func == (a: Self, b: Self) -> Bool { a.owner == b.owner && a.session == b.session && a.state == b.state }
}
/// Find in the focused file viewer: `owner` names the viewer, `id` the file.
public struct OCFindCommand: Equatable {
    public var owner: UUID
    public var id: String
    public var perform: @MainActor () -> Void
    public init(owner: UUID, id: String, perform: @escaping @MainActor () -> Void) { self.owner = owner; self.id = id; self.perform = perform }
    public static func == (a: Self, b: Self) -> Bool { a.owner == b.owner && a.id == b.id }
}
public extension KeyChord {
    /// The UIKit key command input for the key.
    var keyCommandInput: String {
        switch key {
        case .character(let character): String(character)
        case .return: "\r"
        case .escape: UIKeyCommand.inputEscape
        case .tab: "\t"
        case .up: UIKeyCommand.inputUpArrow
        case .down: UIKeyCommand.inputDownArrow
        case .left: UIKeyCommand.inputLeftArrow
        case .right: UIKeyCommand.inputRightArrow
        }
    }
    var keyCommandFlags: UIKeyModifierFlags {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.alternate) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
    /// Whether a fired key command is this chord.
    func matches(_ command: UIKeyCommand) -> Bool { command.input == keyCommandInput && command.modifierFlags == keyCommandFlags }
    /// A key command for this chord that runs ahead of the text system's own keys.
    func keyCommand(_ action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(input: keyCommandInput, modifierFlags: keyCommandFlags, action: action)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
    /// The SwiftUI shortcut for a menu item or a button.
    var keyboardShortcut: KeyboardShortcut {
        let key: KeyEquivalent = switch self.key {
        case .character(let character): KeyEquivalent(character)
        case .return: .return
        case .escape: .escape
        case .tab: .tab
        case .up: .upArrow
        case .down: .downArrow
        case .left: .leftArrow
        case .right: .rightArrow
        }
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(key, modifiers: modifiers)
    }
}
public extension View {
    /// Runs `action` for a chord from the key table while this view has focus. Only the chord's own modifiers match,
    /// so the text field keeps the rest (Shift-arrow selection, for example).
    func ocKeyPress(_ chord: KeyChord, action: @escaping () -> Void) -> some View {
        let shortcut = chord.keyboardShortcut
        return onKeyPress(keys: [shortcut.key]) { press in
            guard press.modifiers.intersection([.command, .shift, .option, .control]) == shortcut.modifiers else { return .ignored }
            action()
            return .handled
        }
    }
}
/// Close terminal for the terminal on screen: `owner` names the terminal view, `id` its PTY.
public struct OCTerminalCommand: Equatable {
    public var owner: UUID
    public var id: String
    public var perform: @MainActor () -> Void
    public init(owner: UUID, id: String, perform: @escaping @MainActor () -> Void) { self.owner = owner; self.id = id; self.perform = perform }
    public static func == (a: Self, b: Self) -> Bool { a.owner == b.owner && a.id == b.id }
}
public extension FocusedValues {
    @Entry var ocTerminalCommand: OCTerminalCommand?
    @Entry var ocWindowCommands: OCWindowCommands?
    @Entry var ocComposerCommands: OCComposerCommands?
    @Entry var ocFindCommand: OCFindCommand?
    /// A line comment is being written in this window.
    @Entry var ocCommenting: Bool?
}

#if DEBUG
/// UI tests count performed commands at their single dispatch points, proving that one key press runs one action.
@MainActor @Observable public final class OCCommandTrace {
    public static let shared = OCCommandTrace()
    public private(set) var counts: [String: Int] = [:]
    /// The menu items the menu bar enabled when it last read the key window's commands.
    @ObservationIgnored public var menuEnabled: [String] = []
    @ObservationIgnored private let enabled = ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"] != nil
    public func record(_ id: String) { if enabled { counts[id, default: 0] += 1 } }
    public var summary: String { counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") }
}
#endif
#endif

import Foundation
import Testing
import OCModels

@Test func everyKeyHasOneOwner() {
    let menu = WorkspaceCommand.all.filter(\.menuOwnsKey).map(\.chord)
    #expect(WorkspaceCommand.all.filter { !$0.menuOwnsKey } == [.find], "Only Find leaves its key to a view")
    #expect(WorkspaceKeys.local(.filesViewer) == [WorkspaceCommand.find.chord], "The Files viewer owns ⌘F")
    #expect(WorkspaceKeys.local(.filesFilter) == [KeyChord(.up), KeyChord(.down), KeyChord(.escape)], "The Files filter's keys come from the table")
    #expect(Set(menu).count == menu.count, "Two menu commands share a key")
    let reserved = Set(WorkspaceKeys.reserved)
    #expect(Set(menu).isDisjoint(with: reserved), "A menu command takes a key iPadOS keeps")
    for scope in WorkspaceKeys.Scope.allCases {
        let local = WorkspaceKeys.local(scope)
        #expect(Set(local).count == local.count, "\(scope) registers a key twice")
        #expect(Set(local).isDisjoint(with: menu), "\(scope) also owns a menu key")
        #expect(Set(local).isDisjoint(with: reserved))
        // A forwarded key stays the menu command's own: the view runs that command, never an action of its own.
        let forwarded = WorkspaceKeys.forwarded(scope)
        #expect(forwarded.allSatisfy { WorkspaceCommand.all.contains($0) && !local.contains($0.chord) }, "\(scope) forwards a key it also owns")
    }
    #expect(WorkspaceKeys.forwarded(.promptEditor) == [.send])
    #expect(Set(WorkspaceCommand.all.map(\.title)).count == WorkspaceCommand.all.count)
    #expect(Set(WorkspaceCommand.all.map(\.id)).count == WorkspaceCommand.all.count)
    #expect(WorkspaceCommand.all.allSatisfy { !$0.title.isEmpty })
}

@Test func theIPadShortcutTableIsCovered() {
    let expected: [(WorkspaceCommand, String)] = [(.newSession, "⌘N"), (.send, "⌘↩"), (.stop, "⌘."), (.commandPalette, "⌘K"), (.find, "⌘F"),
        (.chooseModel, "⌘'"), (.reviewNextApproval, "⇧⌘A"), (.session(1), "⌘1"), (.session(9), "⌘9"), (.toggleSidebar, "⌘\\"),
        (.toggleReview, "⇧⌘R"), (.previousSession, "⌥⌘↑"), (.nextSession, "⌥⌘↓"), (.previousUnread, "⌥⇧⌘↑"), (.nextUnread, "⌥⇧⌘↓"),
        (.newWindow, "⇧⌘N"), (.addFiles, "⌘U"), (.cycleVariant, "⇧⌘D")]
    for (command, shortcut) in expected { #expect(command.chord.description == shortcut, "\(command)") }
    #expect(WorkspaceCommand.all.count == expected.count + 7)
    #expect(KeyChord(.return, [.command, .shift, .option, .control]).description == "⌃⌥⇧⌘↩")
}

private let server = ServerID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
private func ref(_ id: String, request: String? = nil) -> SessionRef { SessionRef(serverID: server, sessionID: id, requestID: request) }

@Test func commandsNeedAWindowAndPauseWhileADialogIsUp() {
    let composer = ComposerCommandState(loaded: true, blank: false)
    let modal = WindowCommandState(modal: true, loaded: true), loading = WindowCommandState(loaded: false), ready = WindowCommandState(loaded: true)
    #expect(!WorkspaceCommandRouter.isEnabled(.send, window: nil, composer: composer, find: false))
    #expect(!WorkspaceCommandRouter.isEnabled(.send, window: modal, composer: composer, find: false))
    #expect(!WorkspaceCommandRouter.isEnabled(.commandPalette, window: loading, composer: nil, find: false))
    #expect(WorkspaceCommandRouter.isEnabled(.send, window: ready, composer: composer, find: false))
    #expect(WorkspaceCommandRouter.isEnabled(.commandPalette, window: ready, composer: nil, find: false))
}

@Test func composerCommandsFollowTheComposerState() {
    let window = WindowCommandState(loaded: true)
    func enabled(_ command: WorkspaceCommand, _ composer: ComposerCommandState?) -> Bool {
        WorkspaceCommandRouter.isEnabled(command, window: window, composer: composer, find: false)
    }
    let ready = ComposerCommandState(loaded: true, blank: false)
    #expect(enabled(.send, ready))
    #expect(!enabled(.send, ComposerCommandState(loaded: true, blank: true)), "Send with an empty composer")
    #expect(!enabled(.send, ComposerCommandState(loaded: true, busy: true, blank: false)))
    #expect(!enabled(.send, ComposerCommandState(loaded: false, blank: false)))
    #expect(!enabled(.send, ComposerCommandState(loaded: true, blank: false, composing: true)), "The input method owns the keyboard")
    #expect(!enabled(.send, ComposerCommandState(loaded: true, blank: false, child: true)), "Subagents are read only")
    #expect(!enabled(.send, ComposerCommandState(loaded: true, blank: false, commenting: true)), "⌘↩ belongs to the comment editor")
    #expect(!enabled(.send, nil))
    #expect(!enabled(.stop, ComposerCommandState(loaded: true)), "Stop while idle")
    #expect(enabled(.stop, ComposerCommandState(loaded: true, running: true)))
    #expect(enabled(.stop, ComposerCommandState(loaded: true, blank: false, running: true)))
    #expect(!enabled(.stop, ComposerCommandState(loaded: true, running: true, composing: true)))
    #expect(enabled(.chooseModel, ready) && enabled(.addFiles, ready))
    #expect(!enabled(.chooseModel, ComposerCommandState(loaded: true, shell: true)))
    #expect(!enabled(.addFiles, ComposerCommandState(loaded: true, busy: true)))
    #expect(!enabled(.cycleVariant, ready))
    #expect(enabled(.cycleVariant, ComposerCommandState(loaded: true, hasVariants: true)))
    // The editor's forwarded ⌘↩ follows the same rules, without a window: its editor is first responder.
    #expect(WorkspaceCommandRouter.composerAllows(.send, ready) && !WorkspaceCommandRouter.composerAllows(.send, ComposerCommandState(loaded: true, blank: true)))
    #expect(!WorkspaceCommandRouter.composerAllows(.newSession, ready), "Window commands are not the composer's")
}

@Test func windowCommandsFollowTheWindowState() {
    func enabled(_ command: WorkspaceCommand, _ window: WindowCommandState, find: Bool = false) -> Bool {
        WorkspaceCommandRouter.isEnabled(command, window: window, composer: nil, find: find)
    }
    #expect(!enabled(.find, .init(loaded: true)), "Find where nothing can be searched")
    #expect(enabled(.find, .init(loaded: true), find: true))
    #expect(!enabled(.newSession, .init(loaded: true)) && enabled(.newSession, .init(loaded: true, canCreateSession: true)))
    #expect(!enabled(.newWindow, .init(loaded: true)) && enabled(.newWindow, .init(loaded: true, supportsWindows: true)))
    #expect(!enabled(.toggleSidebar, .init(loaded: true)) && enabled(.toggleSidebar, .init(loaded: true, sidebarAvailable: true)))
    #expect(!enabled(.toggleReview, .init(loaded: true)) && enabled(.toggleReview, .init(loaded: true, current: ref("a"))))
    #expect(!enabled(.reviewNextApproval, .init(loaded: true)), "Nothing pending")
    #expect(enabled(.reviewNextApproval, .init(loaded: true, approvals: [ref("a", request: "per_1")])))
    let three = WindowCommandState(loaded: true, sessions: [ref("a"), ref("b"), ref("c")])
    #expect(enabled(.session(1), three) && enabled(.session(3), three))
    #expect(!enabled(.session(4), three), "⌘4 beyond the number of sessions")
    #expect(!enabled(.session(0), three) && !enabled(.session(10), three))
}

@Test func sessionNavigationMatchesTheDesktopTabOrder() {
    let order = ["a", "b", "c", "d", "e"], unread: Set = ["a", "d"]
    #expect(WorkspaceCommandRouter.adjacent(order, current: "b", offset: 1) { unread.contains($0) } == "d")
    #expect(WorkspaceCommandRouter.adjacent(order, current: "b", offset: -1) { unread.contains($0) } == "a")
    #expect(WorkspaceCommandRouter.adjacent(order, current: "e", offset: 1) { unread.contains($0) } == "a")
    #expect(WorkspaceCommandRouter.adjacent(order, current: "a", offset: -1) { unread.contains($0) } == "d")
    #expect(WorkspaceCommandRouter.adjacent(order, current: "a", offset: 1) { $0 == "a" } == nil)
    #expect(WorkspaceCommandRouter.adjacent(order, current: nil, offset: 1) == nil)
    #expect(WorkspaceCommandRouter.adjacent(order, current: "z", offset: 1) == nil)
    #expect(WorkspaceCommandRouter.adjacent(["a"], current: "a", offset: 1) == nil)
    let sessions = [ref("a"), ref("b"), ref("c")]
    var window = WindowCommandState(loaded: true, current: ref("b"), sessions: sessions, unread: [ref("a").id])
    #expect(WorkspaceCommandRouter.session(.nextSession, window: window) == ref("c"))
    #expect(WorkspaceCommandRouter.session(.previousSession, window: window) == ref("a"))
    #expect(WorkspaceCommandRouter.session(.nextUnread, window: window) == ref("a"))
    #expect(WorkspaceCommandRouter.session(.session(2), window: window) == ref("b"))
    window.unread = []
    #expect(!WorkspaceCommandRouter.isEnabled(.nextUnread, window: window, composer: nil, find: false))
    window.current = nil
    #expect(!WorkspaceCommandRouter.isEnabled(.nextSession, window: window, composer: nil, find: false), "No session open")
}

@Test func reviewNextApprovalCyclesThroughPendingRequests() {
    var window = WindowCommandState(loaded: true, approvals: [ref("a", request: "per_1"), ref("b", request: "que_1")])
    #expect(WorkspaceCommandRouter.nextApproval(window) == ref("a", request: "per_1"))
    window.openRequest = "per_1"
    #expect(WorkspaceCommandRouter.nextApproval(window) == ref("b", request: "que_1"))
    window.openRequest = "que_1"
    #expect(WorkspaceCommandRouter.nextApproval(window) == ref("a", request: "per_1"))
    window.approvals = [ref("a", request: "per_1")]; window.openRequest = "per_1"
    #expect(WorkspaceCommandRouter.nextApproval(window) == nil, "The only request is already open")
}

@Test func performCallsOnlyTheOwningTarget() {
    var calls: [String] = []
    let window = WindowCommandState(loaded: true, canCreateSession: true)
    let composer = ComposerCommandState(loaded: true, blank: false)
    func run(_ command: WorkspaceCommand, find: Bool = false) -> Bool {
        WorkspaceCommandRouter.perform(command, window: window, composer: composer, find: find,
            windowAction: { calls.append("window:" + $0.id) }, composerAction: { calls.append("composer:" + $0.id) }, findAction: { calls.append("find") })
    }
    #expect(run(.send)); #expect(run(.newSession)); #expect(run(.find, find: true))
    #expect(!run(.find)); #expect(!run(.stop)); #expect(!run(.reviewNextApproval))
    #expect(calls == ["composer:prompt.submit", "window:session.new", "find"])
}

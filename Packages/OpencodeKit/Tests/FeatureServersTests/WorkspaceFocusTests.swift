#if os(iOS)
import Foundation
import Testing
import OCModels
import OCDesign

/// The menu bar keeps a focused value's actions while it compares equal, so equality has to name the target.
@MainActor @Test func focusedCommandsAreEqualOnlyForTheSameTarget() {
    let window = UUID(), state = WindowCommandState(loaded: true)
    #expect(OCWindowCommands(window: window, state: state) { _ in } == OCWindowCommands(window: window, state: state) { _ in },
            "The same window with an equal state keeps its menu")
    #expect(OCWindowCommands(window: window, state: state) { _ in } != OCWindowCommands(window: UUID(), state: state) { _ in },
            "Another window with an equal state is another target")
    let owner = UUID(), running = ComposerCommandState(loaded: true, blank: false, running: true)
    let composer = OCComposerCommands(owner: owner, session: "a", state: running) { _ in }
    #expect(composer == OCComposerCommands(owner: owner, session: "a", state: running) { _ in })
    #expect(composer != OCComposerCommands(owner: owner, session: "b", state: running) { _ in }, "Stop and Send follow the session on screen")
    #expect(composer != OCComposerCommands(owner: UUID(), session: "a", state: running) { _ in }, "Another composer of the same session")
    #expect(composer != OCComposerCommands(owner: owner, session: "a", state: ComposerCommandState(loaded: true, blank: false)) { _ in })
    let find = OCFindCommand(owner: owner, id: "/project/a.swift") {}
    #expect(find == OCFindCommand(owner: owner, id: "/project/a.swift") {})
    #expect(find != OCFindCommand(owner: UUID(), id: "/project/a.swift") {}, "Another viewer")
    #expect(find != OCFindCommand(owner: owner, id: "/project/b.swift") {}, "Another file")
}
#endif

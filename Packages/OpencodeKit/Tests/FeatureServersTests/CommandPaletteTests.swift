#if os(iOS)
import SwiftUI
import UIKit
import Testing
@testable import FeatureServers

/// The switcher's field keeps ↑, ↓, ⌥↩ and ⎋ while it has focus, and Return reaches it through its delegate.
@MainActor @Test func switcherFieldKeysRunOnceEach() throws {
    let field = PaletteTextField()
    var moves: [Int] = [], submits: [Bool] = [], cancels = 0
    field.move = { moves.append($0) }; field.submit = { submits.append($0) }; field.cancel = { cancels += 1 }
    let keys: [(String, UIKeyModifierFlags)] = [(UIKeyCommand.inputDownArrow, []), (UIKeyCommand.inputUpArrow, []), ("\r", .alternate), (UIKeyCommand.inputEscape, [])]
    for (input, flags) in keys {
        let matches = field.keyCommands?.filter { $0.input == input && $0.modifierFlags == flags } ?? []
        #expect(matches.count == 1 && matches.allSatisfy { $0.wantsPriorityOverSystemBehavior }, "One priority command for \(input) \(flags.rawValue)")
        let command = try #require(matches.first)
        // What UIKit sends the first responder when the key command fires.
        _ = field.perform(command.action, with: command)
    }
    let coordinator = PaletteField(text: .constant(""), placeholder: "", move: { _ in }, submit: { submits.append($0) }, cancel: {}).makeCoordinator()
    #expect(!coordinator.textFieldShouldReturn(field), "Return opens the active entry and never inserts a line")
    #expect(moves == [1, -1])
    #expect(submits == [true, false])
    #expect(cancels == 1)
}
#endif


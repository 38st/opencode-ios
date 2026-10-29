// A port of the reference terminal's serializer (packages/gui-plugins/src/terminal/serialize.ts at v2.2.0, itself
// xterm's addon-serialize) to SwiftTerm's content snapshots: the normal buffer with some history, the alternate buffer
// when a program uses it, the cursor, and the input modes, as escape sequences a new terminal replays.
#if os(iOS)
import Foundation
import SwiftTerm

enum TerminalSerializer {
    static func serialize(normal: TerminalContentSnapshot, alternate: TerminalContentSnapshot?, state: TerminalInputStateSnapshot) -> String {
        var output = rows(normal) + cursor(normal)
        if state.isAlternateBuffer, let alternate {
            output += "\u{1B}[?1049h\u{1B}[H" + rows(alternate) + cursor(alternate)
        }
        return output + modes(state)
    }

    /// The rows joined by CRLF, except before a soft-wrapped row, which continues the full row above it.
    static func rows(_ snapshot: TerminalContentSnapshot) -> String {
        var output = "", current = Attribute.empty
        for (index, row) in snapshot.rows.enumerated() {
            let wrapsNext = index + 1 < snapshot.rows.count && snapshot.rows[index + 1].isWrapped
            if index > 0 && !row.isWrapped { output += "\r\n" }
            // A row the next one continues was full; others end at their last written or coloured cell.
            let cells = wrapsNext ? row.cells : Array(row.cells.prefix(through: row.cells.lastIndex(where: visible) ?? -1))
            for cell in cells where cell.width > 0 {
                if cell.attribute != current { output += sgr(cell.attribute); current = cell.attribute }
                output += cell.text.isEmpty || cell.text == "\0" ? " " : cell.text
            }
        }
        return output + (current == .empty ? "" : "\u{1B}[0m")
    }
    static func cursor(_ snapshot: TerminalContentSnapshot) -> String {
        "\u{1B}[\(max(0, snapshot.cursorRow - snapshot.liveTopRow) + 1);\(max(0, snapshot.cursorColumn) + 1)H"
    }
    /// The modes a program set and the next output would not repeat. The mouse report encoding is not readable, so the
    /// SGR encoding (1006) most programs choose is assumed.
    static func modes(_ state: TerminalInputStateSnapshot) -> String {
        var output = ""
        if state.applicationCursor { output += "\u{1B}[?1h" }
        if state.applicationKeypad { output += "\u{1B}=" }
        if state.bracketedPasteMode { output += "\u{1B}[?2004h" }
        if state.focusReportingEnabled { output += "\u{1B}[?1004h" }
        switch state.mouseMode {
        case .off: break
        case .x10: output += "\u{1B}[?9h"
        case .vt200: output += "\u{1B}[?1000h\u{1B}[?1006h"
        case .buttonEventTracking: output += "\u{1B}[?1002h\u{1B}[?1006h"
        case .anyEvent: output += "\u{1B}[?1003h\u{1B}[?1006h"
        @unknown default: break
        }
        return output
    }
    static func sgr(_ attribute: Attribute) -> String {
        var codes = ["0"]
        let style = attribute.style
        if style.contains(.bold) { codes.append("1") }
        if style.contains(.dim) { codes.append("2") }
        if style.contains(.italic) { codes.append("3") }
        switch attribute.underlineStyle {
        case .none: if style.contains(.underline) { codes.append("4") }
        case .single: codes.append("4")
        case .double: codes.append("4:2")
        case .curly: codes.append("4:3")
        case .dotted: codes.append("4:4")
        case .dashed: codes.append("4:5")
        }
        if style.contains(.blink) { codes.append("5") }
        if style.contains(.inverse) { codes.append("7") }
        if style.contains(.invisible) { codes.append("8") }
        if style.contains(.crossedOut) { codes.append("9") }
        codes += color(attribute.fg, base: 30, bright: 90, extended: 38)
        codes += color(attribute.bg, base: 40, bright: 100, extended: 48)
        if let underline = attribute.underlineColor { codes += color(underline, base: nil, bright: nil, extended: 58) }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
    /// The default colours need no code after the reset; a foreground drawn in the background colour (or the reverse)
    /// has no code at all and keeps the default.
    private static func color(_ color: Attribute.Color, base: Int?, bright: Int?, extended: Int) -> [String] {
        switch color {
        case .ansi256(let code) where code < 8 && base != nil: ["\((base ?? 0) + Int(code))"]
        case .ansi256(let code) where code < 16 && bright != nil: ["\((bright ?? 0) + Int(code) - 8)"]
        case .ansi256(let code): ["\(extended)", "5", "\(code)"]
        case .trueColor(let red, let green, let blue): ["\(extended)", "2", "\(red)", "\(green)", "\(blue)"]
        case .defaultColor, .defaultInvertedColor: []
        }
    }
    /// A blank cell counts when it is painted: an explicit background, reverse video or an underline. Unwritten cells
    /// carry `Attribute.empty`, erased ones the default colours.
    private static func visible(_ cell: TerminalCellSnapshot) -> Bool {
        if !(cell.text.isEmpty || cell.text == " " || cell.text == "\0") { return true }
        let attribute = cell.attribute
        guard attribute != Attribute.empty else { return false }
        let painted = if case .defaultColor = attribute.bg { false } else { true }
        return painted || attribute.style.contains(.inverse) || attribute.underlineStyle != .none || attribute.style.contains(.underline)
    }
}
#endif

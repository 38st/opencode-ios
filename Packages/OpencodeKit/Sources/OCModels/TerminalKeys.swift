// xterm's encodings: Ctrl clears bits 5 and 6 of 0x40–0x7F and follows the VT220 digit row, Alt is an ESC prefix, and a
// modified cursor key is CSI 1;<1 + modifiers> in either cursor mode.
import Foundation

public enum TerminalKey: Hashable, Sendable {
    case escape, tab, up, down, left, right
    case text(String)
}

public struct TerminalModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = TerminalModifiers(rawValue: 1 << 0)
    public static let alt = TerminalModifiers(rawValue: 1 << 1)
}

public enum TerminalKeys {
    /// The key bar's keys after Esc, Ctrl and Alt, in order; the bar scrolls when they do not fit.
    public static let bar: [TerminalKey] = [.tab, .left, .down, .up, .right, .text("|"), .text("~"), .text("/"), .text("-")]

    /// The bytes one key sends. `applicationCursor` is DECCKM, read from the terminal when the key is pressed.
    public static func encode(_ key: TerminalKey, modifiers: TerminalModifiers = [], applicationCursor: Bool = false) -> [UInt8] {
        switch key {
        case .escape: return prefix(modifiers, [0x1B])
        case .tab: return prefix(modifiers, [0x09])
        case .up, .down, .left, .right:
            let final: UInt8 = switch key { case .up: 0x41; case .down: 0x42; case .right: 0x43; default: 0x44 }
            let parameter = 1 + (modifiers.contains(.alt) ? 2 : 0) + (modifiers.contains(.control) ? 4 : 0)
            if parameter > 1 { return Array("\u{1B}[1;\(parameter)".utf8) + [final] }
            return applicationCursor ? [0x1B, 0x4F, final] : [0x1B, 0x5B, final]
        case .text(let text):
            guard let first = text.first else { return [] }
            var bytes = Array(String(first).utf8)
            if modifiers.contains(.control), let control = control(first) { bytes = [control] }
            return prefix(modifiers, bytes) + Array(text.dropFirst().utf8)
        }
    }

    /// The C0 byte Ctrl sends with `character`, or nil when Ctrl leaves it unchanged.
    public static func control(_ character: Character) -> UInt8? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first, scalar.isASCII else { return nil }
        let value = UInt8(scalar.value)
        switch value {
        case 0x61...0x7A: return value - 0x60
        case 0x40...0x5F, 0x7B...0x7E: return value & 0x1F
        case 0x20, 0x32, 0x60: return 0x00
        case 0x33: return 0x1B
        case 0x34: return 0x1C
        case 0x35: return 0x1D
        case 0x36: return 0x1E
        case 0x2D, 0x2F, 0x37: return 0x1F
        case 0x38, 0x3F: return 0x7F
        default: return nil
        }
    }

    private static func prefix(_ modifiers: TerminalModifiers, _ bytes: [UInt8]) -> [UInt8] {
        modifiers.contains(.alt) ? [0x1B] + bytes : bytes
    }
}

/// Sticky Ctrl and Alt: a tap latches a modifier for the next key from the bar or either keyboard; a second tap releases it.
public struct TerminalModifierLatch: Equatable, Sendable {
    public private(set) var latched: TerminalModifiers = []
    public init() {}
    public mutating func toggle(_ modifier: TerminalModifiers) { latched.formSymmetricDifference(modifier) }
    /// Applies and releases the latch. Text typed while it is latched modifies only its first character.
    public mutating func consume() -> TerminalModifiers { defer { latched = [] }; return latched }
}

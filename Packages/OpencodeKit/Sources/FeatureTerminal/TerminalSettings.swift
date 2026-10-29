import Foundation

/// The terminal's Settings values. The font is the design system's monospace font at this size; it does not follow
/// Dynamic Type, so a program's columns do not change with the system text size.
public enum TerminalSettings {
    public static let fontSizeKey = "terminalFontSize"
    public static let optionAsMetaKey = "terminalOptionAsMeta"
    public static let defaultFontSize = 13.0
    public static let fontSizes = 9.0...24.0
}

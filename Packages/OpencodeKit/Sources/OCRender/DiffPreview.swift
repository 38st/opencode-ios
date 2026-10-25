import Foundation

/// Sizing for inline diff previews. A preview shows at most `maxRows` rows without scrolling; the full viewer shows the rest.
public enum DiffPreview {
    public static let maxRows = 20
    /// The row height the diff renderer uses for a monospaced font size.
    public static func lineHeight(font: Double) -> Double { max(24, (font * 1.65).rounded(.up)) }
    /// Rows a patch renders as before it is measured. File headers are not rows; hunk headings and collapsed context are.
    public static func estimatedRows(_ patch: String, showAll: Bool = false) -> Int {
        max(1, DiffRows.make(DiffParser.parse(patch), showAll: showAll).count)
    }
    /// The preview height for the measured content height, or for an estimated row count until measured,
    /// and whether the content runs past the cap.
    public static func height(measured: Double?, rows: @autoclosure () -> Int, font: Double) -> (height: Double, clipped: Bool) {
        let line = lineHeight(font: font), cap = Double(maxRows) * line
        let content = measured ?? Double(rows()) * line
        return (min(cap, max(line, content)), content > cap + 0.5)
    }
}

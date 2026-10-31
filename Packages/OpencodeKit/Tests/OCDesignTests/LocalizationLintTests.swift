import Foundation
import Testing

/// SwiftUI looks a literal title up in the app's main bundle, never in a package module's String Catalog, so a bare
/// literal in a title position would stay English forever. Every user-facing literal goes through `localized(_:)`;
/// literal data uses `Text(verbatim:)`. Previews are exempt.
@Suite struct LocalizationLintTests {
    private static let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources").standardizedFileURL
    private static var titlePositions: NSRegularExpression { try! NSRegularExpression(pattern: #"(?<![\w.])(?:Text|Button|Label|Toggle|TextField|SecureField|Section|Menu|Picker|LabeledContent|NavigationLink|Link|ShareLink|ContentUnavailableView|Stepper|Tab|OCSection|OCLabel|OCIconButton|OCBadge|OCPill|OCToggleRow|OCCodeFrame|OCSidebarHeader|OCListRow|OCToolRow|OCMenuButton|OCConfirmationSheet)\("|\.(?:navigationTitle|ocNavigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|help|alert|confirmationDialog|badge)\("|accessibilityAction\(named: "|prompt: ""#) }

    @Test func noBareLiteralInATitlePosition() throws {
        var found: [String] = []
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let previews = Self.previewRanges(text)
            for match in Self.titlePositions.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text), !previews.contains(where: { $0.contains(range.lowerBound) }) else { continue }
                let line = text[..<range.lowerBound].count { $0 == "\n" } + 1
                found.append("\(file.lastPathComponent):\(line)")
            }
        }
        #expect(found.isEmpty, "Wrap these literals in localized(_:) or use Text(verbatim:): \(found)")
    }

    @Test func everyModuleWithStringsHasACatalog() throws {
        let modules = try FileManager.default.contentsOfDirectory(at: Self.sources, includingPropertiesForKeys: nil)
        for module in modules where FileManager.default.fileExists(atPath: module.appending(path: "Localized.swift").path) {
            #expect(FileManager.default.fileExists(atPath: module.appending(path: "Resources/Localizable.xcstrings").path), "\(module.lastPathComponent) has no catalog")
        }
    }

    private static func previewRanges(_ text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var search = text.startIndex
        while let marker = text.range(of: "#Preview", range: search..<text.endIndex), let open = text[marker.upperBound...].firstIndex(of: "{") {
            var depth = 0
            var index = open
            while index < text.endIndex {
                if text[index] == "{" { depth += 1 } else if text[index] == "}" { depth -= 1; if depth == 0 { break } }
                index = text.index(after: index)
            }
            ranges.append(open..<index)
            search = index < text.endIndex ? text.index(after: index) : text.endIndex
        }
        return ranges
    }
}

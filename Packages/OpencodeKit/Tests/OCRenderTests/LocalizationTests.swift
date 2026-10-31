import Foundation
import Testing
import OCFoundation
@testable import OCRender

// Serialized: the double-length mode is process-wide.
@Suite(.serialized) struct LocalizationTests {
    @Test func pluralFormsComeFromTheCatalog() {
        #expect(localized("Changed \(1) files") == "Changed 1 file")
        #expect(localized("Changed \(3) files") == "Changed 3 files")
        #expect(localized("\(1) hidden lines") == "1 hidden line")
        #expect(localized("Used \(2) tools") == "Used 2 tools")
    }

    @Test func doubleLengthModeRepeatsLookedUpStrings() {
        OCLocalization.mode = .doubleLength
        defer { OCLocalization.mode = .standard }
        #expect(localized("Changed \(1) files") == "Changed 1 file Changed 1 file")
        #expect(OCLocalization.string("", bundle: .main, comment: nil) == "")
    }
}

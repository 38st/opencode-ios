import Foundation
import Testing
@testable import OCDesign

@Suite struct AcknowledgementsTests {
    private static let repository = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../..").standardizedFileURL

    @Test func everyBundledComponentHasItsLicenceText() throws {
        let acknowledgements = Acknowledgements.bundled()
        let items = acknowledgements.sections.flatMap(\.items)
        #expect(items.count > 30)
        for item in items {
            let text = try #require(Acknowledgements.licenseText(for: item), "\(item.name) has no licence text")
            #expect(text.count > 300, "\(item.name)'s licence text is too short")
        }
    }

    // THIRD_PARTY_NOTICES.md's table is generated from the same JSON; a hand edit to either side fails here.
    @Test func noticesTableMatchesTheAcknowledgements() throws {
        let notices = try String(contentsOf: Self.repository.appending(path: "THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        let rows = Set(notices.split(separator: "\n").map(String.init).filter { $0.hasPrefix("| [") })
        let items = Acknowledgements.bundled().sections.flatMap(\.items)
        for item in items {
            let cell = { (text: String) in text.replacingOccurrences(of: "|", with: "\\|") }
            let row = "| [\(cell(item.name))](\(item.url.absoluteString)) | \(cell(item.version)) | \(cell(item.license)) | \(cell(item.copyright)) |"
            #expect(rows.contains(row), "THIRD_PARTY_NOTICES.md lacks \(item.name) \(item.version)")
        }
        #expect(rows.count == items.count)
    }

    @Test func swiftVersionsMatchPackageResolved() throws {
        let resolved = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.repository.appending(path: "Packages/OpencodeKit/Package.resolved"))) as? [String: Any]
        let pins = (resolved?["pins"] as? [[String: Any]] ?? []).reduce(into: [String: String]()) { result, pin in
            result[(pin["location"] as? String ?? "").lowercased()] = (pin["state"] as? [String: Any])?["version"] as? String
        }
        let libraries = try #require(Acknowledgements.bundled().sections.first { $0.id == "libraries" })
        for item in libraries.items {
            let wanted = item.url.absoluteString.lowercased()
            let location = pins.keys.first { $0 == wanted || $0 == wanted + ".git" }
            #expect(location.flatMap { pins[$0] } == item.version, "\(item.name) \(item.version) does not match Package.resolved")
        }
    }
}

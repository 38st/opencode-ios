import Foundation
import Testing

@Test func submitColorsPreserveLegibleContrastInBothAppearances() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appending(path: "Sources/OCDesign/Resources/Colors.xcassets")
    func colors(_ name: String) throws -> [[Double]] {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: assets.appending(path: "oc2-" + name + ".colorset/Contents.json"))) as? [String: Any]
        let values = try #require(raw?["colors"] as? [[String: Any]])
        return try values.map { value in
            let color = try #require(value["color"] as? [String: Any])
            let components = try #require(color["components"] as? [String: String])
            return try ["red", "green", "blue"].map { try #require(components[$0].flatMap(Double.init)) }
        }
    }
    func luminance(_ channels: [Double]) -> Double {
        zip(channels, [0.2126, 0.7152, 0.0722]).reduce(0) { result, item in
            let linear = item.0 <= 0.04045 ? item.0 / 12.92 : pow((item.0 + 0.055) / 1.055, 2.4)
            return result + linear * item.1
        }
    }
    let fills = try colors("iconButtonContrast"), glyphs = try colors("textInverse")
    #expect(fills.count == 2 && glyphs.count == 2)
    for index in fills.indices {
        let fill = luminance(fills[index]), glyph = luminance(glyphs[index])
        #expect((max(fill, glyph) + 0.05) / (min(fill, glyph) + 0.05) > 7)
    }
    #expect(abs(fills[1][0] - 219.0 / 255) < 0.000001)
    #expect(abs(try colors("contrast")[1][0] - 92.0 / 255) < 0.000001)
}

import Foundation
import SwiftUI

/// Artwork and mappings: packages/ui/src/components/file-icon.tsx and file-icons/sprite.svg (MIT).
/// The sprite's `currentColor` fills are baked to iconMuted (#808080, the same in both themes), because
/// `.original` rendering would otherwise resolve them to black and hide folders in dark mode.
public struct OCFileIcon: View {
    let path: String
    let directory: Bool
    let size: CGFloat
    let monochrome: Bool
    public init(_ path: String, directory: Bool = false, size: CGFloat = 16, monochrome: Bool = false) {
        self.path = path; self.directory = directory; self.size = size; self.monochrome = monochrome
    }
    private static let maps: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "file-icons", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }()
    public static func name(_ path: String, directory: Bool) -> String {
        let base = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        if directory {
            return [base, "." + base, "_" + base, "__" + base + "__"].compactMap { maps["folderNames"]?[$0] }.first ?? "Folder"
        }
        if let exact = maps["fileNames"]?[base] { return exact }
        var suffix = base[...]
        while !suffix.isEmpty {
            if let match = maps["fileExtensions"]?[String(suffix)] { return match }
            guard let dot = suffix.firstIndex(of: ".") else { break }
            suffix = suffix[suffix.index(after: dot)...]
        }
        return "Document"
    }
    public var body: some View {
        Image("filetype-" + Self.name(path, directory: directory), bundle: .module).renderingMode(monochrome ? .template : .original)
            .resizable().scaledToFit().frame(width: size, height: size).foregroundStyle(OCColor.iconMuted).accessibilityHidden(true)
    }
}

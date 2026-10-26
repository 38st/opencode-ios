// Source: packages/ui/src/icons/{catalog.ts,icon/additional-icons.ts,icon/icon.tsx}.
// Template SVG artwork is preserved in Resources/Icons.xcassets (MIT).
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct OCIcon: View {
    let name: String
    let size: CGFloat
    public init(_ name: String, size: CGFloat = 16) { self.name = name; self.size = size }
    #if canImport(UIKit)
    public static func isBundled(_ name: String) -> Bool { UIImage(named: name, in: .module, compatibleWith: nil) != nil }
    #endif
    public var body: some View {
        #if DEBUG && canImport(UIKit)
        // A missing asset renders as an empty, still tappable frame; catch typos while developing.
        assert(Self.isBundled(name), "OCIcon: no \"\(name)\" asset in Icons.xcassets")
        #endif
        return Image(name, bundle: .module).renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
public struct OCLabel: View {
    let title: String
    let icon: String
    public init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    public var body: some View { Label { Text(title) } icon: { OCIcon(icon) } }
}

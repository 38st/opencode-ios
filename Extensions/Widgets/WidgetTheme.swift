import CoreText
import SwiftUI

/// The OC-2 tokens and Inter of docs/design.md, without linking OCDesign: its colour catalog and Inter are compiled
/// into this bundle, and the status icons are copies of OCDesign's (checked byte for byte by `widgetIconsMatchTheApp`).
enum WidgetStyle {
    static func color(_ name: String) -> Color { Color("oc2-" + name, bundle: .widgets) }
    static let background = color("background")
    static let text = color("text")
    static let muted = color("textMuted")
    static let faint = color("textFaint")
    static let border = color("border")
    static let warning = color("warning")
    static let danger = color("danger")
    static let success = color("success")
    static let info = color("info")
    /// OCType's sizes: micro 11 medium, small 13, body 14, heading 16 medium, title 20 semibold.
    static func inter(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        registerFonts()
        return .custom("Inter-Regular", size: size, relativeTo: style).weight(weight)
    }
    static var micro: Font { inter(11, relativeTo: .caption2, weight: .medium) }
    static var small: Font { inter(13, relativeTo: .footnote) }
    static var body: Font { inter(14, relativeTo: .body) }
    static var heading: Font { inter(16, relativeTo: .headline, weight: .medium) }
    static var title: Font { inter(20, relativeTo: .title2, weight: .semibold) }
    static func icon(_ name: String) -> Image { Image(name, bundle: .widgets).renderingMode(.template) }
    /// The extension lists Inter in UIAppFonts; registering it again covers the snapshot tests' bundle.
    private static let registration: Void = {
        if let url = Bundle.widgets.url(forResource: "Inter", withExtension: "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }()
    static func registerFonts() { _ = registration }
}

private final class WidgetBundleToken {}
extension Bundle {
    /// The bundle holding the widgets' code and resources: the extension, or the snapshot tests.
    static let widgets = Bundle(for: WidgetBundleToken.self)
}

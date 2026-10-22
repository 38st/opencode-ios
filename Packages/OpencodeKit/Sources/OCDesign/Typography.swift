// Sources: packages/ui/src/styles/theme.css, actions/button/button.css,
// assets/fonts/Inter.ttf and JetBrainsMonoNerdFontMono-Regular.woff2.
import SwiftUI
import CoreText
import Foundation

public enum OCFonts {
    private static let registration: Void = {
        for name in ["Inter", "JetBrainsMonoNerdFontMono-Regular"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(name)"); continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    public static func register() { _ = registration }
}

public enum OCType {
    private static func inter(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        OCFonts.register()
        return .custom("Inter-Regular", size: size, relativeTo: style).weight(weight)
    }
    public static var micro: Font { inter(11, relativeTo: .caption2, weight: .medium) }
    public static var small: Font { inter(13, relativeTo: .footnote) }
    public static var body: Font { inter(14, relativeTo: .body) }
    public static var large: Font { inter(16, relativeTo: .title3) }
    public static var title: Font { inter(20, relativeTo: .title2, weight: .semibold) }
    public static var heading: Font { inter(16, relativeTo: .headline, weight: .medium) }
    public static var button: Font { inter(13, relativeTo: .body, weight: .medium) }
    public static var code: Font {
        OCFonts.register()
        return .custom("JetBrainsMonoNFM-Regular", size: 13, relativeTo: .body)
    }
    public static let trackingTight: CGFloat = -0.16
    public static let trackingTightest: CGFloat = -0.32
    public static let lineHeight: CGFloat = 20
}

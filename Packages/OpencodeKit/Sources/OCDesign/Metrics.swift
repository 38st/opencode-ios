// Spacing/radii: packages/ui/src/styles/theme.css; actions/button/button.css; components/dock-surface.css.
// Elevation: packages/ui/src/styles/tokens/theme.css (v2-elevation-*).
// Motion: styles/animations.css, feedback/toast/toast.css, forms/switch/switch.css,
// packages/app/src/shell/mobile-drawer.css. Touch targets are the iOS adaptation.
import SwiftUI

public enum OCSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let section: CGFloat = 48
}
public enum OCRadius {
    public static let xs: CGFloat = 2
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 6
    public static let lg: CGFloat = 8
    public static let xl: CGFloat = 10
    public static let dock: CGFloat = 12
    public static let sheet: CGFloat = 16
}
public enum OCBorder {
    public static let hairline: CGFloat = 0.5
    public static let standard: CGFloat = 1
    public static let focus: CGFloat = 2
}
public enum OCLayout {
    public static let touchTarget: CGFloat = 44
    public static let sidebar: CGFloat = 256
    public static let inspector: CGFloat = 280
    public static let readable: CGFloat = 640
    public static let desktopBreakpoint: CGFloat = 768
    public static let connectionForm: CGFloat = 360
    public static let workspaceWide: CGFloat = 1_100
    // session/session-panel-width.ts: the chat pane's initial/minimum width is 450.
    public static let timelineWithReview: CGFloat = 450
    public static let approvalDockHeight: CGFloat = 240
    public static let timelineMinimumHeight: CGFloat = 120
    public static let sessionCompactHeight: CGFloat = 600
    public static let sessionPendingFraction: CGFloat = 0.2
    // session-review-v2.css: centered empty panels leave room below their message.
    public static let panelEmptyBottom: CGFloat = 160
    public static let panelEmptyDescription: CGFloat = 360
}
public enum OCMotion {
    public static let fast = 0.15
    public static let standard = 0.2
    public static let panel = 0.24
    public static let toggle = 0.09
    public static let toast = 0.28
    public static let opacity = 0.16
    public static let easing = Animation.timingCurve(0.2, 0, 0, 1, duration: standard)
}

public enum OCElevation: Sendable {
    case raised, floating, overlay
    var offset: CGFloat { switch self { case .raised: 2; case .floating: 8; case .overlay: 16 } }
}
private struct ElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let elevation: OCElevation
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.04), radius: elevation.offset * 2, y: elevation.offset)
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: elevation.offset, y: elevation.offset / 2)
    }
}
public extension View {
    func ocElevation(_ elevation: OCElevation) -> some View { modifier(ElevationModifier(elevation: elevation)) }
}

// Sources: packages/ui/src/theme/themes/oc-2.json, styles/tokens/{colors,theme}.css,
// theme/resolve.ts and styles/theme.css (diff/syntax surfaces). Preserve the default preset's explicit overrides.
import SwiftUI

public enum OCTheme: String, Sendable {
    case openCode = "oc2"
    public func color(_ name: String) -> Color { Color(rawValue + "-" + name, bundle: .module) }
}

public enum OCColor {
    /// `v2-background-bg-base`
    public static let background = OCTheme.openCode.color("background")
    /// `v2-background-bg-deep`
    public static let backgroundDeep = OCTheme.openCode.color("backgroundDeep")
    /// `v2-background-bg-layer-01`
    public static let layer1 = OCTheme.openCode.color("layer1")
    /// `v2-background-bg-layer-02`
    public static let layer2 = OCTheme.openCode.color("layer2")
    /// `v2-background-bg-layer-03`
    public static let layer3 = OCTheme.openCode.color("layer3")
    /// `v2-background-bg-layer-04`
    public static let layer4 = OCTheme.openCode.color("layer4")
    /// `v2-background-bg-button-neutral`
    public static let surface = OCTheme.openCode.color("surface")
    /// `v2-background-bg-contrast`
    public static let contrast = OCTheme.openCode.color("contrast")
    /// `v2-text-text-base`
    public static let text = OCTheme.openCode.color("text")
    /// `v2-text-text-muted`
    public static let textMuted = OCTheme.openCode.color("textMuted")
    /// `v2-text-text-faint`
    public static let textFaint = OCTheme.openCode.color("textFaint")
    /// `v2-text-text-inverse`
    public static let textInverse = OCTheme.openCode.color("textInverse")
    /// `v2-text-text-contrast`
    public static let textContrast = OCTheme.openCode.color("textContrast")
    /// `v2-text-text-accent`
    public static let accent = OCTheme.openCode.color("accent")
    /// `v2-background-bg-accent`
    public static let accentBackground = OCTheme.openCode.color("accentBackground")
    /// `v2-icon-icon-base`
    public static let icon = OCTheme.openCode.color("icon")
    /// `v2-icon-icon-muted`
    public static let iconMuted = OCTheme.openCode.color("iconMuted")
    /// `v2-border-border-base`
    public static let border = OCTheme.openCode.color("border")
    /// `v2-border-border-muted`
    public static let borderMuted = OCTheme.openCode.color("borderMuted")
    /// `v2-border-border-strong`
    public static let borderStrong = OCTheme.openCode.color("borderStrong")
    /// `v2-border-border-focus`
    public static let focus = OCTheme.openCode.color("focus")
    /// `v2-overlay-simple-overlay-hover`
    public static let hover = OCTheme.openCode.color("hover")
    /// `v2-overlay-simple-overlay-pressed`
    public static let pressed = OCTheme.openCode.color("pressed")
    /// `v2-overlay-simple-overlay-scrim`
    public static let scrim = OCTheme.openCode.color("scrim")
    /// `v2-state-fg-success`
    public static let success = OCTheme.openCode.color("success")
    /// `v2-state-bg-success`
    public static let successBackground = OCTheme.openCode.color("successBackground")
    /// `v2-state-border-success`
    public static let successBorder = OCTheme.openCode.color("successBorder")
    /// `v2-state-fg-warning`
    public static let warning = OCTheme.openCode.color("warning")
    /// `v2-state-bg-warning`
    public static let warningBackground = OCTheme.openCode.color("warningBackground")
    /// `v2-state-border-warning`
    public static let warningBorder = OCTheme.openCode.color("warningBorder")
    /// `v2-state-fg-danger`
    public static let danger = OCTheme.openCode.color("danger")
    /// `v2-state-bg-danger`
    public static let dangerBackground = OCTheme.openCode.color("dangerBackground")
    /// `v2-state-border-danger`
    public static let dangerBorder = OCTheme.openCode.color("dangerBorder")
    /// `v2-state-fg-info`
    public static let info = OCTheme.openCode.color("info")
    /// `v2-state-bg-info`
    public static let infoBackground = OCTheme.openCode.color("infoBackground")
    /// `v2-state-border-info`
    public static let infoBorder = OCTheme.openCode.color("infoBorder")
    /// `v2-grey-200`
    public static let toggleThumb = OCTheme.openCode.color("toggleThumb")
    /// `syntax-comment`
    public static let syntaxComment = OCTheme.openCode.color("syntaxComment")
    /// `syntax-keyword`
    public static let syntaxKeyword = OCTheme.openCode.color("syntaxKeyword")
    /// `syntax-string`
    public static let syntaxString = OCTheme.openCode.color("syntaxString")
    /// `syntax-primitive`
    public static let syntaxPrimitive = OCTheme.openCode.color("syntaxPrimitive")
    /// `syntax-property`
    public static let syntaxProperty = OCTheme.openCode.color("syntaxProperty")
    /// `syntax-type`
    public static let syntaxType = OCTheme.openCode.color("syntaxType")
    /// `syntax-constant`
    public static let syntaxConstant = OCTheme.openCode.color("syntaxConstant")
    /// `syntax-critical`
    public static let syntaxCritical = OCTheme.openCode.color("syntaxCritical")
    /// `syntax-diff-add`
    public static let syntaxDiffAdd = OCTheme.openCode.color("syntaxDiffAdd")
    /// `syntax-diff-delete`
    public static let syntaxDiffDelete = OCTheme.openCode.color("syntaxDiffDelete")
    /// `syntax-diff-unknown`
    public static let syntaxDiffUnknown = OCTheme.openCode.color("syntaxDiffUnknown")
    /// `syntax-info`
    public static let syntaxInfo = OCTheme.openCode.color("syntaxInfo")
    /// `syntax-object`
    public static let syntaxObject = OCTheme.openCode.color("syntaxObject")
    /// `syntax-operator`
    public static let syntaxOperator = OCTheme.openCode.color("syntaxOperator")
    /// `syntax-punctuation`
    public static let syntaxPunctuation = OCTheme.openCode.color("syntaxPunctuation")
    /// `syntax-regexp`
    public static let syntaxRegexp = OCTheme.openCode.color("syntaxRegexp")
    /// `syntax-success`
    public static let syntaxSuccess = OCTheme.openCode.color("syntaxSuccess")
    /// `syntax-variable`
    public static let syntaxVariable = OCTheme.openCode.color("syntaxVariable")
    /// `syntax-warning`
    public static let syntaxWarning = OCTheme.openCode.color("syntaxWarning")
    /// `surface-diff-add-base`
    public static let diffAdd = OCTheme.openCode.color("diffAdd")
    /// `surface-diff-add-weak`
    public static let diffAddWeak = OCTheme.openCode.color("diffAddWeak")
    /// `surface-diff-add-strong`
    public static let diffAddStrong = OCTheme.openCode.color("diffAddStrong")
    /// `surface-diff-delete-base`
    public static let diffRemove = OCTheme.openCode.color("diffRemove")
    /// `surface-diff-delete-weak`
    public static let diffRemoveWeak = OCTheme.openCode.color("diffRemoveWeak")
    /// `surface-diff-delete-strong`
    public static let diffRemoveStrong = OCTheme.openCode.color("diffRemoveStrong")
    /// Pierre's emphasized words and changed-line gutters, in both appearances.
    public static let diffAddText = OCTheme.openCode.color("diffAddText")
    public static let diffRemoveText = OCTheme.openCode.color("diffRemoveText")
    public static let diffAddNumber = OCTheme.openCode.color("diffAddNumber")
    public static let diffRemoveNumber = OCTheme.openCode.color("diffRemoveNumber")
}

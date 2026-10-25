// Sources: packages/ui/src/components/{spinner,progress}.css, feedback/toast/toast.css (banner uses state tokens),
// packages/app/src/shell/mobile-drawer.css. VoiceOver receives explicit text for every status.
import SwiftUI

public struct OCSpinner: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        HStack(spacing: OCSpacing.sm) { ProgressView().tint(OCColor.iconMuted); Text(title).font(OCType.small) }
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }
}
public struct OCProgress: View {
    let title: String
    let value: Double
    public init(_ title: String, value: Double) { self.title = title; self.value = value }
    public var body: some View { ProgressView(title, value: value).tint(OCColor.accentBackground).font(OCType.small) }
}
public struct OCBanner: View {
    let title: String
    let tone: OCTone
    public init(_ title: String, tone: OCTone = .info) { self.title = title; self.tone = tone }
    public var body: some View {
        HStack(alignment: .top, spacing: OCSpacing.sm) {
            OCIcon(tone == .success ? "check" : "info")
            Text(title).font(OCType.small).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(tone.foreground).padding(OCSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.background, in: RoundedRectangle(cornerRadius: OCRadius.md))
    }
}
public struct OCToast<Content: View>: View {
    let announcement: String?
    let content: Content
    /// `announcement` is spoken when the toast appears or its text changes; VoiceOver focus stays put.
    public init(announcement: String? = nil, @ViewBuilder content: () -> Content) { self.announcement = announcement; self.content = content() }
    public var body: some View {
        OCCard { content }.ocElevation(.floating).padding(OCSpacing.lg)
            .ocAnnounce(announcement, initial: true)
    }
}
public enum OCAnnouncementPriority: Sendable { case normal, high }
/// Posts VoiceOver announcements for changes that do not move focus: errors, copies, run state and approvals.
public enum OCAnnouncer {
    public static func post(_ text: String, priority: OCAnnouncementPriority = .normal) {
        guard !text.isEmpty else { return }
        var message = AttributedString(text)
        message.accessibilitySpeechAnnouncementPriority = priority == .high ? .high : .default
        AccessibilityNotification.Announcement(message).post()
    }
}
extension View {
    /// Announces `text` whenever it changes to a non-empty value, for inline errors and status lines.
    public func ocAnnounce(_ text: String?, priority: OCAnnouncementPriority = .normal, initial: Bool = false) -> some View {
        onChange(of: text, initial: initial) { _, value in if let value { OCAnnouncer.post(value, priority: priority) } }
    }
}
public enum OCEmptyStatePresentation: Sendable { case page, panel }
public struct OCEmptyState<Actions: View>: View {
    let title: String
    let detail: String
    let icon: String
    let presentation: OCEmptyStatePresentation
    let fileIcon: String?
    let actions: Actions
    public init(_ title: String, detail: String, icon: String, presentation: OCEmptyStatePresentation = .page, fileIcon: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.detail = detail; self.icon = icon; self.actions = actions()
        self.presentation = presentation; self.fileIcon = fileIcon
    }
    public var body: some View {
        if presentation == .panel {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: OCSpacing.lg) {
                        if let fileIcon { OCFileIcon(fileIcon, size: 20, monochrome: true) }
                        else { OCIcon(icon, size: 20).foregroundStyle(OCColor.iconMuted) }
                        VStack(spacing: fileIcon == nil ? OCSpacing.sm : OCSpacing.lg) {
                            Text(title).font(OCType.button)
                            if !detail.isEmpty {
                                Text(detail).font(OCType.small).foregroundStyle(OCColor.textMuted)
                                    .lineSpacing(OCSpacing.xs).frame(maxWidth: OCLayout.panelEmptyDescription)
                            }
                        }
                        actions
                    }.multilineTextAlignment(.center).padding(.horizontal, OCSpacing.xl)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, geometry.size.height - OCSpacing.xl - OCLayout.panelEmptyBottom))
                        .padding(.top, OCSpacing.xl).padding(.bottom, OCLayout.panelEmptyBottom)
                }.background(OCColor.background)
            }
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.xl) {
                OCIcon(icon, size: 32).foregroundStyle(OCColor.iconMuted)
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text(title).font(OCType.title).tracking(OCType.trackingTightest)
                    Text(detail).font(OCType.body).foregroundStyle(OCColor.textMuted)
                }
                actions
            }.padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable, alignment: .leading)
                .frame(maxWidth: .infinity).padding(.top, OCSpacing.section)
        }.background(OCColor.background)
        }
    }
}
#Preview("Feedback") {
    OCForm {
        OCSpinner("Connecting…")
        OCProgress("Syncing", value: 0.6)
        OCBanner("Connected to Studio Mac", tone: .success)
        OCBanner("Pairing expires soon", tone: .warning)
        OCToast { Text("Command copied") }
    }.ocTheme()
}

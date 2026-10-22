import SwiftUI
import Foundation
#if os(iOS)
import UIKit
import ImageIO
#endif

public enum OCComposerMetrics {
    public static let editorMinimum: CGFloat = 60
    public static let editorMaximum: CGFloat = 180
    public static let toolbar: CGFloat = 44
    public static let submit: CGFloat = 28
    public static let thumbnailWidth: CGFloat = 58
    public static let thumbnailHeight: CGFloat = 46
    // new-session/{layout.ts,view.tsx}: 880 px with a 25.375% top anchor.
    public static let newSessionWidth: CGFloat = 880
    public static let newSessionTopFraction: CGFloat = 0.25375
    public static let compactHeight: CGFloat = 500
}
public struct OCComposerChoice: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        HStack(spacing: OCSpacing.xs) {
            Text(title).font(OCType.small).lineLimit(1)
            OCIcon("chevron-down", size: 12)
        }.frame(minWidth: OCLayout.touchTarget, minHeight: OCLayout.touchTarget)
    }
}
public struct OCComposerSurface<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        VStack(spacing: 0) { content }
            .background(colorScheme == .dark ? OCColor.layer1 : OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.dock))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.dock).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline).allowsHitTesting(false))
            .ocElevation(.raised)
    }
}
public enum OCMentionStyle {
    // message-part.css: local-session user-message-mention-prefix-color (v2-blue-500).
    public static let sentPrefix = Color("oc2-sentMentionPrefix", bundle: .module)
    public static func agentAccent(_ hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let rgb = UInt32(hex.dropFirst(), radix: 16) else { return OCColor.textMuted }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    public static func color(_ kind: String?) -> Color {
        switch kind { case "file": OCColor.syntaxProperty; case "agent": OCColor.syntaxType; case "reference": OCColor.syntaxKeyword; default: OCColor.text }
    }
}
public struct OCPromptText: View {
    let value: AttributedString
    public init(_ value: AttributedString) { self.value = value }
    public var body: some View { Text(value).font(OCType.body) }
}
#if os(iOS)
public extension OCType {
    static func editorParagraphStyle(traits: UITraitCollection? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = UIFontMetrics(forTextStyle: .body).scaledValue(for: 20, compatibleWith: traits)
        return style
    }
    static func editorFont(shell: Bool, traits: UITraitCollection? = nil) -> UIFont {
        OCFonts.register()
        let font = UIFont(name: shell ? "JetBrainsMonoNFM-Regular" : "Inter-Regular", size: 13) ?? UIFont.preferredFont(forTextStyle: .body)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font, compatibleWith: traits)
    }
}
public struct OCAttachmentChip: View {
    let name: String
    let mime: String
    let data: Data?
    let base64: String?
    let url: URL?
    let remove: (() -> Void)?
    @State private var thumbnail: UIImage?
    public init(name: String, mime: String, data: Data? = nil, base64: String? = nil, url: URL? = nil, remove: (() -> Void)? = nil) {
        self.name = name; self.mime = mime; self.data = data; self.base64 = base64; self.url = url; self.remove = remove
    }
    public var body: some View {
        HStack(spacing: OCSpacing.xs) {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: OCComposerMetrics.thumbnailWidth, height: OCComposerMetrics.thumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: OCRadius.md)).accessibilityLabel(name)
            } else {
                VStack(alignment: .leading, spacing: OCSpacing.xxs) {
                    Text(name).lineLimit(1)
                    Text(mime == "application/pdf" ? "PDF" : mime.hasPrefix("image/") ? "Image" : "Text").foregroundStyle(OCColor.textMuted)
                }.font(OCType.small).padding(OCSpacing.sm)
            }
            if let remove { OCIconButton("Remove attachment", icon: "outline-xmark", action: remove).accessibilityHint(name) }
        }.background(OCColor.layer2, in: RoundedRectangle(cornerRadius: OCRadius.md))
            .task(id: Source(data: data, base64: base64, url: url)) {
                guard mime.hasPrefix("image/") else { return }
                thumbnail = await Self.decode(data: data, base64: base64, url: url).map { UIImage(cgImage: $0) }
            }
    }
    private struct Source: Equatable { let data: Data?; let base64: String?; let url: URL? }
    @concurrent private static func decode(data: Data?, base64: String?, url: URL?) async -> CGImage? {
        guard let bytes = data ?? base64.flatMap({ Data(base64Encoded: $0) }) ?? url.flatMap({ try? Data(contentsOf: $0) }),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 174] as CFDictionary)
    }
}
#endif

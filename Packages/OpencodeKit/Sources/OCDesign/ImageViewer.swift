#if os(iOS)
import Photos
import SwiftUI
import UIKit
import OCRender

/// An image in the transcript, from the user or from a tool. Tapping opens it full screen to zoom, save or share.
public struct OCTranscriptImage: View {
    let image: TranscriptImage
    @State private var decoded: UIImage?
    @State private var open = false
    public init(_ image: TranscriptImage) { self.image = image }
    public var body: some View {
        Button { open = decoded != nil } label: {
            Group {
                if let decoded {
                    Image(uiImage: decoded).resizable().scaledToFit()
                        .frame(maxWidth: min(OCImageMetrics.inlineWidth, decoded.size.width), maxHeight: OCImageMetrics.inlineHeight)
                } else {
                    OCLabel(image.name, icon: "photo").font(OCType.small).padding(OCSpacing.sm)
                }
            }.clipShape(RoundedRectangle(cornerRadius: OCRadius.md))
                .overlay(RoundedRectangle(cornerRadius: OCRadius.md).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
        }.buttonStyle(.plain).accessibilityLabel(image.name).accessibilityHint(localized("Opens the image to zoom, save or share"))
            .accessibilityIdentifier("transcriptImage")
            .task(id: image.id) { decoded = await Self.decode(image.base64) }
            .fullScreenCover(isPresented: $open) {
                if let decoded { OCImageViewer(image: decoded, name: image.name) { open = false } }
            }
    }
    @concurrent static func decode(_ base64: String) async -> UIImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)?.preparingForDisplay()
    }
}

public enum OCImageMetrics {
    public static let inlineWidth: CGFloat = 280
    public static let inlineHeight: CGFloat = 220
}

/// Full screen: pinch or double-tap to zoom, drag to pan; save to Photos (add-only access) or share.
public struct OCImageViewer: View {
    let image: UIImage
    let name: String
    let close: () -> Void
    @State private var scale: CGFloat = 1
    @State private var settled: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragged: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: String?
    public init(image: UIImage, name: String, close: @escaping () -> Void) { self.image = image; self.name = name; self.close = close }
    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Image(uiImage: image).resizable().scaledToFit()
                    .scaleEffect(scale).offset(x: offset.width + dragged.width, y: offset.height + dragged.height)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(MagnifyGesture().onChanged { scale = max(1, min(8, settled * $0.magnification)) }
                        .onEnded { _ in settled = scale; if scale == 1 { offset = .zero } })
                    .simultaneousGesture(DragGesture().onChanged { if scale > 1 { dragged = $0.translation } }
                        .onEnded { value in if scale > 1 { offset.width += value.translation.width; offset.height += value.translation.height }; dragged = .zero })
                    .onTapGesture(count: 2) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: OCMotion.fast)) {
                            scale = scale > 1 ? 1 : 2.5; settled = scale; if scale == 1 { offset = .zero }
                        }
                    }
                    .accessibilityLabel(name).accessibilityAddTraits(.isImage)
                    .accessibilityZoomAction { action in
                        scale = max(1, min(8, action.direction == .zoomIn ? scale * 1.5 : scale / 1.5)); settled = scale
                    }
            }.background(OCColor.backgroundDeep)
                .overlay(alignment: .bottom) {
                    if let status { Text(status).font(OCType.small).padding(OCSpacing.md).background(OCColor.layer2, in: Capsule()).padding(OCSpacing.lg).ocAnnounce(status, initial: true) }
                }
                .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(localized("Done"), action: close).accessibilityIdentifier("closeImage") }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { Task { await save() } } label: { OCIcon("download") }.accessibilityLabel(localized("Save to Photos")).accessibilityIdentifier("saveImage")
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(name, image: Image(uiImage: image))) { OCIcon("share") }
                            .accessibilityLabel(localized("Share image")).accessibilityIdentifier("shareImage")
                    }
                }
        }.ocTheme()
    }
    private func save() async {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            status = localized("Photos access is off. Allow adding photos in Settings."); return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { [image] in _ = PHAssetChangeRequest.creationRequestForAsset(from: image) }
            status = localized("Saved to Photos")
        } catch { status = localized("Could not save the image") }
    }
}
#endif

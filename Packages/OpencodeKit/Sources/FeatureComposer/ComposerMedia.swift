#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import OCModels

enum ComposerMedia {
    @concurrent static func read(_ url: URL) async throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= AttachmentProcessing.maximumBytes else { throw AttachmentError.tooLarge }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
    static func data(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? AttachmentError.unsupported) }
            }
        }
    }
}
struct ComposerCamera: UIViewControllerRepresentable {
    var received: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ComposerCamera
        init(_ parent: ComposerCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.received((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1)); parent.dismiss()
        }
    }
}
#endif

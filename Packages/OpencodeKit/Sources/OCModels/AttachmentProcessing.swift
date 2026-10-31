import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreparedAttachment: Sendable {
    public let data: Data
    public let mime: String
    public let name: String
    public var dataURL: String { "data:\(mime);base64,\(data.base64EncodedString())" }
}
public enum AttachmentError: Error, LocalizedError, Sendable {
    case tooLarge, unsupported, invalidImage
    public var errorDescription: String? {
        switch self {
        case .tooLarge: localized("Each attachment must be 20 MiB or smaller.")
        case .unsupported: localized("Attach an image, PDF or text file. The server drops audio, video and other binary files.")
        case .invalidImage: localized("This image could not be read.")
        }
    }
}
public enum AttachmentProcessing {
    public static let maximumBytes = 20 * 1024 * 1024
    @concurrent public static func prepare(_ data: Data, mime: String, name: String) async throws -> PreparedAttachment {
        guard data.count <= maximumBytes else { throw AttachmentError.tooLarge }
        if data.starts(with: Data("%PDF-".utf8)) { return .init(data: data, mime: "application/pdf", name: name) }
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2_000,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AttachmentError.invalidImage }
            let png = (type as String) == UTType.png.identifier
            let outputType = png ? UTType.png : UTType.jpeg
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, outputType.identifier as CFString, 1, nil) else { throw AttachmentError.invalidImage }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw AttachmentError.invalidImage }
            guard output.length <= maximumBytes else { throw AttachmentError.tooLarge }
            let convertedName = (name as NSString).deletingPathExtension + (png ? ".png" : ".jpg")
            return .init(data: output as Data, mime: png ? "image/png" : "image/jpeg", name: convertedName)
        }
        if !mime.hasPrefix("audio/"), !mime.hasPrefix("video/"), !data.contains(0), String(data: data, encoding: .utf8) != nil {
            return .init(data: data, mime: "text/plain", name: name)
        }
        throw AttachmentError.unsupported
    }
}

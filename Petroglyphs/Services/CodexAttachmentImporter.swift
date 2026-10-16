import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct CodexImportedImage {
    let data: Data
    let name: String
    let mimeType: String
}

enum CodexAttachmentImporter {
    static let maximumCount = 4
    static let maximumImageBytes = 10 * 1_024 * 1_024
    static let maximumTotalBytes = 24 * 1_024 * 1_024

    enum ImportError: LocalizedError {
        case unsupported, tooLarge, tooMany, totalTooLarge
        var errorDescription: String? {
            switch self {
            case .unsupported: "Choose a PNG, JPEG, or another supported image."
            case .tooLarge: "Each image must be 10 MB or smaller."
            case .tooMany: "You can attach up to 4 images per message."
            case .totalTooLarge: "The images in one message must total 24 MB or less."
            }
        }
    }

    static func normalize(_ data: Data, name: String = "Image") throws -> CodexImportedImage {
        guard data.count <= maximumImageBytes else { throw ImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImportError.unsupported }
        let hasAlpha = [CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo)
        let uiImage = UIImage(cgImage: image)
        guard let encoded = hasAlpha ? uiImage.pngData() : uiImage.jpegData(compressionQuality: 0.9) else {
            throw ImportError.unsupported
        }
        guard encoded.count <= maximumImageBytes else { throw ImportError.tooLarge }
        let originalName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let cleanName = originalName.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\\" }
        let basename = cleanName.isEmpty ? "Image" : String(String.UnicodeScalarView(cleanName).prefix(120))
        return CodexImportedImage(data: encoded, name: basename + (hasAlpha ? ".png" : ".jpg"), mimeType: hasAlpha ? "image/png" : "image/jpeg")
    }

    static func image(from provider: NSItemProvider) async throws -> CodexImportedImage {
        let type = [UTType.png.identifier, UTType.jpeg.identifier, UTType.image.identifier]
            .first { provider.hasItemConformingToTypeIdentifier($0) }
        guard let type else { throw ImportError.unsupported }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? ImportError.unsupported) }
            }
        }
        return try normalize(data, name: provider.suggestedName ?? "Pasted image")
    }
}

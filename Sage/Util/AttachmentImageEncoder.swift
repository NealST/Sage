//
//  AttachmentImageEncoder.swift
//  Sage
//
//  Downscales local images for the current-turn vision part.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum AttachmentImageEncoder {
    static let maxDimension: CGFloat = 2048
    static let maxBytes = 4_000_000

    /// OpenAI-compatible `data:image/jpeg;base64,…` URL, or nil when the file
    /// cannot be encoded under the size cap.
    static func dataURL(for url: URL) -> String? {
        guard let jpeg = jpegData(for: url), jpeg.count <= maxBytes else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    static func canEncode(_ url: URL) -> Bool {
        jpegData(for: url) != nil
    }

    static func thumbnailData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = thumbnail(from: source, maxDimension: 96)
        else { return nil }
        return encodeJPEG(image, quality: 0.72)
    }

    static func jpegData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let dimensions = [2048, 1536, 1024, 768]
        let qualities = [0.82, 0.68, 0.52, 0.40]
        for dimension in dimensions {
            guard let image = thumbnail(from: source, maxDimension: dimension) else { continue }
            for quality in qualities {
                if let data = encodeJPEG(image, quality: quality), data.count <= maxBytes {
                    return data
                }
            }
        }
        return nil
    }

    private static func thumbnail(
        from source: CGImageSource,
        maxDimension: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

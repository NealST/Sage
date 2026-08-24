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

    static func jpegData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

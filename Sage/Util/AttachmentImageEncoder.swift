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
    static let maxDimension: CGFloat = 2_048
    static let maxBytes = 4_000_000
    private static let cacheLimit = 12
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var jpegCache: [String: Data] = [:]
    nonisolated(unsafe) private static var cacheOrder: [String] = []

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

    static func pngData(from sourceData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let image = thumbnail(from: source, maxDimension: 4_096)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Conservative OpenAI-compatible high-detail estimate after provider image scaling.
    static func estimatedVisionTokenCost(for url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let widthValue = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightValue = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return 800 }
        var width = max(widthValue.doubleValue, 1)
        var height = max(heightValue.doubleValue, 1)
        let longestScale = min(2_048 / max(width, height), 1)
        width *= longestScale
        height *= longestScale
        let shortestScale = min(768 / min(width, height), 1)
        width *= shortestScale
        height *= shortestScale
        let tiles = max(Int(ceil(width / 512)) * Int(ceil(height / 512)), 1)
        return 85 + 170 * tiles
    }

    static func jpegData(for url: URL) -> Data? {
        let key = cacheKey(for: url)
        if let key, let cached = cachedData(for: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let dimensions = [2_048, 1_536, 1_024, 768]
        let qualities = [0.82, 0.68, 0.52, 0.40]
        for dimension in dimensions {
            guard let image = thumbnail(from: source, maxDimension: dimension) else { continue }
            for quality in qualities {
                if let data = encodeJPEG(image, quality: quality), data.count <= maxBytes {
                    if let key { store(data, for: key) }
                    return data
                }
            }
        }
        return nil
    }

    private static func cacheKey(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return "\(url.resolvingSymlinksInPath().path)|\(size)|\(modified.timeIntervalSince1970)"
    }

    private static func cachedData(for key: String) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return jpegCache[key]
    }

    private static func store(_ data: Data, for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        jpegCache[key] = data
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit {
            jpegCache.removeValue(forKey: cacheOrder.removeFirst())
        }
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

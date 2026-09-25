//
//  image_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/image/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Image loading, resizing, and encoding for prompt image preparation.
//  Upstream uses the Rust `image` crate for decode/resize/encode. Sage uses
//  macOS-native CoreGraphics and AppKit. The cache, resize heuristics, and
//  data-URL handling are faithfully ported; the pixel-level encoding path
//  uses CGImage → NSBitmapImageRep.
//
//  R4a: upstream `lib.rs` → `image_lib.swift` (basename dedup).
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import CryptoKit

// MARK: - Constants

private let dataURLPrefix = "data:"
public let promptImagePatchSize: UInt32 = 32
public let maxDimension: UInt32 = 2048
public let maxPromptImageInputBytes: Int = 1024 * 1024 * 1024
private let maxImageCacheBytes = 64 * 1024 * 1024

// MARK: - EncodedImage

public struct EncodedImage: Sendable {
    public let bytes: Data
    public let mime: String
    public let sourceWidth: UInt32
    public let sourceHeight: UInt32
    public let width: UInt32
    public let height: UInt32

    public func intoDataURL() -> String {
        dataURLFromBytes(mime: mime, bytes: bytes)
    }
}

/// Wraps image bytes in a data URL without decoding or validating them.
public func dataURLFromBytes(mime: String, bytes: Data) -> String {
    let encoded = bytes.base64EncodedString()
    return "data:\(mime);base64,\(encoded)"
}

// MARK: - Prompt image mode

public enum PromptImageMode: Equatable, Hashable, Sendable {
    case resizeToFit
    case original
    case resizeWithLimits(PromptImageResizeLimits)

    /// Resize policy for high-detail prompt images.
    public static let highDetail = PromptImageMode.resizeWithLimits(
        PromptImageResizeLimits(maxDimension: 2048, maxPatches: 2500)
    )
    /// Resize policy for original-detail prompt images.
    public static let originalDetail = PromptImageMode.resizeWithLimits(
        PromptImageResizeLimits(maxDimension: 6000, maxPatches: 10_000)
    )
}

public struct PromptImageResizeLimits: Equatable, Hashable, Sendable {
    public var maxDimension: UInt32
    public var maxPatches: Int

    public init(maxDimension: UInt32, maxPatches: Int) {
        self.maxDimension = maxDimension
        self.maxPatches = maxPatches
    }
}

// MARK: - Image cache

private struct ImageCacheKey: Hashable {
    let digest: Data
    let mode: PromptImageMode
}

private let imageCacheLock = NSLock()
private var imageCache: [(key: ImageCacheKey, value: EncodedImage)] = []
private let maxCacheEntries = 32

private func cachedImage(for key: ImageCacheKey) -> EncodedImage? {
    imageCacheLock.lock()
    defer { imageCacheLock.unlock() }
    return imageCache.first(where: { $0.key == key })?.value
}

private func insertCachedImage(_ image: EncodedImage, for key: ImageCacheKey) {
    guard image.bytes.count <= maxImageCacheBytes else { return }
    imageCacheLock.lock()
    defer { imageCacheLock.unlock() }
    imageCache.append((key: key, value: image))
    var totalBytes = imageCache.reduce(0) { $0 + $1.value.bytes.count }
    while totalBytes > maxImageCacheBytes, !imageCache.isEmpty {
        let removed = imageCache.removeFirst()
        totalBytes -= removed.value.bytes.count
    }
    if imageCache.count > maxCacheEntries {
        imageCache.removeFirst()
    }
}

private func sha1Digest(_ data: Data) -> Data {
    Data(Insecure.SHA1.hash(data: data))
}

// MARK: - Public API

public func loadForPromptBytes(
    path: String,
    fileBytes: Data,
    mode: PromptImageMode
) throws -> EncodedImage {
    let key = ImageCacheKey(digest: sha1Digest(fileBytes), mode: mode)
    if let cached = cachedImage(for: key) {
        return cached
    }
    let image = try loadForPromptBytesUncached(path: path, fileBytes: fileBytes, mode: mode)
    insertCachedImage(image, for: key)
    return image
}

#if canImport(AppKit)
private func loadForPromptBytesUncached(
    path: String,
    fileBytes: Data,
    mode: PromptImageMode
) throws -> EncodedImage {
    guard let nsImage = NSImage(data: fileBytes) else {
        throw ImageProcessingError.decode(
            path: path,
            source: NSError(domain: "ImageProcessing", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "cannot decode image"])
        )
    }

    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw ImageProcessingError.decode(
            path: path,
            source: NSError(domain: "ImageProcessing", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "cannot obtain CGImage"])
        )
    }

    let sourceWidth = UInt32(cgImage.width)
    let sourceHeight = UInt32(cgImage.height)

    let mime = detectMime(from: fileBytes) ?? "image/png"
    let canPreserve = ["image/png", "image/jpeg", "image/webp"].contains(mime)

    switch mode {
    case .resizeToFit where sourceWidth > maxDimension || sourceHeight > maxDimension:
        let (tw, th) = fitDimensions(sourceWidth, sourceHeight, maxDim: maxDimension)
        let resized = resizeCGImage(cgImage, to: (Int(tw), Int(th)))
        let encoded = try encodeToData(resized, preferredMime: canPreserve ? mime : "image/png")
        return EncodedImage(
            bytes: encoded.data, mime: encoded.mime,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            width: tw, height: th
        )

    case .resizeWithLimits(let limits):
        let (tw, th) = promptImageOutputDimensionsForLimits(
            sourceWidth, sourceHeight, limits: limits
        )
        if (tw, th) != (sourceWidth, sourceHeight) {
            let resized = resizeCGImage(cgImage, to: (Int(tw), Int(th)))
            let encoded = try encodeToData(resized, preferredMime: canPreserve ? mime : "image/png")
            return EncodedImage(
                bytes: encoded.data, mime: encoded.mime,
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                width: tw, height: th
            )
        }
        fallthrough

    default:
        if canPreserve {
            return EncodedImage(
                bytes: fileBytes, mime: mime,
                sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                width: sourceWidth, height: sourceHeight
            )
        }
        let encoded = try encodeToData(cgImage, preferredMime: "image/png")
        return EncodedImage(
            bytes: encoded.data, mime: encoded.mime,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
            width: sourceWidth, height: sourceHeight
        )
    }
}

// MARK: - Helpers

private func detectMime(from data: Data) -> String? {
    guard data.count >= 4 else { return nil }
    let header = [UInt8](data.prefix(8))
    if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
    if header.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
    if header.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
    if header.count >= 4, header[0...3] == [0x52, 0x49, 0x46, 0x46],
       data.count >= 12, [UInt8](data[8..<12]) == [0x57, 0x45, 0x42, 0x50]
    {
        return "image/webp"
    }
    return nil
}

private func fitDimensions(_ w: UInt32, _ h: UInt32, maxDim: UInt32) -> (UInt32, UInt32) {
    let scale = Double(maxDim) / Double(max(w, h))
    return (max(1, UInt32((Double(w) * scale).rounded())),
            max(1, UInt32((Double(h) * scale).rounded())))
}

private func resizeCGImage(_ image: CGImage, to size: (Int, Int)) -> CGImage {
    let context = CGContext(
        data: nil, width: size.0, height: size.1,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size.0, height: size.1))
    return context.makeImage()!
}

private func encodeToData(
    _ image: CGImage, preferredMime: String
) throws -> (data: Data, mime: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    let type: NSBitmapImageRep.FileType
    let mime: String
    switch preferredMime {
    case "image/jpeg":
        type = .jpeg; mime = "image/jpeg"
    case "image/gif":
        type = .gif; mime = "image/gif"
    default:
        type = .png; mime = "image/png"
    }
    guard let data = rep.representation(using: type, properties: [:]) else {
        throw ImageProcessingError.encode(
            format: mime,
            source: NSError(domain: "ImageProcessing", code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "encoding failed"])
        )
    }
    return (data, mime)
}
#else
private func loadForPromptBytesUncached(
    path: String, fileBytes: Data, mode: PromptImageMode
) throws -> EncodedImage {
    throw ImageProcessingError.unsupportedImageFormat(mime: "unavailable (non-macOS)")
}
#endif

// MARK: - Data URL loading

public func loadDataURLForPrompt(
    imageURL: String,
    mode: PromptImageMode
) throws -> EncodedImage {
    try loadDataURLForPromptWith(imageURL: imageURL, mode: mode, load: loadForPromptBytes)
}

public func loadDataURLForPromptUncached(
    imageURL: String,
    mode: PromptImageMode
) throws -> EncodedImage {
    try loadDataURLForPromptWith(imageURL: imageURL, mode: mode, load: loadForPromptBytesUncached)
}

private func loadDataURLForPromptWith(
    imageURL: String,
    mode: PromptImageMode,
    load: (String, Data, PromptImageMode) throws -> EncodedImage
) throws -> EncodedImage {
    guard imageURL.lowercased().hasPrefix(dataURLPrefix),
          let rest = imageURL.dropFirst(dataURLPrefix.count) as Substring?
    else {
        throw ImageProcessingError.invalidDataUrl(reason: "missing data: prefix")
    }

    guard let commaIndex = rest.firstIndex(of: ",") else {
        throw ImageProcessingError.invalidDataUrl(reason: "missing comma separator")
    }
    let metadata = rest[..<commaIndex]
    let encoded = rest[rest.index(after: commaIndex)...]

    guard metadata.split(separator: ";").contains(where: {
        $0.lowercased() == "base64"
    }) else {
        throw ImageProcessingError.invalidDataUrl(reason: "only base64 data URLs are supported")
    }

    guard encoded.count <= maxPromptImageInputBytes else {
        throw ImageProcessingError.imageTooLarge(
            representation: "base64 payload",
            size: encoded.count,
            max: maxPromptImageInputBytes
        )
    }

    guard let fileBytes = Data(base64Encoded: String(encoded)) else {
        throw ImageProcessingError.invalidDataUrl(reason: "invalid base64 payload")
    }

    guard fileBytes.count <= maxPromptImageInputBytes else {
        throw ImageProcessingError.imageTooLarge(
            representation: "decoded input",
            size: fileBytes.count,
            max: maxPromptImageInputBytes
        )
    }

    return try load("<data-url-image>", fileBytes, mode)
}

// MARK: - Prompt image dimension calculation

func promptImageOutputDimensionsForLimits(
    _ width: UInt32, _ height: UInt32, limits: PromptImageResizeLimits
) -> (UInt32, UInt32) {
    let w = max(width, 1)
    let h = max(height, 1)
    if promptImageDimensionsFit(w, h, limits: limits) {
        return (w, h)
    }

    let maxDimScale = min(Double(limits.maxDimension) / Double(max(w, h)), 1.0)
    let sw = max(UInt32((Double(w) * maxDimScale).rounded()), 1)
    let sh = max(UInt32((Double(h) * maxDimScale).rounded()), 1)
    if promptImageDimensionsFit(sw, sh, limits: limits) {
        return (sw, sh)
    }

    let wf = Double(sw)
    let hf = Double(sh)
    let ps = Double(promptImagePatchSize)
    var scale = (ps * ps * Double(limits.maxPatches) / wf / hf).squareRoot()
    let scaledPatchesWide = wf * scale / ps
    let scaledPatchesHigh = hf * scale / ps
    scale *= min(
        scaledPatchesWide.rounded(.down) / scaledPatchesWide,
        scaledPatchesHigh.rounded(.down) / scaledPatchesHigh
    )
    return (
        max(UInt32((wf * scale).rounded(.down)), 1),
        max(UInt32((hf * scale).rounded(.down)), 1)
    )
}

private func promptImageDimensionsFit(
    _ width: UInt32, _ height: UInt32, limits: PromptImageResizeLimits
) -> Bool {
    let patchesWide = (width + promptImagePatchSize - 1) / promptImagePatchSize
    let patchesHigh = (height + promptImagePatchSize - 1) / promptImagePatchSize
    let patchCount = UInt64(patchesWide) * UInt64(patchesHigh)
    return width <= limits.maxDimension
        && height <= limits.maxDimension
        && patchCount <= UInt64(limits.maxPatches)
}

//
//  compact_remote_v2_images.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_remote_v2_images.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Image+label groups stay atomic. Audio is uncharged and kept.
//  Original-detail inline images decode data-URL + PNG/JPEG/GIF headers
//  (rust uses the image crate). Non-original is always 7373 bytes.
//

import CodexProtocol
import CodexUtils
import Foundation
import os

public let resizedImageBytesEstimate = 7373
public let originalImageMaxPatches = 10_000
public let originalImagePatchSize = 32

private let originalImageEstimateCache = OSAllocatedUnfairLock(initialState: [String: Int?]())
private let originalImageEstimateCacheLimit = 32

public enum CompactRemoteV2Images {
    public static func shouldDropImages(occupancy: Double) -> Bool {
        occupancy >= 0.85
    }
}

public func parseBase64ImageDataURL(_ url: String) -> String? {
    let prefix = "data:"
    guard url.count >= prefix.count,
          url.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
    else { return nil }
    guard let comma = url.firstIndex(of: ",") else { return nil }
    let metadata = url[url.startIndex..<comma]
    let payload = url[url.index(after: comma)...]
    let metadataWithoutScheme = metadata.dropFirst(prefix.count)
    let parts = metadataWithoutScheme.split(separator: ";", omittingEmptySubsequences: false)
    let mimeType = parts.first.map(String.init) ?? ""
    let hasBase64 = parts.dropFirst().contains { $0.caseInsensitiveCompare("base64") == .orderedSame }
    guard mimeType.prefix(6).caseInsensitiveCompare("image/") == .orderedSame, hasBase64 else {
        return nil
    }
    return String(payload)
}

public func estimateImageBytes(_ imageURL: String, detail: ImageDetail?) -> Int {
    if detail == .original {
        return estimateOriginalImageBytes(imageURL) ?? resizedImageBytesEstimate
    }
    return resizedImageBytesEstimate
}

public func estimateImageReferenceBytes(_ image: ImageReference, detail: ImageDetail?) -> Int {
    switch image {
    case .inline(let url):
        return estimateImageBytes(url, detail: detail)
    case .file:
        if detail == .original {
            return approxBytesForTokens(originalImageMaxPatches)
        }
        return resizedImageBytesEstimate
    }
}

func estimateOriginalImageBytes(_ imageURL: String) -> Int? {
    originalImageEstimateCache.withLock { cache -> Int? in
        if let cached = cache[imageURL] { return cached }
        let estimated = decodeOriginalImageByteEstimate(imageURL)
        if cache.count >= originalImageEstimateCacheLimit, let first = cache.keys.first {
            cache.removeValue(forKey: first)
        }
        cache[imageURL] = estimated
        return estimated
    }
}

func decodeOriginalImageByteEstimate(_ imageURL: String) -> Int? {
    guard let payload = parseBase64ImageDataURL(imageURL),
          let bytes = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]),
          let (width, height) = imageDimensions(from: bytes)
    else { return nil }
    let patch = originalImagePatchSize
    let patchesWide = (width + patch - 1) / patch
    let patchesHigh = (height + patch - 1) / patch
    let patchCount = min(patchesWide * patchesHigh, originalImageMaxPatches)
    return approxBytesForTokens(max(patchCount, 0))
}

func imageDimensions(from data: Data) -> (Int, Int)? {
    if data.count >= 24,
       data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        let width = int32BE(data, 16)
        let height = int32BE(data, 20)
        if width > 0, height > 0 { return (width, height) }
    }
    if data.count >= 10, data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
        let width = Int(data[6]) | (Int(data[7]) << 8)
        let height = Int(data[8]) | (Int(data[9]) << 8)
        if width > 0, height > 0 { return (width, height) }
    }
    if data.count >= 4, data[0] == 0xFF, data[1] == 0xD8 {
        return jpegDimensions(data)
    }
    return nil
}

func int32BE(_ data: Data, _ offset: Int) -> Int {
    (Int(data[offset]) << 24)
        | (Int(data[offset + 1]) << 16)
        | (Int(data[offset + 2]) << 8)
        | Int(data[offset + 3])
}

func jpegDimensions(_ data: Data) -> (Int, Int)? {
    var offset = 2
    while offset + 3 < data.count {
        guard data[offset] == 0xFF else { return nil }
        let marker = data[offset + 1]
        offset += 2
        if marker == 0xD9 || marker == 0xDA { return nil }
        guard offset + 1 < data.count else { return nil }
        let length = (Int(data[offset]) << 8) | Int(data[offset + 1])
        if length < 2 { return nil }
        if (0xC0...0xC3).contains(marker), offset + 6 < data.count {
            let height = (Int(data[offset + 3]) << 8) | Int(data[offset + 4])
            let width = (Int(data[offset + 5]) << 8) | Int(data[offset + 6])
            if width > 0, height > 0 { return (width, height) }
            return nil
        }
        offset += length
    }
    return nil
}

public func contentItemTokenCount(_ item: ContentItem) -> Int {
    switch item {
    case .inputText(let text), .outputText(let text):
        return approxTokenCount(text)
    case .inputImage(let image, let detail):
        return Int(clamping: approxTokensFromByteCountI64(Int64(estimateImageReferenceBytes(image, detail: detail))))
    case .inputAudio:
        return 0
    }
}

public func truncateMessageToTokenBudget(
    _ envelope: ResponseItemEnvelope,
    maxTokens: Int
) -> ResponseItemEnvelope? {
    var item = envelope.item
    guard var content = toAnnotatedContent(&item) else { return nil }
    var remaining = maxTokens
    var retained: [AnnotatedContent] = []
    while !content.isEmpty {
        let last = content.count - 1
        let imageIndex: Int?
        switch content[last].content {
        case .inputImage:
            imageIndex = last
        case .inputText(let text)
            where isImageCloseTagText(text)
            && last > 0
            && {
                if case .inputImage = content[last - 1].content { return true }
                return false
            }():
            imageIndex = last - 1
        default:
            imageIndex = nil
        }
        if let imageIndex {
            var hasOpenTag = false
            if imageIndex > 0, case .inputText(let text) = content[imageIndex - 1].content {
                hasOpenTag = isLocalImageOpenTagText(text) || isImageOpenTagText(text)
            }
            let start = imageIndex - (hasOpenTag ? 1 : 0)
            let tokenCount = content[start...].reduce(0) { $0 + contentItemTokenCount($1.content) }
            let fits = tokenCount <= remaining
            remaining = fits ? remaining - tokenCount : 0
            let drained = Array(content[start...])
            content.removeSubrange(start...)
            if fits {
                retained.append(contentsOf: drained.reversed())
            }
            continue
        }
        var part = content.removeLast()
        switch part.content {
        case .inputText(let text), .outputText(let text):
            if remaining == 0 { continue }
            let tokenCount = approxTokenCount(text)
            var kept = text
            if tokenCount <= remaining {
                remaining -= tokenCount
            } else {
                kept = truncateTextByTokens(text, tokenBudget: remaining)
                remaining = 0
            }
            if kept.isEmpty { continue }
            if case .inputText = part.content {
                part.content = .inputText(text: kept)
            } else {
                part.content = .outputText(text: kept)
            }
            retained.append(part)
        case .inputAudio:
            retained.append(part)
        case .inputImage:
            continue
        }
    }
    if retained.isEmpty { return nil }
    retained.reverse()
    guard setAnnotatedContent(&item, retained) else { return nil }
    return ResponseItemEnvelope(item, metadata: envelope.metadata)
}

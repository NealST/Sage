//
//  error.swift
//  CodexUtils
//
//  Port of codex-rs/utils/image/src/error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Image processing error types. Upstream uses the Rust `image` crate's
//  `ImageError` and `ImageFormat` types. Swift uses native `CGImage` /
//  `NSImage` for image handling, so the error enum is adapted to reference
//  platform-neutral descriptions instead of crate-specific types.
//

import Foundation

public enum ImageProcessingError: Error, CustomStringConvertible, Sendable {
    case read(path: String, source: any Error)
    case decode(path: String, source: any Error)
    case encode(format: String, source: any Error)
    case unsupportedImageFormat(mime: String)
    case invalidDataUrl(reason: String)
    case imageTooLarge(representation: String, size: Int, max: Int)

    public var description: String {
        switch self {
        case let .read(path, source):
            return "failed to read image at \(path): \(source)"
        case let .decode(path, source):
            return "failed to decode image at \(path): \(source)"
        case let .encode(format, source):
            return "failed to encode image as \(format): \(source)"
        case let .unsupportedImageFormat(mime):
            return "unsupported image `\(mime)`"
        case let .invalidDataUrl(reason):
            return "invalid image data URL: \(reason)"
        case let .imageTooLarge(representation, size, max):
            return "image \(representation) is too large (\(size) bytes; max \(max) bytes)"
        }
    }

    /// Whether this error indicates the image data itself is invalid/corrupt.
    public var isInvalidImage: Bool {
        if case .decode = self { return true }
        return false
    }
}

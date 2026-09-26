//
//  image_resize_notice.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/image_resize_notice.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public enum ImageResizeNoticeSource: String, Equatable, Sendable {
    case user
    case tool
}

public struct ResizedImage: Equatable, Sendable {
    public var originalBytes: Int
    public var resizedBytes: Int
    public var width: Int?
    public var height: Int?

    public init(originalBytes: Int, resizedBytes: Int, width: Int? = nil, height: Int? = nil) {
        self.originalBytes = originalBytes
        self.resizedBytes = resizedBytes
        self.width = width
        self.height = height
    }
}

public struct ImageResizeNotice: ContextualUserFragment, Equatable, Sendable {
    public var source: ImageResizeNoticeSource
    public var images: [ResizedImage]

    public init(source: ImageResizeNoticeSource, images: [ResizedImage]) {
        self.source = source
        self.images = images
    }

    public var contentKind: ContentItemKind { ContentItemKind("images.resize_notice") }
    public var role: String { "developer" }
    public var openMarker: String { "<image_resize_notice>" }
    public var closeMarker: String { "</image_resize_notice>" }
    public var body: String {
        let rows = images.map { image in
            "resized \(image.originalBytes)B → \(image.resizedBytes)B"
        }.joined(separator: "; ")
        return "One or more \(source.rawValue) images were resized before the model request (\(rows))."
    }
}

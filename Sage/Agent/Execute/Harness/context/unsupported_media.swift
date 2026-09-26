//
//  unsupported_media.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/unsupported_media.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct UnsupportedMedia: ContextualUserFragment, Equatable, Sendable {
    public var text: String
    public var kind: String

    public static let image = UnsupportedMedia(
        text: "image content omitted because you do not support image input",
        kind: "images.unsupported"
    )
    public static let audio = UnsupportedMedia(
        text: "audio content omitted because you do not support audio input",
        kind: "audio.unsupported"
    )

    public init(text: String, kind: String) {
        self.text = text
        self.kind = kind
    }

    public var contentKind: ContentItemKind { ContentItemKind(kind) }
    public var role: String { "user" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { text }
}

//
//  fragment.swift
//  CodexContextFragments
//
//  Port of codex-rs/context-fragments/src/fragment.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `ContextualUserFragment` is a protocol (Rust trait). `into()` /
//  `into_boxed_response_item()` map to `asResponseItem()`. Type-level
//  `matches_text` / `type_markers` are static protocol requirements with
//  defaults. `openMarker` / `closeMarker` expose `markers()` so existing
//  CodexCore fragments can keep their stored surface.
//

import CodexProtocol
import Foundation

/// A rendered contextual fragment and the role that owns its annotated content.
public struct RenderedFragment: Equatable, Sendable {
    public var role: String
    public var content: AnnotatedContent

    /// Creates a rendered fragment without separating its role and annotated content.
    public init(role: String, content: AnnotatedContent) {
        self.role = role
        self.content = content
    }

    /// Returns the response role associated with this fragment.
    public func roleValue() -> String {
        role
    }

    /// Returns this fragment's model-visible content and classification.
    public func annotatedContent() -> AnnotatedContent {
        content
    }

    /// Separates the role and annotated content at an API boundary.
    public func intoParts() -> (String, AnnotatedContent) {
        (role, content)
    }
}

extension ResponseItem {
    public init(_ fragment: RenderedFragment) {
        let (role, annotated) = fragment.intoParts()
        let (content, contentKind) = annotated.intoParts()
        self = .message(
            id: nil,
            role: role,
            content: [content],
            phase: nil,
            internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough(
                contentItemKinds: [contentKind]
            )
        )
    }
}

/// Context payload that is injected as a message fragment.
///
/// Implementations own the response role and provide the exact fragment body.
/// Marked fragments also provide start/end markers used to recognize injected
/// context later. `render()` concatenates markers and body without adding
/// separators, so implementations should include any whitespace they need
/// between tags in `body`. Unmarked fragments should leave both markers empty,
/// in which case the default helpers render only the body and never match
/// arbitrary text.
public protocol ContextualUserFragment {
    var role: String { get }
    /// Returns a stable `<feature>.<name>` classification, using `generic` for shared fragments.
    var contentKind: ContentItemKind { get }
    /// Whether this fragment must be recorded as its own response item.
    var requiresSeparateMessage: Bool { get }
    var openMarker: String { get }
    var closeMarker: String { get }
    var body: String { get }

    static func typeMarkers() -> (String, String)
    static func matchesText(_ text: String) -> Bool
}

extension ContextualUserFragment {
    public var requiresSeparateMessage: Bool { false }

    public func markers() -> (String, String) {
        (openMarker, closeMarker)
    }

    public static func typeMarkers() -> (String, String) {
        ("", "")
    }

    public static func matchesText(_ text: String) -> Bool {
        let (startMarker, endMarker) = typeMarkers()
        return matchesMarkedText(startMarker: startMarker, endMarker: endMarker, text: text)
    }

    public func matchesText(_ text: String) -> Bool {
        Self.matchesText(text)
    }

    public func render() -> String {
        let (startMarker, endMarker) = markers()
        if startMarker.isEmpty && endMarker.isEmpty {
            return body
        }
        return "\(startMarker)\(body)\(endMarker)"
    }

    /// Compatibility alias for CodexCore callers (`renderedText()`).
    public func renderedText() -> String {
        render()
    }

    /// Renders the role, model-visible content, and classification together.
    public func renderFragment() -> RenderedFragment {
        RenderedFragment(
            role: role,
            content: AnnotatedContent.inputText(render(), kind: contentKind)
        )
    }

    public func asResponseItem() -> ResponseItem {
        ResponseItem(renderFragment())
    }
}

func matchesMarkedText(startMarker: String, endMarker: String, text: String) -> Bool {
    if startMarker.isEmpty || endMarker.isEmpty {
        return false
    }

    let leading = String(text.drop(while: { $0.isWhitespace }))
    let leadingBytes = Array(leading.utf8)
    let startBytes = Array(startMarker.utf8)
    guard leadingBytes.count >= startBytes.count else { return false }
    let startsWithMarker = asciiEqualsIgnoreCase(
        leadingBytes.prefix(startBytes.count),
        startBytes
    )

    let trimmed = String(leading.reversed().drop(while: { $0.isWhitespace }).reversed())
    let trimmedBytes = Array(trimmed.utf8)
    let endBytes = Array(endMarker.utf8)
    guard trimmedBytes.count >= endBytes.count else { return false }
    let endsWithMarker = asciiEqualsIgnoreCase(
        trimmedBytes.suffix(endBytes.count),
        endBytes
    )
    return startsWithMarker && endsWithMarker
}

private func asciiEqualsIgnoreCase<C: Collection>(_ lhs: C, _ rhs: [UInt8]) -> Bool
where C.Element == UInt8 {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { asciiLower($0) == asciiLower($1) }
}

private func asciiLower(_ byte: UInt8) -> UInt8 {
    (byte >= 65 && byte <= 90) ? byte &+ 32 : byte
}

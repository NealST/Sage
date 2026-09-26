//
//  annotated_content.swift
//  CodexContextFragments
//
//  Port of codex-rs/context-fragments/src/annotated_content.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

/// Model-visible content paired with its harness-owned classification.
public struct AnnotatedContent: Equatable, Sendable {
    public var content: ContentItem
    public var kind: ContentItemKind

    /// Creates content and its classification together.
    public init(content: ContentItem, kind: ContentItemKind) {
        self.content = content
        self.kind = kind
    }

    /// Creates model-visible input text and its classification together.
    public static func inputText(_ text: String, kind: ContentItemKind) -> AnnotatedContent {
        AnnotatedContent(content: .inputText(text: text), kind: kind)
    }

    /// Separates the content from its classification at an API boundary.
    public func intoParts() -> (ContentItem, ContentItemKind) {
        (content, kind)
    }
}

/// Takes a message's content together with its positional classifications.
///
/// Legacy messages, including persisted rollouts, may not have classifications.
/// Missing entries are classified as unknown so the message remains usable.
@discardableResult
public func toAnnotatedContent(_ item: inout ResponseItem) -> [AnnotatedContent]? {
    guard case .message(let id, let role, let content, let phase, var metadata) = item else {
        return nil
    }
    let kinds = metadata?.contentItemKinds ?? []
    if metadata != nil {
        metadata!.contentItemKinds = nil
    }
    var annotated: [AnnotatedContent] = []
    annotated.reserveCapacity(content.count)
    for (index, part) in content.enumerated() {
        let kind = index < kinds.count ? kinds[index] : ContentItemKind("unknown")
        annotated.append(AnnotatedContent(content: part, kind: kind))
    }
    item = .message(
        id: id,
        role: role,
        content: [],
        phase: phase,
        internalChatMessageMetadataPassthrough: metadata
    )
    return annotated
}

/// Replaces a message's content and positional classifications together.
@discardableResult
public func setAnnotatedContent(
    _ item: inout ResponseItem,
    _ annotatedContent: [AnnotatedContent]
) -> Bool {
    guard case .message(let id, let role, _, let phase, var metadata) = item else {
        return false
    }
    var updatedContent: [ContentItem] = []
    var contentItemKinds: [ContentItemKind] = []
    updatedContent.reserveCapacity(annotatedContent.count)
    contentItemKinds.reserveCapacity(annotatedContent.count)
    for annotated in annotatedContent {
        let (content, kind) = annotated.intoParts()
        updatedContent.append(content)
        contentItemKinds.append(kind)
    }
    if metadata == nil {
        metadata = InternalChatMessageMetadataPassthrough()
    }
    metadata!.contentItemKinds = contentItemKinds
    item = .message(
        id: id,
        role: role,
        content: updatedContent,
        phase: phase,
        internalChatMessageMetadataPassthrough: metadata
    )
    return true
}

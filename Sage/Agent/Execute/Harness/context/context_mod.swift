//
//  context_mod.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Context fragments injected into model input. `AdditionalContext*` and
//  the crate-level `ContextualUserFragment` live in CodexContextFragments;
//  this file keeps the CodexCore protocol used by world-state fragments.
//

import CodexProtocol
import Foundation

public let appsInstructionsOpenTag = "<apps_instructions>"
public let appsInstructionsCloseTag = "</apps_instructions>"
public let pluginsInstructionsOpenTag = "<plugins_instructions>"
public let pluginsInstructionsCloseTag = "</plugins_instructions>"
public let environmentsInstructionsOpenTag = "<environments_instructions>"
public let environmentsInstructionsCloseTag = "</environments_instructions>"

public protocol ContextualUserFragment {
    var contentKind: ContentItemKind { get }
    var role: String { get }
    var requiresSeparateMessage: Bool { get }
    var openMarker: String { get }
    var closeMarker: String { get }
    var body: String { get }
}

extension ContextualUserFragment {
    public var requiresSeparateMessage: Bool { false }

    public func renderedText() -> String {
        if openMarker.isEmpty && closeMarker.isEmpty {
            return body
        }
        return "\(openMarker)\(body)\(closeMarker)"
    }

    public func matchesText(_ text: String) -> Bool {
        if openMarker.isEmpty { return false }
        return text.contains(openMarker)
    }

    public func asResponseItem() -> ResponseItem {
        .message(
            id: nil,
            role: role,
            content: [.inputText(text: renderedText())],
            phase: nil,
            internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough(
                contentItemKinds: [contentKind]
            )
        )
    }
}

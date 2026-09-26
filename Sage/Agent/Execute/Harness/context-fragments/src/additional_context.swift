//
//  additional_context.swift
//  CodexContextFragments
//
//  Port of codex-rs/context-fragments/src/additional_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import CodexUtils
import Foundation

let MAX_ADDITIONAL_CONTEXT_VALUE_TOKENS = 1_000
let ADDITIONAL_CONTEXT_END_MARKER_SUFFIX = ">"
let ADDITIONAL_CONTEXT_START_MARKER_PREFIX = "<external_"

public struct AdditionalContextUserFragment: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension AdditionalContextUserFragment: ContextualUserFragment {
    public var role: String { "user" }

    public var contentKind: ContentItemKind {
        ContentItemKind("additional_content.\(key)")
    }

    public var openMarker: String { Self.typeMarkers().0 }
    public var closeMarker: String { Self.typeMarkers().1 }

    public static func typeMarkers() -> (String, String) {
        (ADDITIONAL_CONTEXT_START_MARKER_PREFIX, ADDITIONAL_CONTEXT_END_MARKER_SUFFIX)
    }

    public static func matchesText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rest = stripPrefix(trimmed, ADDITIONAL_CONTEXT_START_MARKER_PREFIX) else {
            return false
        }
        guard let split = rest.range(of: ADDITIONAL_CONTEXT_END_MARKER_SUFFIX) else {
            return false
        }
        let key = String(rest[..<split.lowerBound])
        let valueAndClose = String(rest[split.upperBound...])
        return valueAndClose.hasSuffix("</external_\(key)>")
    }

    public var body: String {
        additionalContextBody(key: key, value: value)
    }
}

public struct AdditionalContextDeveloperFragment: Equatable, Sendable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension AdditionalContextDeveloperFragment: ContextualUserFragment {
    public var role: String { "developer" }

    public var contentKind: ContentItemKind {
        ContentItemKind("additional_content.\(key)")
    }

    public var openMarker: String { Self.typeMarkers().0 }
    public var closeMarker: String { Self.typeMarkers().1 }

    public static func typeMarkers() -> (String, String) {
        ("", "")
    }

    public var body: String {
        additionalContextDeveloperBody(key: key, value: value)
    }
}

func additionalContextBody(key: String, value: String) -> String {
    let truncated = truncateMiddleWithTokenBudget(value, maxTokens: MAX_ADDITIONAL_CONTEXT_VALUE_TOKENS).0
    return "\(key)>\(truncated)</external_\(key)"
}

func additionalContextDeveloperBody(key: String, value: String) -> String {
    let truncated = truncateMiddleWithTokenBudget(value, maxTokens: MAX_ADDITIONAL_CONTEXT_VALUE_TOKENS).0
    return "<\(key)>\(truncated)</\(key)>"
}

private func stripPrefix(_ text: String, _ prefix: String) -> String? {
    text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : nil
}

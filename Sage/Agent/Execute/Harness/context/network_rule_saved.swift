//
//  network_rule_saved.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/network_rule_saved.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct NetworkRuleSaved: ContextualUserFragment, Equatable, Sendable {
    public var rule: String

    public init(rule: String) {
        self.rule = rule
    }

    public var contentKind: ContentItemKind { ContentItemKind("network.rule_saved") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { "Network rule saved: \(rule)" }
}

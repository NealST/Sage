//
//  legacy_unified_exec_process_limit_warning.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/legacy_unified_exec_process_limit_warning.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct LegacyUnifiedExecProcessLimitWarning: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("legacy.unified_exec_process_limit") }
    public var role: String { "user" }
    public var openMarker: String { "<legacy_unified_exec_process_limit_warning>" }
    public var closeMarker: String { "</legacy_unified_exec_process_limit_warning>" }
    public var body: String {
        "This thread was created when unified exec allowed fewer concurrent processes. Prefer finishing or polling existing processes before starting new ones."
    }
}

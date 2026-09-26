//
//  guardian_budget_omission.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_budget_omission.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct GuardianBudgetOmission: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("guardian.budget_omission") }
    public var role: String { "developer" }
    public var openMarker: String { "<guardian_budget_omission>" }
    public var closeMarker: String { "</guardian_budget_omission>" }
    public var body: String {
        "Guardian evidence was omitted because it exceeded the reviewer token budget."
    }
}

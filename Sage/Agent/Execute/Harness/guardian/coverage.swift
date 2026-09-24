//
//  coverage.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/coverage.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

enum GuardianScope: String, Sendable {
    case shell
    case fileChanges
    case network
    case permissions
    case mcp
}

extension GuardianApprovalRequest {
    var scope: GuardianScope {
        switch self {
        case .execCommand:
            return .shell
        case .applyPatch:
            return .fileChanges
        case .networkAccess:
            return .network
        }
    }
}

//
//  guardian_approved_action.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_approved_action.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Markers stay empty. The body is the manual-approval prefix plus the
//  pretty-printed approved action.
//

import CodexProtocol
import Foundation

public struct GuardianApprovedAction: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("guardian.approved_action") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String {
        let prefix =
            "The user has manually approved a specific action that was previously `Rejected`."
        return """
        \(prefix)

        Treat this as approval to perform that exact action in the same context in which it was originally requested.
        Do not assume this also authorizes similar operations with different payloads.

        Approved action:
        \(text)
        """
    }
}

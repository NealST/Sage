//
//  approved_command_prefix_saved.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/approved_command_prefix_saved.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public let approvedCommandPrefixSavedMessagePrefix = "Approved command prefix saved:"

public struct ApprovedCommandPrefixSaved: ContextualUserFragment, Equatable, Sendable {
    public var prefixes: String

    public init(prefixes: String) {
        self.prefixes = prefixes
    }

    public var contentKind: ContentItemKind { ContentItemKind("permissions.approved_command_prefix_saved") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { "\(approvedCommandPrefixSavedMessagePrefix)\n\(prefixes)" }
}

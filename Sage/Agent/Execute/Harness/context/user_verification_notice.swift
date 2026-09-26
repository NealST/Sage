//
//  user_verification_notice.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/user_verification_notice.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct UserVerificationNotice: ContextualUserFragment, Equatable, Sendable {
    public init() {}
    public var contentKind: ContentItemKind { ContentItemKind("user_verification.notice") }
    public var role: String { "developer" }
    public var openMarker: String { "<user_verification_notice>" }
    public var closeMarker: String { "</user_verification_notice>" }
    public var body: String { "User verification is required. Please respond in the app." }
}

//
//  attestation.swift
//  CodexCore
//
//  Port of codex-rs/core/src/attestation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Host integration boundary. `http::HeaderValue` maps to `String`.
//

import CodexProtocol
import Foundation

public let xOaiAttestationHeader = "x-oai-attestation"

/// Request context that host integrations can use when deciding whether to
/// generate an attestation header value.
public struct AttestationContext: Equatable, Sendable {
    /// Thread whose upstream request is being prepared.
    public var threadId: ThreadId

    public init(threadId: ThreadId) {
        self.threadId = threadId
    }
}

/// Host integration boundary for just-in-time attestation header values.
public protocol AttestationProvider: Sendable {
    func headerForRequest(_ context: AttestationContext) async -> String?
}

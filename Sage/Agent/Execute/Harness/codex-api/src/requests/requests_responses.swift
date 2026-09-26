//
//  requests_responses.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/requests/responses.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SPM unique basename. `Zstd` is accepted but treated as `None`
//  (no compression crate).
//

import Foundation

public enum Compression: Equatable, Sendable {
    case none
    case zstd
}

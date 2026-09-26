//
//  guardian_context_mode.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_context_mode.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Reviewer policy carried by each history snapshot. Checkpoint compatibility
//  against `codex_history` waits for the rollout crate.
//

import Foundation

public enum GuardianContextMode: String, Equatable, Sendable {
    case legacy
    case threadOwned

    public static let `default`: GuardianContextMode = .threadOwned
}

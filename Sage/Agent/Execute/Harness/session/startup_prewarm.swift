//
//  startup_prewarm.swift
//  Sage
//
//  Port of codex-rs/core/src/session/startup_prewarm.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

final class SessionStartupPrewarmHandle: @unchecked Sendable {
    var cancelled = false

    init() {}

    func cancel() { cancelled = true }
}

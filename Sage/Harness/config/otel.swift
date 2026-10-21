//
//  otel.swift
//  Sage
//
//  Port of codex-rs/core/src/config/otel.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

struct OtelConfig: Equatable, Sendable {
    var enabled: Bool

    init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

//
//  metrics.swift
//  Sage
//
//  Port of codex-rs/core/src/config/metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

struct MetricsConfig: Equatable, Sendable {
    var serviceName: String?

    init(serviceName: String? = nil) {
        self.serviceName = serviceName
    }
}

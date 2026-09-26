//
//  extension_metrics.swift
//  Sage
//
//  Port of codex-rs/core/src/session/extension_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

extension Session {
    func recordExtensionMetric(_ name: String, value: Double) {}
}

//
//  network_config.swift
//  Sage
//
//  Port of codex-rs/core/src/config/network_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

struct NetworkConfig: Equatable, Sendable {
    var enforceResidency: Bool
    var proxyEnabled: Bool

    init(enforceResidency: Bool = false, proxyEnabled: Bool = false) {
        self.enforceResidency = enforceResidency
        self.proxyEnabled = proxyEnabled
    }
}

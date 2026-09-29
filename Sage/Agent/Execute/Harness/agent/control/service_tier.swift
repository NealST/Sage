//
//  service_tier.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/service_tier.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

extension LocalAgentControl {
    public func rootServiceTier() -> String? {
        runtime.rootServiceTier()
    }

    public func setRootServiceTier(_ serviceTier: String?) {
        runtime.setRootServiceTier(serviceTier)
    }
}

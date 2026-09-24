//
//  reviewer_config.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/reviewer_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  The reviewer uses the review-role model and the Guardian contract.
//  Live network rules are attached when a proxy spec is active.
//

import Foundation

struct GuardianReviewerConfig: Sendable {
    var model: String
    var instructions: String
    var network: NetworkProxySpec?

    static func resolve(
        settings: ModelSettingsSnapshot,
        network: NetworkProxySpec? = nil
    ) -> GuardianReviewerConfig {
        GuardianReviewerConfig(
            model: settings.model,
            instructions: GuardianPrompt.system,
            network: network
        )
    }
}

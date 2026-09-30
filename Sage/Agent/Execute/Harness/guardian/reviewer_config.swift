//
//  reviewer_config.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/reviewer_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolves the review-role model, Guardian contract, optional extra
//  policy, and live network rules before HUD review. Catalog prewarm /
//  isolated session spawn stay out.
//

import Foundation

struct GuardianReviewerConfig: Sendable {
    var settings: ModelSettingsSnapshot
    var instructions: String
    var network: NetworkProxySpec?

    var model: String { settings.model }

    static func resolve(
        settings: ModelSettingsSnapshot,
        extraPolicy: String? = nil,
        network: NetworkProxySpec? = nil
    ) -> GuardianReviewerConfig {
        var instructions = GuardianPrompt.system
        if let extra = extraPolicy?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extra.isEmpty {
            instructions += "\n\n" + extra
        }
        return GuardianReviewerConfig(
            settings: settings,
            instructions: instructions,
            network: network
        )
    }

    /// Review-role snapshot plus Seatbelt network rules for network-scope actions.
    @MainActor
    static func resolveLive(
        scope: GuardianScope? = nil,
        extraPolicy: String? = nil
    ) -> GuardianReviewerConfig {
        resolve(
            settings: ModelSettings.shared.snapshot(for: .review),
            extraPolicy: extraPolicy,
            network: scope == .network ? .seatbelt : nil
        )
    }
}

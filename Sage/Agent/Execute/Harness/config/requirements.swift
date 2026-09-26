//
//  requirements.swift
//  Sage
//
//  Port of codex-rs/core/src/config/requirements.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

struct FeatureRequirements: Equatable, Sendable {
    var required: Set<Feature>
    var forbidden: Set<Feature>

    init(required: Set<Feature> = [], forbidden: Set<Feature> = []) {
        self.required = required
        self.forbidden = forbidden
    }
}

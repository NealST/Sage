//
//  bedrock.swift
//  Sage
//
//  Port of codex-rs/core/src/config/edit/bedrock.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

struct BedrockConfigEdit: Equatable, Sendable {
    var region: String?

    init(region: String? = nil) {
        self.region = region
    }
}

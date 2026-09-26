//
//  rollout_reconstruction.swift
//  Sage
//
//  Port of codex-rs/core/src/session/rollout_reconstruction.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexCore
import CodexProtocol
import Foundation

enum RolloutReconstruction {
    static func items(from history: ContextManager) -> [ResponseItem] {
        history.items.map(\.item)
    }
}

//
//  thread_settings.swift
//  Sage
//
//  Port of codex-rs/core/src/session/thread_settings.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

extension Session {
    func applyThreadSettings(_ settings: StepSettings) {
        state.sessionConfiguration.stepSettings = settings
    }
}

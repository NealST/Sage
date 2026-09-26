//
//  inject.swift
//  Sage
//
//  Port of codex-rs/core/src/session/inject.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

extension Session {
    func inject(_ item: ResponseItem) {
        state.recordItems([item])
    }
}

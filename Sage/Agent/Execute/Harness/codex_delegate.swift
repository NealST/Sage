//
//  codex_delegate.swift
//  CodexCore
//
//  Port of codex-rs/core/src/codex_delegate.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Host-side delegate hooks. Realtime and ChatGPT login stay deferred.
//

import CodexProtocol
import Foundation

public protocol CodexDelegate: AnyObject, Sendable {
    func threadDidEmitEvent(_ event: Event)
}

public extension CodexDelegate {
    func threadDidEmitEvent(_ event: Event) {}
}

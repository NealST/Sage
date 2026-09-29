//
//  runtime.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  LocalAgentRuntime lives in control.swift. ThreadManager upgrade and
//  live-thread queries wait on Session.
//

import CodexProtocol
import Foundation

extension LocalAgentRuntime {
    public func upgradeThreadManager() throws {
        throw CodexErr.unsupportedOperation("LocalAgentRuntime.upgrade waits on ThreadManager")
    }
}

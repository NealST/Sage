//
//  runtime.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  LocalAgentRuntime lives in control.swift. ThreadManager attach uses a
//  weak back-reference so the registry can outlive individual controls.
//

import CodexProtocol
import Foundation

extension LocalAgentRuntime {
    public func attachThreadManager(_ manager: ThreadManager) {
        self.manager = manager
    }

    @discardableResult
    public func upgradeThreadManager() throws -> ThreadManager {
        guard let manager else {
            throw CodexErr.unsupportedOperation("thread manager dropped")
        }
        return manager
    }
}

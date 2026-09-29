//
//  user_authorization.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/user_authorization.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Bounded root evidence projection waits on retained history / guardian
//  context. Root-id lookup is available from the registry.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func rootUserAuthorization(threadId: ThreadId) async -> GuardianRootSnapshot? {
        guard let rootThreadId = runtime.registry.agentIdForPath(.root()) else { return nil }
        if rootThreadId == threadId { return nil }
        return nil
    }
}

//
//  interrupt.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/interrupt.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Root/self/path validation is faithful. Runtime interrupt records
//  `.interrupted` on the mailbox; ThreadManager stop is still pending.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func interruptSpawnedAgent(caller: ThreadId, target: ThreadId) async throws -> AgentInfo {
        let receiverAgent = try runtime.ensureAgentKnown(target)
        if receiverAgent.agentPath?.isRoot == true {
            throw CodexErr.unsupportedOperation("root is not a spawned agent")
        }
        if target == caller {
            throw CodexErr.unsupportedOperation(
                "an agent cannot interrupt itself; return your result and let the parent interrupt you if needed"
            )
        }
        guard receiverAgent.agentPath != nil else {
            throw CodexErr.unsupportedOperation("target agent is missing an agent_path")
        }
        let snapshot = try await inspectAgent(target)
        do {
            try await interruptAgent(target)
        } catch let error as CodexErr {
            switch error.detailsValue() {
            case .threadNotFound, .internalAgentDied:
                break
            default:
                throw error
            }
        }
        return snapshot
    }

    public func interruptAgent(_ target: ThreadId) async throws {
        _ = try runtime.ensureAgentKnown(target)
        runtime.delivery.setStatus(target, .interrupted)
    }
}

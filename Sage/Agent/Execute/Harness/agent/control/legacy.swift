//
//  legacy.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/legacy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Registry close/release is live. Persisted spawn-edge updates and
//  Session shutdown still wait on ThreadManager.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func shutdownLiveAgent(agentId: ThreadId) async throws -> String {
        runtime.delivery.setStatus(agentId, .shutdown)
        runtime.delivery.remove(agentId)
        runtime.residency.remove(agentId)
        runtime.registry.releaseSpawnedThread(agentId)
        return ""
    }

    public func closeAgent(_ agentId: ThreadId) async throws -> AgentInfo {
        let snapshot = try await inspectAgent(agentId)
        _ = try await shutdownAgentTree(agentId)
        return snapshot
    }

    public func shutdownAgentTree(_ agentId: ThreadId) async throws -> String {
        let descendantIds = liveThreadSpawnDescendants(agentId)
        let result = try await shutdownLiveAgent(agentId: agentId)
        for descendantId in descendantIds {
            _ = try await shutdownLiveAgent(agentId: descendantId)
        }
        return result
    }

    public func liveThreadSpawnDescendants(_ parent: ThreadId) -> [ThreadId] {
        guard let parentPath = runtime.registry.agentMetadataForThread(parent)?.agentPath else {
            return []
        }
        let prefix = "\(parentPath.asStr)/"
        return runtime.registry.liveAgents().compactMap { metadata in
            guard let path = metadata.agentPath, let threadId = metadata.agentId else {
                return nil
            }
            return path.asStr.hasPrefix(prefix) ? threadId : nil
        }
        .sorted { $0.description < $1.description }
    }
}

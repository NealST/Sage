//
//  runtime_context.swift
//  CodexCore
//
//  Port of methods on rust `LocalAgentControl` in
//  codex-rs/core/src/agent/control.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `register_session_root` / `ensure_agent_known` live on LocalAgentRuntime
//  in control.swift. Live subtree listing and environment-context subagent
//  formatting use ThreadManager spawn edges; agent-graph-store persistence
//  is still skipped.
//

import CodexProtocol
import Foundation

let maxEnvironmentSubagents = 8
let maxEnvironmentSubagentBytes = 1_024

extension LocalAgentRuntime {
    public func listLiveAgentSubtreeThreadIds(_ agentId: ThreadId) async throws -> [ThreadId] {
        var threadIds = [agentId]
        threadIds.append(contentsOf: try await liveThreadSpawnDescendants(agentId))
        return threadIds
    }

    public func formatLegacyEnvironmentContextSubagents(
        parentThreadId: ThreadId,
        multiAgentVersion: MultiAgentVersion
    ) async -> String {
        if multiAgentVersion != .v2 {
            guard let agents = try? await openThreadSpawnChildren(parentThreadId) else {
                return ""
            }
            return agents.map { threadId, metadata in
                let reference = metadata.agentPath?.name ?? threadId.description
                return formatSubagentContextLine(
                    agentReference: reference,
                    agentNickname: metadata.agentNickname
                )
            }
            .joined(separator: "\n")
        }

        guard let parentPath = registry.agentMetadataForThread(parentThreadId)?.agentPath else {
            return ""
        }
        let parentPrefix = "\(parentPath.asStr)/"
        var agentPaths = registry.liveAgents().compactMap(\.agentPath).filter { path in
            guard let name = path.asStr.stripPrefix(parentPrefix) else { return false }
            return !name.contains("/")
        }
        let loadedPaths = Set(
            ((try? await openThreadSpawnChildren(parentThreadId)) ?? []).compactMap(\.1.agentPath)
        )
        agentPaths.sort { lhs, rhs in
            let leftUnloaded = !loadedPaths.contains(lhs)
            let rightUnloaded = !loadedPaths.contains(rhs)
            if leftUnloaded != rightUnloaded {
                return !leftUnloaded && rightUnloaded
            }
            return lhs < rhs
        }

        var lines: [String] = []
        var renderedBytes = "  <subagents>\n  </subagents>\n".count
        for agentPath in agentPaths {
            if lines.count == maxEnvironmentSubagents {
                break
            }
            let line = "<agent name=\"\(agentPath)\" />"
            let lineBytes = "    \n".count + line.count
            if renderedBytes + lineBytes <= maxEnvironmentSubagentBytes {
                renderedBytes += lineBytes
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    func openThreadSpawnChildren(
        _ parentThreadId: ThreadId
    ) async throws -> [(ThreadId, AgentMetadata)] {
        var childrenByParent = try await liveThreadSpawnChildren()
        return childrenByParent.removeValue(forKey: parentThreadId) ?? []
    }

    func liveThreadSpawnChildren() async throws -> [ThreadId: [(ThreadId, AgentMetadata)]] {
        let manager = try upgradeThreadManager()
        var childrenByParent: [ThreadId: [(ThreadId, AgentMetadata)]] = [:]
        for (parentThreadId, childThreadId) in await manager.listLiveThreadSpawnEdges() {
            childrenByParent[parentThreadId, default: []].append(
                (
                    childThreadId,
                    registry.agentMetadataForThread(childThreadId) ?? AgentMetadata()
                )
            )
        }
        return childrenByParent
    }

    func liveThreadSpawnDescendants(_ rootThreadId: ThreadId) async throws -> [ThreadId] {
        var childrenByParent = try await liveThreadSpawnChildren()
        var descendants: [ThreadId] = []
        var stack = Array(
            (childrenByParent.removeValue(forKey: rootThreadId) ?? []).map(\.0).reversed()
        )
        while let threadId = stack.popLast() {
            descendants.append(threadId)
            if let children = childrenByParent.removeValue(forKey: threadId) {
                for childThreadId in children.map(\.0).reversed() {
                    stack.append(childThreadId)
                }
            }
        }
        return descendants
    }
}

extension LocalAgentControl {
    public func listLiveAgentSubtreeThreadIds(_ agentId: ThreadId) async throws -> [ThreadId] {
        try await runtime.listLiveAgentSubtreeThreadIds(agentId)
    }

    public func formatEnvironmentContextSubagents(
        parentThreadId: ThreadId,
        multiAgentVersion: MultiAgentVersion
    ) async -> String {
        await runtime.formatLegacyEnvironmentContextSubagents(
            parentThreadId: parentThreadId,
            multiAgentVersion: multiAgentVersion
        )
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

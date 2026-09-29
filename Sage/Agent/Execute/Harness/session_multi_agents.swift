//
//  session_multi_agents.swift
//  CodexCore
//
//  Port of codex-rs/core/src/session/multi_agents.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `resolve_usage_hints` is faithful against a Config stand-in.
//  StepContext-backed usage_hint_text / effective_multi_agent_mode wait
//  on Session.
//

import CodexProtocol
import Foundation

public let DEFAULT_MULTI_AGENT_V2_MAX_CONCURRENT_THREADS_PER_SESSION = 4
public let DEFAULT_MULTI_AGENT_V2_MIN_WAIT_TIMEOUT_MS: Int64 = 10_000
public let DEFAULT_MULTI_AGENT_V2_MAX_WAIT_TIMEOUT_MS: Int64 = 3600 * 1000
public let DEFAULT_MULTI_AGENT_V2_DEFAULT_WAIT_TIMEOUT_MS: Int64 = 30_000
public let DEFAULT_MULTI_AGENT_V2_TOOL_NAMESPACE = "collaboration"
public let HARD_MAX_MULTI_AGENT_V2_TIMEOUT_MS = DEFAULT_MULTI_AGENT_V2_MAX_WAIT_TIMEOUT_MS

public struct MultiAgentV2Config: Equatable, Sendable {
    public var maxConcurrentThreadsPerSession: Int
    public var minWaitTimeoutMs: Int64
    public var maxWaitTimeoutMs: Int64
    public var defaultWaitTimeoutMs: Int64
    public var usageHintText: String?
    public var rootAgentUsageHintText: String?
    public var subagentUsageHintText: String?
    public var subagentDeveloperInstructions: String?
    public var multiAgentModeHintText: String?
    public var toolNamespace: String?
    public var hideSpawnAgentMetadata: Bool
    public var exposeSpawnAgentModelOverrides: Bool
    public var waitAgentEnabled: Bool
    public var disableDirectMessage: Bool
    public var messageBoardInMemory: Bool
    public var nonCodeModeOnly: Bool

    public init(
        maxConcurrentThreadsPerSession: Int = DEFAULT_MULTI_AGENT_V2_MAX_CONCURRENT_THREADS_PER_SESSION,
        minWaitTimeoutMs: Int64 = DEFAULT_MULTI_AGENT_V2_MIN_WAIT_TIMEOUT_MS,
        maxWaitTimeoutMs: Int64 = DEFAULT_MULTI_AGENT_V2_MAX_WAIT_TIMEOUT_MS,
        defaultWaitTimeoutMs: Int64 = DEFAULT_MULTI_AGENT_V2_DEFAULT_WAIT_TIMEOUT_MS,
        usageHintText: String? = nil,
        rootAgentUsageHintText: String? = nil,
        subagentUsageHintText: String? = nil,
        subagentDeveloperInstructions: String? = nil,
        multiAgentModeHintText: String? = nil,
        toolNamespace: String? = DEFAULT_MULTI_AGENT_V2_TOOL_NAMESPACE,
        hideSpawnAgentMetadata: Bool = true,
        exposeSpawnAgentModelOverrides: Bool = true,
        waitAgentEnabled: Bool = true,
        disableDirectMessage: Bool = false,
        messageBoardInMemory: Bool = false,
        nonCodeModeOnly: Bool = true
    ) {
        self.maxConcurrentThreadsPerSession = maxConcurrentThreadsPerSession
        self.minWaitTimeoutMs = minWaitTimeoutMs
        self.maxWaitTimeoutMs = maxWaitTimeoutMs
        self.defaultWaitTimeoutMs = defaultWaitTimeoutMs
        self.usageHintText = usageHintText
        self.rootAgentUsageHintText = rootAgentUsageHintText
        self.subagentUsageHintText = subagentUsageHintText
        self.subagentDeveloperInstructions = subagentDeveloperInstructions
        self.multiAgentModeHintText = multiAgentModeHintText
        self.toolNamespace = toolNamespace
        self.hideSpawnAgentMetadata = hideSpawnAgentMetadata
        self.exposeSpawnAgentModelOverrides = exposeSpawnAgentModelOverrides
        self.waitAgentEnabled = waitAgentEnabled
        self.disableDirectMessage = disableDirectMessage
        self.messageBoardInMemory = messageBoardInMemory
        self.nonCodeModeOnly = nonCodeModeOnly
    }
}

public struct ResolvedMultiAgentMessages: Equatable, Sendable {
    public var root: String
    public var subagent: String
    public var rootCatalogOverride: Bool
    public var subagentCatalogOverride: Bool

    public init(
        root: String = "",
        subagent: String = "",
        rootCatalogOverride: Bool = false,
        subagentCatalogOverride: Bool = false
    ) {
        self.root = root
        self.subagent = subagent
        self.rootCatalogOverride = rootCatalogOverride
        self.subagentCatalogOverride = subagentCatalogOverride
    }
}

public func resolveUsageHints(
    config: MultiAgentV2Config,
    multiAgentMessages: ResolvedMultiAgentMessages,
    omitUpdatePlanInstructions: Bool
) -> ResolvedMultiAgentV2UsageHints {
    func resolveRole(configured: String?, base: String, catalogOverride: Bool) -> MultiAgentRoleInstructions? {
        if let configured {
            return configured.isEmpty ? nil : .configured(configured)
        }
        if base.isEmpty { return nil }
        return .composed(
            base: base,
            marked: catalogOverride,
            omitUpdatePlanInstructions: omitUpdatePlanInstructions,
            maxConcurrency: config.maxConcurrentThreadsPerSession,
            waitAgentEnabled: config.waitAgentEnabled,
            exposeModelOverrides: config.exposeSpawnAgentModelOverrides
        )
    }

    return ResolvedMultiAgentV2UsageHints(
        root: resolveRole(
            configured: config.rootAgentUsageHintText,
            base: multiAgentMessages.root,
            catalogOverride: multiAgentMessages.rootCatalogOverride
        ),
        subagent: resolveRole(
            configured: config.subagentUsageHintText,
            base: multiAgentMessages.subagent,
            catalogOverride: multiAgentMessages.subagentCatalogOverride
        )
    )
}

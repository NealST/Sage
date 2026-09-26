//
//  responses_metadata.swift
//  CodexCore
//
//  Port of codex-rs/core/src/responses_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Compaction analytics enums are local stand-ins (otel/analytics crate
//  waits for Phase 10). Header maps are [String: String]. JSON uses
//  CodexUtils toAsciiJsonString / toJsonStringBounded.
//

import CodexProtocol
import CodexUtils
import Foundation

public let installationIdKey = "installation_id"
public let sessionIdKey = "session_id"
public let threadIdKey = "thread_id"
public let agentNameKey = "agent_name"
public let turnIdKey = "turn_id"
public let windowIdKey = "window_id"
public let windowNumberKey = "window_number"
public let contextWindowIdKey = "context_window_id"
public let requestKindKey = "request_kind"
public let compactionKey = "compaction"
public let legacyCodeModeToolNamesKey = "code_mode_tool_names"
public let toolNamespacesInfoKey = "tool_namespaces_info"
public let turnStartedAtUnixMsKey = "turn_started_at_unix_ms"
public let historyIngestRequestedKey = "history_ingest_requested"
public let analyticsEnabledKey = "analytics_enabled"
public let mcpAttributionClientMetadataKey = "mcp_attribution"
public let maxMcpAttributionBytes = 16 * 1024

public let forkedFromThreadIdKey = "forked_from_thread_id"
public let forkedFromOrdinalExclusiveKey = "forked_from_ordinal_exclusive"
public let parentThreadIdKey = "parent_thread_id"
public let parentTurnIdKey = "parent_turn_id"
public let rootTurnIdKey = "root_turn_id"
public let subagentKindKey = "subagent_kind"
public let threadSourceKey = "thread_source"
public let turnTriggerKey = "turn_trigger"
public let sandboxKey = "sandbox"
public let sandboxModeKey = "sandbox_mode"
public let autoReviewEnabledKey = "auto_review_enabled"
public let nodeReplAutoReviewRequiredKey = "node_repl_auto_review_required"
public let nodeReplDisabledKey = "node_repl_disabled"
public let workspacesKey = "workspaces"

let reservedMetadataKeys: [String] = [
    "guardian_credits_requested",
    mcpAttributionClientMetadataKey,
    installationIdKey,
    xCodexInstallationIdHeader,
    sessionIdKey,
    threadIdKey,
    agentNameKey,
    turnIdKey,
    windowIdKey,
    windowNumberKey,
    contextWindowIdKey,
    xCodexWindowIdHeader,
    xCodexTurnMetadataHeader,
    xCodexParentThreadIdHeader,
    xOpenaiSubagentHeader,
    requestKindKey,
    compactionKey,
    legacyCodeModeToolNamesKey,
    toolNamespacesInfoKey,
    turnStartedAtUnixMsKey,
    historyIngestRequestedKey,
    analyticsEnabledKey,
    forkedFromThreadIdKey,
    forkedFromOrdinalExclusiveKey,
    parentThreadIdKey,
    parentTurnIdKey,
    rootTurnIdKey,
    subagentKindKey,
    threadSourceKey,
    turnTriggerKey,
    sandboxKey,
    sandboxModeKey,
    autoReviewEnabledKey,
    nodeReplAutoReviewRequiredKey,
    nodeReplDisabledKey,
    workspacesKey,
]

let backwardCompatibleReservedMetadataKeys: [String] = [
    windowNumberKey,
    forkedFromOrdinalExclusiveKey,
    analyticsEnabledKey,
]

let maxExtraMetadataEntries = 16
let maxExtraMetadataKeyBytes = 64
public let maxExtraMetadataValueBytes = 128

public enum CompactionTrigger: String, Codable, Equatable, Sendable {
    case auto
    case user
}

public enum CompactionReason: String, Codable, Equatable, Sendable {
    case contextWindow
    case overflow
}

public enum CompactionImplementation: String, Codable, Equatable, Sendable {
    case local
    case remote
    case remoteV2 = "remote_v2"
}

public enum CompactionPhase: String, Codable, Equatable, Sendable {
    case start
    case complete
}

public enum CompactionStrategy: String, Codable, Equatable, Sendable {
    case memento
}

public struct CompactionTurnMetadata: Codable, Equatable, Sendable {
    public var trigger: CompactionTrigger
    public var reason: CompactionReason
    public var implementation: CompactionImplementation
    public var phase: CompactionPhase
    public var strategy: CompactionStrategy

    public init(
        trigger: CompactionTrigger,
        reason: CompactionReason,
        implementation: CompactionImplementation,
        phase: CompactionPhase
    ) {
        self.trigger = trigger
        self.reason = reason
        self.implementation = implementation
        self.phase = phase
        self.strategy = .memento
    }
}

public enum CodexResponsesRequestKind: Equatable, Sendable {
    case turn
    case prewarm
    case compaction(CompactionTurnMetadata)
    case memory

    func metadata() -> (String, CompactionTurnMetadata?) {
        switch self {
        case .turn: return ("turn", nil)
        case .prewarm: return ("prewarm", nil)
        case .compaction(let metadata): return ("compaction", metadata)
        case .memory: return ("memory", nil)
        }
    }

    func hasThreadIdentity() -> Bool {
        if case .memory = self { return false }
        return true
    }
}

public struct TurnMetadataWorkspace: Codable, Equatable, Sendable {
    public var associatedRemoteUrls: [String: SanitizedGitUrl]?
    public var latestGitCommitHash: String?
    public var hasChanges: Bool?

    enum CodingKeys: String, CodingKey {
        case associatedRemoteUrls = "associated_remote_urls"
        case latestGitCommitHash = "latest_git_commit_hash"
        case hasChanges = "has_changes"
    }

    public init(
        associatedRemoteUrls: [String: SanitizedGitUrl]? = nil,
        latestGitCommitHash: String? = nil,
        hasChanges: Bool? = nil
    ) {
        self.associatedRemoteUrls = associatedRemoteUrls
        self.latestGitCommitHash = latestGitCommitHash
        self.hasChanges = hasChanges
    }
}

public typealias TurnToolNamespacesInfo = [String: TurnToolNamespaceInfo]

public struct TurnToolNamespaceInfo: Codable, Equatable, Sendable {
    public var name: String
    public var functions: [String: TurnToolFunctionInfo]

    public init(name: String, functions: [String: TurnToolFunctionInfo] = [:]) {
        self.name = name
        self.functions = functions
    }
}

public struct TurnToolFunctionInfo: Codable, Equatable, Sendable {
    public var name: String
    public var direct: Bool
    public var codeModeName: String?
    public var deferred: Bool
    public var source: TurnToolSource

    enum CodingKeys: String, CodingKey {
        case name, direct, deferred, source
        case codeModeName = "code_mode_name"
    }

    public init(
        name: String,
        direct: Bool,
        codeModeName: String? = nil,
        deferred: Bool,
        source: TurnToolSource
    ) {
        self.name = name
        self.direct = direct
        self.codeModeName = codeModeName
        self.deferred = deferred
        self.source = source
    }
}

public enum TurnToolSource: Equatable, Sendable {
    case harness
    case mcp(serverName: String)
}

extension TurnToolSource: Codable {
    private enum CodingKeys: String, CodingKey { case kind, serverName = "server_name" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "harness":
            self = .harness
        case "mcp":
            self = .mcp(serverName: try container.decode(String.self, forKey: .serverName))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "unknown TurnToolSource \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .harness:
            try container.encode("harness", forKey: .kind)
        case .mcp(let serverName):
            try container.encode("mcp", forKey: .kind)
            try container.encode(serverName, forKey: .serverName)
        }
    }
}

public struct CodexResponsesMetadata: Sendable {
    public var parentResponseId: String?
    public var installationId: String
    public var sessionId: String
    public var threadId: String
    public var agentName: String?
    public var turnId: String?
    public var routingHint: String?
    public var windowId: String
    public var windowNumber: UInt64?
    public var contextWindowId: UUID?
    public var requestKind: CodexResponsesRequestKind?
    public var forkedFromThreadId: ThreadId?
    public var forkedFromOrdinalExclusive: UInt64?
    public var parentThreadId: ThreadId?
    public var parentTurnId: String?
    public var rootTurnId: String?
    public var subagentHeader: String?
    public var subagentKind: String?
    public var threadSource: ThreadSource?
    public var turnTrigger: String?
    public var sandbox: String?
    public var sandboxMode: String?
    public var autoReviewEnabled: Bool?
    public var nodeReplAutoReviewRequired: Bool?
    public var nodeReplDisabled: Bool?
    public var workspaces: [String: TurnMetadataWorkspace]
    public var toolNamespacesInfo: TurnToolNamespacesInfo?
    public var turnStartedAtUnixMs: Int64?
    public var historyIngestRequested: Bool?
    public var analyticsEnabled: Bool?
    public var mcpAttribution: McpAttribution?
    public var extra: [String: String]

    public init(
        installationId: String,
        sessionId: String,
        threadId: String,
        windowId: String
    ) {
        self.installationId = installationId
        self.sessionId = sessionId
        self.threadId = threadId
        self.windowId = windowId
        self.workspaces = [:]
        self.extra = [:]
    }

    public func hasTurnMetadata() -> Bool {
        requestKind != nil
    }

    public func turnMetadataJSON() -> String? {
        try? toAsciiJsonString(turnMetadataPayload())
    }

    public func clientMetadata(includeInternal: Bool) -> [String: String] {
        var clientMetadata: [String: String] = [
            xCodexInstallationIdHeader: installationId,
            sessionIdKey: sessionId,
            threadIdKey: threadId,
            xCodexWindowIdHeader: windowId,
        ]
        if let turnId {
            clientMetadata[turnIdKey] = turnId
        }
        if let subagentHeader {
            clientMetadata[xOpenaiSubagentHeader] = subagentHeader
        }
        if let parentThreadId {
            clientMetadata[xCodexParentThreadIdHeader] = parentThreadId.description
        }
        if let parentTurnId {
            clientMetadata[parentTurnIdKey] = parentTurnId
        }
        if let rootTurnId {
            clientMetadata[rootTurnIdKey] = rootTurnId
        }
        if hasTurnMetadata(), let json = turnMetadataJSON() {
            clientMetadata[xCodexTurnMetadataHeader] = json
        }
        if includeInternal, let attribution = mcpAttribution {
            let serialized: String
            do {
                serialized = try toJsonStringBounded(attribution, maxBytes: maxMcpAttributionBytes)
            } catch is JsonByteLimitExceededError {
                serialized = #"{"status":"attribution_error","error_reason":"payload_too_large"}"#
            } catch {
                serialized = #"{"status":"attribution_error","error_reason":"serialization_failed"}"#
            }
            clientMetadata[mcpAttributionClientMetadataKey] = serialized
        }
        return clientMetadata
    }

    public func compatibilityHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        insertHeader(&headers, xCodexWindowIdHeader, windowId)
        if hasTurnMetadata() {
            var payload = turnMetadataPayload()
            payload.toolNamespacesInfo = nil
            if let json = try? toAsciiJsonString(payload) {
                insertHeader(&headers, xCodexTurnMetadataHeader, json)
            }
        }
        if let parentThreadId {
            insertHeader(&headers, xCodexParentThreadIdHeader, parentThreadId.description)
        }
        if let subagentHeader {
            insertHeader(&headers, xOpenaiSubagentHeader, subagentHeader)
        }
        return headers
    }

    func turnMetadataPayload() -> CodexTurnMetadataPayload {
        let kind = requestKind
        let (requestKindValue, compaction) = kind.map { $0.metadata() } ?? (nil, nil)
        let hasThreadIdentity = kind?.hasThreadIdentity() ?? true
        let hasRequestIdentity = kind?.hasThreadIdentity() ?? false
        return CodexTurnMetadataPayload(
            installationId: hasRequestIdentity ? installationId : nil,
            sessionId: hasThreadIdentity ? sessionId : nil,
            threadId: hasThreadIdentity ? threadId : nil,
            agentName: hasThreadIdentity ? agentName : nil,
            turnId: turnId,
            windowId: hasRequestIdentity ? windowId : nil,
            windowNumber: hasRequestIdentity ? windowNumber : nil,
            contextWindowId: hasRequestIdentity ? contextWindowId : nil,
            requestKind: requestKindValue,
            forkedFromThreadId: forkedFromThreadId,
            forkedFromOrdinalExclusive: forkedFromOrdinalExclusive,
            parentThreadId: parentThreadId,
            parentTurnId: parentTurnId,
            rootTurnId: rootTurnId,
            subagentKind: subagentKind,
            threadSource: threadSource,
            turnTrigger: turnTrigger,
            sandbox: sandbox,
            sandboxMode: sandboxMode,
            autoReviewEnabled: autoReviewEnabled,
            nodeReplAutoReviewRequired: nodeReplAutoReviewRequired,
            nodeReplDisabled: nodeReplDisabled,
            workspaces: workspaces.isEmpty ? nil : workspaces,
            toolNamespacesInfo: toolNamespacesInfo,
            turnStartedAtUnixMs: turnStartedAtUnixMs,
            historyIngestRequested: historyIngestRequested,
            analyticsEnabled: analyticsEnabled,
            compaction: compaction,
            extra: extra
        )
    }
}

public func subagentHeaderValue(_ sessionSource: SessionSource) -> String? {
    switch sessionSource {
    case .subAgent(.review): return "review"
    case .subAgent(.compact): return "compact"
    case .subAgent(.memoryConsolidation): return "memory_consolidation"
    case .subAgent(.threadSpawn): return "collab_spawn"
    case .subAgent(.other(let label)): return label
    case .internal(let source): return source.rawValue
    case .cli, .vsCode, .exec, .mcp, .custom, .unknown:
        return nil
    }
}

public func subagentMetadataKind(_ sessionSource: SessionSource) -> String? {
    switch sessionSource {
    case .subAgent(let source):
        return subagentSourceKind(source)
    default:
        return nil
    }
}

func subagentSourceKind(_ source: SubAgentSource) -> String {
    switch source {
    case .review: return "review"
    case .compact: return "compact"
    case .threadSpawn: return "thread_spawn"
    case .memoryConsolidation: return "memory_consolidation"
    case .other(let other): return other
    }
}

func insertHeader(_ headers: inout [String: String], _ name: String, _ value: String) {
    headers[name.lowercased()] = value
}

/// Swift `Result` requires `Failure: Error`; stands in for Rust `Result<(), String>`.
public struct ExtraMetadataError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public func validateExtraMetadata(_ extra: [String: String]) -> Result<Void, ExtraMetadataError> {
    if extra.count > maxExtraMetadataEntries {
        return .failure(ExtraMetadataError("responses_api_metadata may contain at most 16 entries"))
    }
    for (key, value) in extra {
        if key.utf8.count > maxExtraMetadataKeyBytes || !validExtraMetadataKey(key) {
            return .failure(ExtraMetadataError("responses_api_metadata keys must be short ASCII identifiers"))
        }
        if reservedMetadataKeys.contains(key) && !backwardCompatibleReservedMetadataKeys.contains(key) {
            return .failure(ExtraMetadataError("responses_api_metadata contains a reserved key"))
        }
        if value.utf8.count > maxExtraMetadataValueBytes {
            return .failure(ExtraMetadataError("responses_api_metadata values may contain at most 128 bytes"))
        }
    }
    return .success(())
}

public func filterExtraMetadata(_ extra: [String: String]) -> [String: String] {
    extra.filter { !reservedMetadataKeys.contains($0.key) }
}

func validExtraMetadataKey(_ key: String) -> Bool {
    guard let first = key.utf8.first, (65...90).contains(first) || (97...122).contains(first) else {
        return false
    }
    return key.utf8.dropFirst().allSatisfy { byte in
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            || byte == 95 || byte == 46 || byte == 45
    }
}

struct CodexTurnMetadataPayload: Encodable {
    var installationId: String?
    var sessionId: String?
    var threadId: String?
    var agentName: String?
    var turnId: String?
    var windowId: String?
    var windowNumber: UInt64?
    var contextWindowId: UUID?
    var requestKind: String?
    var forkedFromThreadId: ThreadId?
    var forkedFromOrdinalExclusive: UInt64?
    var parentThreadId: ThreadId?
    var parentTurnId: String?
    var rootTurnId: String?
    var subagentKind: String?
    var threadSource: ThreadSource?
    var turnTrigger: String?
    var sandbox: String?
    var sandboxMode: String?
    var autoReviewEnabled: Bool?
    var nodeReplAutoReviewRequired: Bool?
    var nodeReplDisabled: Bool?
    var workspaces: [String: TurnMetadataWorkspace]?
    var toolNamespacesInfo: TurnToolNamespacesInfo?
    var turnStartedAtUnixMs: Int64?
    var historyIngestRequested: Bool?
    var analyticsEnabled: Bool?
    var compaction: CompactionTurnMetadata?
    var extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
        case sessionId = "session_id"
        case threadId = "thread_id"
        case agentName = "agent_name"
        case turnId = "turn_id"
        case windowId = "window_id"
        case windowNumber = "window_number"
        case contextWindowId = "context_window_id"
        case requestKind = "request_kind"
        case forkedFromThreadId = "forked_from_thread_id"
        case forkedFromOrdinalExclusive = "forked_from_ordinal_exclusive"
        case parentThreadId = "parent_thread_id"
        case parentTurnId = "parent_turn_id"
        case rootTurnId = "root_turn_id"
        case subagentKind = "subagent_kind"
        case threadSource = "thread_source"
        case turnTrigger = "turn_trigger"
        case sandbox
        case sandboxMode = "sandbox_mode"
        case autoReviewEnabled = "auto_review_enabled"
        case nodeReplAutoReviewRequired = "node_repl_auto_review_required"
        case nodeReplDisabled = "node_repl_disabled"
        case workspaces
        case toolNamespacesInfo = "tool_namespaces_info"
        case turnStartedAtUnixMs = "turn_started_at_unix_ms"
        case historyIngestRequested = "history_ingest_requested"
        case analyticsEnabled = "analytics_enabled"
        case compaction
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(installationId, forKey: .installationId)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(threadId, forKey: .threadId)
        try container.encodeIfPresent(agentName, forKey: .agentName)
        try container.encodeIfPresent(turnId, forKey: .turnId)
        try container.encodeIfPresent(windowId, forKey: .windowId)
        try container.encodeIfPresent(windowNumber, forKey: .windowNumber)
        try container.encodeIfPresent(contextWindowId?.uuidString.lowercased(), forKey: .contextWindowId)
        try container.encodeIfPresent(requestKind, forKey: .requestKind)
        try container.encodeIfPresent(forkedFromThreadId, forKey: .forkedFromThreadId)
        try container.encodeIfPresent(forkedFromOrdinalExclusive, forKey: .forkedFromOrdinalExclusive)
        try container.encodeIfPresent(parentThreadId, forKey: .parentThreadId)
        try container.encodeIfPresent(parentTurnId, forKey: .parentTurnId)
        try container.encodeIfPresent(rootTurnId, forKey: .rootTurnId)
        try container.encodeIfPresent(subagentKind, forKey: .subagentKind)
        try container.encodeIfPresent(threadSource, forKey: .threadSource)
        try container.encodeIfPresent(turnTrigger, forKey: .turnTrigger)
        try container.encodeIfPresent(sandbox, forKey: .sandbox)
        try container.encodeIfPresent(sandboxMode, forKey: .sandboxMode)
        try container.encodeIfPresent(autoReviewEnabled, forKey: .autoReviewEnabled)
        try container.encodeIfPresent(nodeReplAutoReviewRequired, forKey: .nodeReplAutoReviewRequired)
        try container.encodeIfPresent(nodeReplDisabled, forKey: .nodeReplDisabled)
        try container.encodeIfPresent(workspaces, forKey: .workspaces)
        try container.encodeIfPresent(toolNamespacesInfo, forKey: .toolNamespacesInfo)
        try container.encodeIfPresent(turnStartedAtUnixMs, forKey: .turnStartedAtUnixMs)
        try container.encodeIfPresent(historyIngestRequested, forKey: .historyIngestRequested)
        try container.encodeIfPresent(analyticsEnabled, forKey: .analyticsEnabled)
        try container.encodeIfPresent(compaction, forKey: .compaction)
        var extras = encoder.container(keyedBy: ExtraMetadataKey.self)
        for (key, value) in extra {
            try extras.encode(value, forKey: ExtraMetadataKey(key))
        }
    }
}

private struct ExtraMetadataKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

//
//  approvals.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/approvals.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexUtils
import Foundation

/// Proposed execpolicy change to allow commands starting with this prefix.
/// serde `transparent` — encodes as a JSON array of command tokens.
public struct ExecPolicyAmendment: Codable, Equatable, Sendable {
    public var command: [String]

    public init(_ command: [String]) {
        self.command = command
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        command = try container.decode([String].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(command)
    }
}

public enum NetworkApprovalProtocol: String, Codable, Equatable, Sendable {
    case http
    case https
    case socks5Tcp = "socks5_tcp"
    case socks5Udp = "socks5_udp"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "http": self = .http
        case "https", "https_connect", "http-connect": self = .https
        case "socks5_tcp": self = .socks5Tcp
        case "socks5_udp": self = .socks5Udp
        default:
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown NetworkApprovalProtocol: \(raw)")
        }
    }
}

public struct NetworkApprovalContext: Codable, Equatable, Sendable {
    public var host: String
    public var protocol_: NetworkApprovalProtocol

    enum CodingKeys: String, CodingKey {
        case host
        case protocol_ = "protocol"
    }

    public init(host: String, protocol_: NetworkApprovalProtocol) {
        self.host = host
        self.protocol_ = protocol_
    }
}

public enum NetworkPolicyRuleAction: String, Codable, Equatable, Sendable {
    case allow
    case deny
}

public struct NetworkPolicyAmendment: Codable, Equatable, Sendable {
    public var host: String
    public var action: NetworkPolicyRuleAction

    public init(host: String, action: NetworkPolicyRuleAction) {
        self.host = host
        self.action = action
    }
}

public enum GuardianRiskLevel: String, Codable, Equatable, Sendable {
    case low, medium, high, critical
}

public enum GuardianUserAuthorization: String, Codable, Equatable, Sendable {
    case unknown, low, medium, high
}

public enum GuardianAssessmentOutcome: String, Codable, Equatable, Sendable {
    case allow, deny
}

public enum GuardianAssessmentStatus: String, Codable, Equatable, Sendable {
    case inProgress = "in_progress"
    case approved
    case denied
    case timedOut = "timed_out"
    case aborted
}

public enum GuardianAssessmentDecisionSource: String, Codable, Equatable, Sendable {
    case agent
}

public enum GuardianCommandSource: String, Codable, Equatable, Sendable {
    case shell
    case unifiedExec = "unified_exec"
}

public enum GuardianReviewReason: String, Codable, Equatable, Sendable {
    case policy
    case freshRequired = "fresh_required"
    case missingScore = "missing_score"
    case staleScore = "stale_score"
    case invalidScore = "invalid_score"
    case incompatibleCompaction = "incompatible_compaction"
    case elevatedRisk = "elevated_risk"
    case scoringFailure = "scoring_failure"
    case authorizationChanged = "authorization_changed"
    case unknown

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = GuardianReviewReason(rawValue: raw) ?? .unknown
    }
}

public enum GuardianAssessmentAction: Codable, Equatable, Sendable {
    case command(source: GuardianCommandSource, command: String, cwd: LegacyAppPathString)
    case execve(
        source: GuardianCommandSource, program: String, argv: [String], cwd: AbsolutePathBuf)
    case writeStdin(approvalId: String, processId: String, stdin: String, cwd: PathUri)
    case applyPatch(cwd: LegacyAppPathString, files: [LegacyAppPathString])
    case networkAccess(target: String, host: String, protocol_: NetworkApprovalProtocol, port: UInt16)
    case mcpToolCall(
        server: String, toolName: String, connectorId: String?, connectorName: String?,
        toolTitle: String?)
    case requestPermissions(reason: String?, permissions: RequestPermissionProfile)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case source, command, cwd, program, argv
        case approvalId = "approval_id"
        case processId = "process_id"
        case stdin
        case files, target, host, port, server
        case protocol_ = "protocol"
        case toolName = "tool_name"
        case connectorId = "connector_id"
        case connectorName = "connector_name"
        case toolTitle = "tool_title"
        case reason, permissions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "command":
            self = .command(
                source: try keys.decode(GuardianCommandSource.self, forKey: .source),
                command: try keys.decode(String.self, forKey: .command),
                cwd: try keys.decode(LegacyAppPathString.self, forKey: .cwd))
        case "execve":
            self = .execve(
                source: try keys.decode(GuardianCommandSource.self, forKey: .source),
                program: try keys.decode(String.self, forKey: .program),
                argv: try keys.decode([String].self, forKey: .argv),
                cwd: try keys.decode(AbsolutePathBuf.self, forKey: .cwd))
        case "write_stdin":
            self = .writeStdin(
                approvalId: try keys.decode(String.self, forKey: .approvalId),
                processId: try keys.decode(String.self, forKey: .processId),
                stdin: try keys.decode(String.self, forKey: .stdin),
                cwd: try keys.decode(PathUri.self, forKey: .cwd))
        case "apply_patch":
            self = .applyPatch(
                cwd: try keys.decode(LegacyAppPathString.self, forKey: .cwd),
                files: try keys.decode([LegacyAppPathString].self, forKey: .files))
        case "network_access":
            self = .networkAccess(
                target: try keys.decode(String.self, forKey: .target),
                host: try keys.decode(String.self, forKey: .host),
                protocol_: try keys.decode(NetworkApprovalProtocol.self, forKey: .protocol_),
                port: try keys.decode(UInt16.self, forKey: .port))
        case "mcp_tool_call":
            self = .mcpToolCall(
                server: try keys.decode(String.self, forKey: .server),
                toolName: try keys.decode(String.self, forKey: .toolName),
                connectorId: try keys.decodeIfPresent(String.self, forKey: .connectorId),
                connectorName: try keys.decodeIfPresent(String.self, forKey: .connectorName),
                toolTitle: try keys.decodeIfPresent(String.self, forKey: .toolTitle))
        case "request_permissions":
            self = .requestPermissions(
                reason: try keys.decodeIfPresent(String.self, forKey: .reason),
                permissions: try keys.decode(RequestPermissionProfile.self, forKey: .permissions))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown GuardianAssessmentAction: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .command(let source, let command, let cwd):
            try container.encode("command", forKey: .type_)
            try keys.encode(source, forKey: .source)
            try keys.encode(command, forKey: .command)
            try keys.encode(cwd, forKey: .cwd)
        case .execve(let source, let program, let argv, let cwd):
            try container.encode("execve", forKey: .type_)
            try keys.encode(source, forKey: .source)
            try keys.encode(program, forKey: .program)
            try keys.encode(argv, forKey: .argv)
            try keys.encode(cwd, forKey: .cwd)
        case .writeStdin(let approvalId, let processId, let stdin, let cwd):
            try container.encode("write_stdin", forKey: .type_)
            try keys.encode(approvalId, forKey: .approvalId)
            try keys.encode(processId, forKey: .processId)
            try keys.encode(stdin, forKey: .stdin)
            try keys.encode(cwd, forKey: .cwd)
        case .applyPatch(let cwd, let files):
            try container.encode("apply_patch", forKey: .type_)
            try keys.encode(cwd, forKey: .cwd)
            try keys.encode(files, forKey: .files)
        case .networkAccess(let target, let host, let protocol_, let port):
            try container.encode("network_access", forKey: .type_)
            try keys.encode(target, forKey: .target)
            try keys.encode(host, forKey: .host)
            try keys.encode(protocol_, forKey: .protocol_)
            try keys.encode(port, forKey: .port)
        case .mcpToolCall(let server, let toolName, let connectorId, let connectorName, let toolTitle):
            try container.encode("mcp_tool_call", forKey: .type_)
            try keys.encode(server, forKey: .server)
            try keys.encode(toolName, forKey: .toolName)
            try keys.encodeIfPresent(connectorId, forKey: .connectorId)
            try keys.encodeIfPresent(connectorName, forKey: .connectorName)
            try keys.encodeIfPresent(toolTitle, forKey: .toolTitle)
        case .requestPermissions(let reason, let permissions):
            try container.encode("request_permissions", forKey: .type_)
            try keys.encodeIfPresent(reason, forKey: .reason)
            try keys.encode(permissions, forKey: .permissions)
        }
    }
}

/// Fully resolved permissions for rerunning an intercepted child process.
public struct ResolvedPermissionProfile: Equatable, Sendable {
    public var permissionProfile: PermissionProfile

    public init(permissionProfile: PermissionProfile) {
        self.permissionProfile = permissionProfile
    }
}

public enum EscalationPermissions: Equatable, Sendable {
    case additionalPermissionProfile(AdditionalPermissionProfile)
    case resolvedPermissionProfile(ResolvedPermissionProfile)
}

public enum ExecApprovalKind: String, Codable, Equatable, Sendable {
    case command
    case writeStdin = "write_stdin"

    public static let `default`: ExecApprovalKind = .command
}

public struct GuardianAssessmentEvent: Codable, Equatable, Sendable {
    public var reviewReason: GuardianReviewReason?
    public var modelContext: ModelInvocationContext?
    public var id: String
    public var targetItemId: String?
    public var pluginId: String?
    public var scriptPath: String?
    public var turnId: String
    public var startedAtMs: Int64
    public var completedAtMs: Int64?
    public var status: GuardianAssessmentStatus
    public var riskLevel: GuardianRiskLevel?
    public var userAuthorization: GuardianUserAuthorization?
    public var rationale: String?
    public var decisionSource: GuardianAssessmentDecisionSource?
    public var action: GuardianAssessmentAction

    enum CodingKeys: String, CodingKey {
        case id, status, action, rationale
        case reviewReason = "review_reason"
        case targetItemId = "target_item_id"
        case pluginId = "plugin_id"
        case scriptPath = "script_path"
        case turnId = "turn_id"
        case startedAtMs = "started_at_ms"
        case completedAtMs = "completed_at_ms"
        case riskLevel = "risk_level"
        case userAuthorization = "user_authorization"
        case decisionSource = "decision_source"
    }

    public init(
        reviewReason: GuardianReviewReason? = nil,
        modelContext: ModelInvocationContext? = nil,
        id: String,
        targetItemId: String? = nil,
        pluginId: String? = nil,
        scriptPath: String? = nil,
        turnId: String = "",
        startedAtMs: Int64 = 0,
        completedAtMs: Int64? = nil,
        status: GuardianAssessmentStatus,
        riskLevel: GuardianRiskLevel? = nil,
        userAuthorization: GuardianUserAuthorization? = nil,
        rationale: String? = nil,
        decisionSource: GuardianAssessmentDecisionSource? = nil,
        action: GuardianAssessmentAction
    ) {
        self.reviewReason = reviewReason
        self.modelContext = modelContext
        self.id = id
        self.targetItemId = targetItemId
        self.pluginId = pluginId
        self.scriptPath = scriptPath
        self.turnId = turnId
        self.startedAtMs = startedAtMs
        self.completedAtMs = completedAtMs
        self.status = status
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
        self.rationale = rationale
        self.decisionSource = decisionSource
        self.action = action
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reviewReason = try container.decodeIfPresent(GuardianReviewReason.self, forKey: .reviewReason)
        modelContext = nil
        id = try container.decode(String.self, forKey: .id)
        targetItemId = try container.decodeIfPresent(String.self, forKey: .targetItemId)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        scriptPath = try container.decodeIfPresent(String.self, forKey: .scriptPath)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        startedAtMs = try container.decodeIfPresent(Int64.self, forKey: .startedAtMs) ?? 0
        completedAtMs = try container.decodeIfPresent(Int64.self, forKey: .completedAtMs)
        status = try container.decode(GuardianAssessmentStatus.self, forKey: .status)
        riskLevel = try container.decodeIfPresent(GuardianRiskLevel.self, forKey: .riskLevel)
        userAuthorization = try container.decodeIfPresent(
            GuardianUserAuthorization.self, forKey: .userAuthorization)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        decisionSource = try container.decodeIfPresent(
            GuardianAssessmentDecisionSource.self, forKey: .decisionSource)
        action = try container.decode(GuardianAssessmentAction.self, forKey: .action)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(reviewReason, forKey: .reviewReason)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(targetItemId, forKey: .targetItemId)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(scriptPath, forKey: .scriptPath)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encodeIfPresent(completedAtMs, forKey: .completedAtMs)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(riskLevel, forKey: .riskLevel)
        try container.encodeIfPresent(userAuthorization, forKey: .userAuthorization)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encodeIfPresent(decisionSource, forKey: .decisionSource)
        try container.encode(action, forKey: .action)
    }
}

public struct ExecApprovalRequestEvent: Codable, Equatable, Sendable {
    public var modelContext: ModelInvocationContext?
    public var kind: ExecApprovalKind
    public var callId: String
    public var pluginId: String?
    public var scriptPath: String?
    public var approvalId: String?
    public var turnId: String
    public var environmentId: String?
    public var startedAtMs: Int64
    public var command: [String]
    public var cwd: LegacyAppPathString
    public var reason: String?
    public var networkApprovalContext: NetworkApprovalContext?
    public var proposedExecpolicyAmendment: ExecPolicyAmendment?
    public var proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]?
    public var additionalPermissions: AdditionalPermissionProfile?
    public var availableDecisions: [ReviewDecision]?
    public var parsedCmd: [ParsedCommand]

    enum CodingKeys: String, CodingKey {
        case kind, command, cwd, reason
        case callId = "call_id"
        case pluginId = "plugin_id"
        case scriptPath = "script_path"
        case approvalId = "approval_id"
        case turnId = "turn_id"
        case environmentId
        case environmentIdSnake = "environment_id"
        case startedAtMs = "started_at_ms"
        case networkApprovalContext = "network_approval_context"
        case proposedExecpolicyAmendment = "proposed_execpolicy_amendment"
        case proposedNetworkPolicyAmendments = "proposed_network_policy_amendments"
        case additionalPermissions = "additional_permissions"
        case availableDecisions = "available_decisions"
        case parsedCmd = "parsed_cmd"
    }

    public init(
        modelContext: ModelInvocationContext? = nil,
        kind: ExecApprovalKind = .command,
        callId: String,
        pluginId: String? = nil,
        scriptPath: String? = nil,
        approvalId: String? = nil,
        turnId: String = "",
        environmentId: String? = nil,
        startedAtMs: Int64,
        command: [String],
        cwd: LegacyAppPathString,
        reason: String? = nil,
        networkApprovalContext: NetworkApprovalContext? = nil,
        proposedExecpolicyAmendment: ExecPolicyAmendment? = nil,
        proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]? = nil,
        additionalPermissions: AdditionalPermissionProfile? = nil,
        availableDecisions: [ReviewDecision]? = nil,
        parsedCmd: [ParsedCommand]
    ) {
        self.modelContext = modelContext
        self.kind = kind
        self.callId = callId
        self.pluginId = pluginId
        self.scriptPath = scriptPath
        self.approvalId = approvalId
        self.turnId = turnId
        self.environmentId = environmentId
        self.startedAtMs = startedAtMs
        self.command = command
        self.cwd = cwd
        self.reason = reason
        self.networkApprovalContext = networkApprovalContext
        self.proposedExecpolicyAmendment = proposedExecpolicyAmendment
        self.proposedNetworkPolicyAmendments = proposedNetworkPolicyAmendments
        self.additionalPermissions = additionalPermissions
        self.availableDecisions = availableDecisions
        self.parsedCmd = parsedCmd
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelContext = nil
        kind = try container.decodeIfPresent(ExecApprovalKind.self, forKey: .kind) ?? .command
        callId = try container.decode(String.self, forKey: .callId)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        scriptPath = try container.decodeIfPresent(String.self, forKey: .scriptPath)
        approvalId = try container.decodeIfPresent(String.self, forKey: .approvalId)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        environmentId = try container.decodeIfPresent(String.self, forKey: .environmentId)
            ?? container.decodeIfPresent(String.self, forKey: .environmentIdSnake)
        startedAtMs = try container.decode(Int64.self, forKey: .startedAtMs)
        command = try container.decode([String].self, forKey: .command)
        cwd = try container.decode(LegacyAppPathString.self, forKey: .cwd)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        networkApprovalContext = try container.decodeIfPresent(
            NetworkApprovalContext.self, forKey: .networkApprovalContext)
        proposedExecpolicyAmendment = try container.decodeIfPresent(
            ExecPolicyAmendment.self, forKey: .proposedExecpolicyAmendment)
        proposedNetworkPolicyAmendments = try container.decodeIfPresent(
            [NetworkPolicyAmendment].self, forKey: .proposedNetworkPolicyAmendments)
        additionalPermissions = try container.decodeIfPresent(
            AdditionalPermissionProfile.self, forKey: .additionalPermissions)
        availableDecisions = try container.decodeIfPresent(
            [ReviewDecision].self, forKey: .availableDecisions)
        parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(callId, forKey: .callId)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(scriptPath, forKey: .scriptPath)
        try container.encodeIfPresent(approvalId, forKey: .approvalId)
        try container.encode(turnId, forKey: .turnId)
        try container.encodeIfPresent(environmentId, forKey: .environmentId)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(networkApprovalContext, forKey: .networkApprovalContext)
        try container.encodeIfPresent(proposedExecpolicyAmendment, forKey: .proposedExecpolicyAmendment)
        try container.encodeIfPresent(
            proposedNetworkPolicyAmendments, forKey: .proposedNetworkPolicyAmendments)
        try container.encodeIfPresent(additionalPermissions, forKey: .additionalPermissions)
        try container.encodeIfPresent(availableDecisions, forKey: .availableDecisions)
        try container.encode(parsedCmd, forKey: .parsedCmd)
    }

    public func effectiveApprovalId() -> String {
        approvalId ?? callId
    }

    public func effectiveAvailableDecisions() -> [ReviewDecision] {
        if let availableDecisions { return availableDecisions }
        return Self.defaultAvailableDecisions(
            networkApprovalContext: networkApprovalContext,
            proposedExecpolicyAmendment: proposedExecpolicyAmendment,
            proposedNetworkPolicyAmendments: proposedNetworkPolicyAmendments,
            additionalPermissions: additionalPermissions)
    }

    public static func defaultAvailableDecisions(
        networkApprovalContext: NetworkApprovalContext?,
        proposedExecpolicyAmendment: ExecPolicyAmendment?,
        proposedNetworkPolicyAmendments: [NetworkPolicyAmendment]?,
        additionalPermissions: AdditionalPermissionProfile?
    ) -> [ReviewDecision] {
        if networkApprovalContext != nil {
            var decisions: [ReviewDecision] = [.approved, .approvedForSession]
            if let amendment = proposedNetworkPolicyAmendments?.first(where: { $0.action == .allow })
            {
                decisions.append(.networkPolicyAmendment(networkPolicyAmendment: amendment))
            }
            decisions.append(.abort)
            return decisions
        }
        if additionalPermissions != nil {
            return [.approved, .abort]
        }
        var decisions: [ReviewDecision] = [.approved]
        if let prefix = proposedExecpolicyAmendment {
            decisions.append(
                .approvedExecpolicyAmendment(proposedExecpolicyAmendment: prefix))
        }
        decisions.append(.abort)
        return decisions
    }
}

public enum ElicitationRequest: Codable, Equatable, Sendable {
    case userVerification(meta: JSONValue?, title: String, description: String, challenge: String)
    case form(meta: JSONValue?, message: String, requestedSchema: JSONValue)
    case openAiForm(meta: JSONValue?, message: String, requestedSchema: JSONValue)
    case openAiElicitationForm(meta: JSONValue?, message: String, requestedSchema: JSONValue)
    case url(meta: JSONValue?, message: String, url: String, elicitationId: String)

    private enum TypeKey: String, CodingKey { case mode }
    private enum Keys: String, CodingKey {
        case meta = "_meta"
        case title, description, challenge, message, url
        case requestedSchema = "requested_schema"
        case elicitationId = "elicitation_id"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let mode = try container.decode(String.self, forKey: .mode)
        let keys = try decoder.container(keyedBy: Keys.self)
        let meta = try keys.decodeIfPresent(JSONValue.self, forKey: .meta)
        switch mode {
        case "openai/userVerification":
            self = .userVerification(
                meta: meta,
                title: try keys.decode(String.self, forKey: .title),
                description: try keys.decode(String.self, forKey: .description),
                challenge: try keys.decode(String.self, forKey: .challenge))
        case "form":
            self = .form(
                meta: meta,
                message: try keys.decode(String.self, forKey: .message),
                requestedSchema: try keys.decode(JSONValue.self, forKey: .requestedSchema))
        case "openai/form":
            self = .openAiForm(
                meta: meta,
                message: try keys.decode(String.self, forKey: .message),
                requestedSchema: try keys.decode(JSONValue.self, forKey: .requestedSchema))
        case "openaiForm":
            self = .openAiElicitationForm(
                meta: meta,
                message: try keys.decode(String.self, forKey: .message),
                requestedSchema: try keys.decode(JSONValue.self, forKey: .requestedSchema))
        case "url":
            self = .url(
                meta: meta,
                message: try keys.decode(String.self, forKey: .message),
                url: try keys.decode(String.self, forKey: .url),
                elicitationId: try keys.decode(String.self, forKey: .elicitationId))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .mode, in: container,
                debugDescription: "Unknown ElicitationRequest: \(mode)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .userVerification(let meta, let title, let description, let challenge):
            try container.encode("openai/userVerification", forKey: .mode)
            try keys.encodeIfPresent(meta, forKey: .meta)
            try keys.encode(title, forKey: .title)
            try keys.encode(description, forKey: .description)
            try keys.encode(challenge, forKey: .challenge)
        case .form(let meta, let message, let schema):
            try container.encode("form", forKey: .mode)
            try keys.encodeIfPresent(meta, forKey: .meta)
            try keys.encode(message, forKey: .message)
            try keys.encode(schema, forKey: .requestedSchema)
        case .openAiForm(let meta, let message, let schema):
            try container.encode("openai/form", forKey: .mode)
            try keys.encodeIfPresent(meta, forKey: .meta)
            try keys.encode(message, forKey: .message)
            try keys.encode(schema, forKey: .requestedSchema)
        case .openAiElicitationForm(let meta, let message, let schema):
            try container.encode("openaiForm", forKey: .mode)
            try keys.encodeIfPresent(meta, forKey: .meta)
            try keys.encode(message, forKey: .message)
            try keys.encode(schema, forKey: .requestedSchema)
        case .url(let meta, let message, let url, let elicitationId):
            try container.encode("url", forKey: .mode)
            try keys.encodeIfPresent(meta, forKey: .meta)
            try keys.encode(message, forKey: .message)
            try keys.encode(url, forKey: .url)
            try keys.encode(elicitationId, forKey: .elicitationId)
        }
    }
}

public struct ElicitationRequestEvent: Codable, Equatable, Sendable {
    public var turnId: String?
    public var serverName: String
    public var id: RequestId
    public var request: ElicitationRequest

    enum CodingKeys: String, CodingKey {
        case request
        case turnId = "turn_id"
        case serverName = "server_name"
        case id
    }

    public init(turnId: String? = nil, serverName: String, id: RequestId, request: ElicitationRequest) {
        self.turnId = turnId; self.serverName = serverName; self.id = id; self.request = request
    }
}

public enum ElicitationAction: String, Codable, Equatable, Sendable {
    case accept
    case decline
    case cancel
}

public struct ApplyPatchApprovalRequestEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var startedAtMs: Int64
    public var changes: [String: FileChange]
    public var reason: String?
    public var grantRoot: String?

    enum CodingKeys: String, CodingKey {
        case changes, reason
        case callId = "call_id"
        case turnId = "turn_id"
        case startedAtMs = "started_at_ms"
        case grantRoot = "grant_root"
    }

    public init(
        callId: String, turnId: String = "", startedAtMs: Int64, changes: [String: FileChange],
        reason: String? = nil, grantRoot: String? = nil
    ) {
        self.callId = callId
        self.turnId = turnId
        self.startedAtMs = startedAtMs
        self.changes = changes
        self.reason = reason
        self.grantRoot = grantRoot
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        startedAtMs = try container.decode(Int64.self, forKey: .startedAtMs)
        changes = try container.decode([String: FileChange].self, forKey: .changes)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        grantRoot = try container.decodeIfPresent(String.self, forKey: .grantRoot)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encode(changes, forKey: .changes)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(grantRoot, forKey: .grantRoot)
    }
}

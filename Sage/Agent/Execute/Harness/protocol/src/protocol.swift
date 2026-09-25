//
//  protocol.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/protocol.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Core protocol types. This is a partial port covering the most commonly
//  referenced types needed by other protocol files. The full `protocol.rs`
//  is ~6,444 lines; remaining types will be ported incrementally.
//

import CodexUtils
import Foundation

// MARK: - AskForApproval

public enum AskForApproval: Equatable, Sendable {
    case unlessTrusted
    case onRequest
    case granular(GranularApprovalConfig)
    case never
}

extension AskForApproval: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self) {
            switch raw {
            case "untrusted": self = .unlessTrusted
            case "on_request", "on-failure": self = .onRequest
            case "never": self = .never
            default:
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown AskForApproval: \(raw)")
            }
            return
        }
        let obj = try decoder.container(keyedBy: TagKey.self)
        let tag = try obj.decode(String.self, forKey: .type_)
        if tag == "granular" {
            self = .granular(try GranularApprovalConfig(from: decoder))
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: obj, debugDescription: "Unknown AskForApproval tag: \(tag)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .unlessTrusted:
            var container = encoder.singleValueContainer()
            try container.encode("untrusted")
        case .onRequest:
            var container = encoder.singleValueContainer()
            try container.encode("on_request")
        case .never:
            var container = encoder.singleValueContainer()
            try container.encode("never")
        case .granular(let config):
            try config.encode(to: encoder)
        }
    }

    private enum TagKey: String, CodingKey { case type_ = "type" }
}

// MARK: - GranularApprovalConfig

public struct GranularApprovalConfig: Codable, Equatable, Hashable, Sendable {
    public var sandboxApproval: Bool
    public var rules: Bool
    public var skillApproval: Bool
    public var requestPermissions: Bool
    public var mcpElicitations: Bool

    enum CodingKeys: String, CodingKey {
        case sandboxApproval = "sandbox_approval"
        case rules
        case skillApproval = "skill_approval"
        case requestPermissions = "request_permissions"
        case mcpElicitations = "mcp_elicitations"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sandboxApproval = try container.decode(Bool.self, forKey: .sandboxApproval)
        rules = try container.decode(Bool.self, forKey: .rules)
        skillApproval = try container.decodeIfPresent(Bool.self, forKey: .skillApproval) ?? false
        requestPermissions = try container.decodeIfPresent(Bool.self, forKey: .requestPermissions) ?? false
        mcpElicitations = try container.decode(Bool.self, forKey: .mcpElicitations)
    }

    public init(
        sandboxApproval: Bool, rules: Bool, skillApproval: Bool = false,
        requestPermissions: Bool = false, mcpElicitations: Bool
    ) {
        self.sandboxApproval = sandboxApproval; self.rules = rules
        self.skillApproval = skillApproval; self.requestPermissions = requestPermissions
        self.mcpElicitations = mcpElicitations
    }
}

// MARK: - NetworkAccess

public enum NetworkAccess: String, Codable, Equatable, Sendable {
    case restricted = "restricted"
    case enabled = "enabled"

    public var isEnabled: Bool { self == .enabled }
}

// MARK: - SandboxPolicy

public enum SandboxPolicy: Codable, Equatable, Sendable {
    case dangerFullAccess
    case readOnly(networkAccess: Bool)
    case externalSandbox(networkAccess: NetworkAccess)
    case workspaceWrite(
        writableRoots: [AbsolutePathBuf],
        networkAccess: Bool,
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool
    )

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case networkAccess = "network_access"
        case writableRoots = "writable_roots"
        case excludeTmpdirEnvVar = "exclude_tmpdir_env_var"
        case excludeSlashTmp = "exclude_slash_tmp"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "danger-full-access":
            self = .dangerFullAccess
        case "read-only":
            self = .readOnly(
                networkAccess: try keys.decodeIfPresent(Bool.self, forKey: .networkAccess) ?? false)
        case "external-sandbox":
            self = .externalSandbox(
                networkAccess: try keys.decodeIfPresent(NetworkAccess.self, forKey: .networkAccess) ?? .restricted)
        case "workspace-write":
            self = .workspaceWrite(
                writableRoots: try keys.decodeIfPresent([AbsolutePathBuf].self, forKey: .writableRoots) ?? [],
                networkAccess: try keys.decodeIfPresent(Bool.self, forKey: .networkAccess) ?? false,
                excludeTmpdirEnvVar: try keys.decodeIfPresent(Bool.self, forKey: .excludeTmpdirEnvVar) ?? false,
                excludeSlashTmp: try keys.decodeIfPresent(Bool.self, forKey: .excludeSlashTmp) ?? false)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown SandboxPolicy: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .dangerFullAccess:
            try container.encode("danger-full-access", forKey: .type_)
        case .readOnly(let net):
            try container.encode("read-only", forKey: .type_)
            if net { try keys.encode(net, forKey: .networkAccess) }
        case .externalSandbox(let net):
            try container.encode("external-sandbox", forKey: .type_)
            try keys.encode(net, forKey: .networkAccess)
        case .workspaceWrite(let roots, let net, let excludeTmpdir, let excludeSlashTmp):
            try container.encode("workspace-write", forKey: .type_)
            if !roots.isEmpty { try keys.encode(roots, forKey: .writableRoots) }
            if net { try keys.encode(net, forKey: .networkAccess) }
            if excludeTmpdir { try keys.encode(excludeTmpdir, forKey: .excludeTmpdirEnvVar) }
            if excludeSlashTmp { try keys.encode(excludeSlashTmp, forKey: .excludeSlashTmp) }
        }
    }

    public static func newReadOnlyPolicy() -> SandboxPolicy {
        .readOnly(networkAccess: false)
    }

    public static func newWorkspaceWritePolicy() -> SandboxPolicy {
        .workspaceWrite(
            writableRoots: [], networkAccess: false,
            excludeTmpdirEnvVar: false, excludeSlashTmp: false)
    }

    public var hasFullDiskReadAccess: Bool { true }

    public var hasFullDiskWriteAccess: Bool {
        switch self {
        case .dangerFullAccess, .externalSandbox: return true
        case .readOnly, .workspaceWrite: return false
        }
    }

    public var hasFullNetworkAccess: Bool {
        switch self {
        case .dangerFullAccess: return true
        case .externalSandbox(let networkAccess): return networkAccess.isEnabled
        case .readOnly(let networkAccess): return networkAccess
        case .workspaceWrite(_, let networkAccess, _, _): return networkAccess
        }
    }
}

// MARK: - WritableRoot

/// A writable root plus subpaths that stay read-only (e.g. `.git` / `.codex`).
public struct WritableRoot: Equatable, Sendable {
    public var root: AbsolutePathBuf
    public var readOnlySubpaths: [AbsolutePathBuf]
    public var protectedMetadataNames: [String]

    public init(
        root: AbsolutePathBuf,
        readOnlySubpaths: [AbsolutePathBuf] = [],
        protectedMetadataNames: [String] = []
    ) {
        self.root = root
        self.readOnlySubpaths = readOnlySubpaths
        self.protectedMetadataNames = protectedMetadataNames
    }

    public func isPathWritable(_ path: String) -> Bool {
        let rootPath = root.asPath
        guard path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        else {
            return false
        }
        for subpath in readOnlySubpaths {
            let prefix = subpath.asPath
            if path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/") {
                return false
            }
        }
        return true
    }
}

// MARK: - NonSteerableTurnKind

public enum NonSteerableTurnKind: String, Codable, Equatable, Sendable {
    case review
    case compact
}

// MARK: - CodexErrorInfo

/// Codex errors that we expose to clients. The `Codable` conformance lives in
/// `codex_error_info.swift`, mirroring upstream where the serde impls live in
/// `codex_error_info.rs` (external tagging, unknown classifications decode as
/// `other`).
public enum CodexErrorInfo: Equatable, Sendable {
    case contextWindowExceeded
    case sessionBudgetExceeded
    case usageLimitExceeded
    case rateLimitExceeded
    case flexUnavailable
    case serverOverloaded
    case cyberPolicy
    case bioPolicy
    case misalignmentPolicyViolation
    case httpConnectionFailed(httpStatusCode: UInt16?)
    case responseStreamConnectionFailed(httpStatusCode: UInt16?)
    case internalServerError
    case unauthorized
    case badRequest
    case invalidPrompt
    case sandboxError
    case responseStreamDisconnected(httpStatusCode: UInt16?)
    case responseTooManyFailedAttempts(httpStatusCode: UInt16?)
    case activeTurnNotSteerable(turnKind: NonSteerableTurnKind)
    case threadRollbackFailed
    case other

    public var affectsTurnStatus: Bool {
        switch self {
        case .threadRollbackFailed, .activeTurnNotSteerable: return false
        default: return true
        }
    }
}

// MARK: - AgentStatus

public enum AgentStatus: Codable, Equatable, Sendable {
    case pendingInit
    case running
    case interrupted
    case completed(String?)
    case errored(String)
    case shutdown
    case notFound

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey { case message }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "pending_init": self = .pendingInit
        case "running": self = .running
        case "interrupted": self = .interrupted
        case "completed":
            let keys = try decoder.container(keyedBy: Keys.self)
            self = .completed(try keys.decodeIfPresent(String.self, forKey: .message))
        case "errored":
            let keys = try decoder.container(keyedBy: Keys.self)
            self = .errored(try keys.decode(String.self, forKey: .message))
        case "shutdown": self = .shutdown
        case "not_found": self = .notFound
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown AgentStatus: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .pendingInit: try container.encode("pending_init", forKey: .type_)
        case .running: try container.encode("running", forKey: .type_)
        case .interrupted: try container.encode("interrupted", forKey: .type_)
        case .completed(let msg):
            try container.encode("completed", forKey: .type_)
            if let msg {
                var keys = encoder.container(keyedBy: Keys.self)
                try keys.encode(msg, forKey: .message)
            }
        case .errored(let msg):
            try container.encode("errored", forKey: .type_)
            var keys = encoder.container(keyedBy: Keys.self)
            try keys.encode(msg, forKey: .message)
        case .shutdown: try container.encode("shutdown", forKey: .type_)
        case .notFound: try container.encode("not_found", forKey: .type_)
        }
    }
}

// MARK: - W3cTraceContext

public struct W3cTraceContext: Codable, Equatable, Sendable {
    public var traceparent: String
    public var tracestate: String?

    public init(traceparent: String, tracestate: String? = nil) {
        self.traceparent = traceparent; self.tracestate = tracestate
    }
}

// MARK: - ThreadSettingsOverrides (simplified)

public struct ThreadSettingsOverrides: Equatable, Sendable {
    public var model: String?
    public var reasoningEffort: ReasoningEffort?
    public var reasoningSummary: ReasoningSummary?
    public var mode: ModeKind?

    public init(
        model: String? = nil, reasoningEffort: ReasoningEffort? = nil,
        reasoningSummary: ReasoningSummary? = nil, mode: ModeKind? = nil
    ) {
        self.model = model; self.reasoningEffort = reasoningEffort
        self.reasoningSummary = reasoningSummary; self.mode = mode
    }

    public var isEmpty: Bool {
        model == nil && reasoningEffort == nil && reasoningSummary == nil && mode == nil
    }
}

// MARK: - AdditionalContextKind

public enum AdditionalContextKind: String, Codable, Equatable, Sendable {
    case developerInstructions = "developer_instructions"
    case previousResponseId = "previous_response_id"
}

// MARK: - AdditionalContextEntry

public struct AdditionalContextEntry: Codable, Equatable, Sendable {
    public var kind: AdditionalContextKind
    public var value: JSONValue

    public init(kind: AdditionalContextKind, value: JSONValue) {
        self.kind = kind; self.value = value
    }
}

// MARK: - GitSha

/// `#[serde(transparent)]` newtype around a commit SHA string.
public struct GitSha: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var value: String
    public var description: String { value }

    public init(_ sha: String) {
        self.value = sha
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - GitInfo

public struct GitInfo: Codable, Equatable, Sendable {
    /// Current commit hash (SHA)
    public var commitHash: GitSha?
    /// Current branch name
    public var branch: String?
    /// Repository URL (if available from remote). Malformed legacy values
    /// decode as nil rather than failing the enclosing record.
    public var repositoryUrl: SanitizedGitUrl?

    private enum CodingKeys: String, CodingKey {
        case commitHash = "commit_hash"
        case branch
        case repositoryUrl = "repository_url"
    }

    public init(
        commitHash: GitSha? = nil, branch: String? = nil,
        repositoryUrl: SanitizedGitUrl? = nil
    ) {
        self.commitHash = commitHash; self.branch = branch; self.repositoryUrl = repositoryUrl
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commitHash = try container.decodeIfPresent(GitSha.self, forKey: .commitHash)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        repositoryUrl = try decodeOptionalSanitizedGitURL(from: container, forKey: .repositoryUrl)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(commitHash, forKey: .commitHash)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encodeIfPresent(repositoryUrl, forKey: .repositoryUrl)
    }
}

// MARK: - ReviewOutputEvent

/// Structured review result produced by a child review session.
public struct ReviewOutputEvent: Codable, Equatable, Sendable {
    public var findings: [ReviewFinding]
    public var overallCorrectness: String
    public var overallExplanation: String
    public var overallConfidenceScore: Float

    private enum CodingKeys: String, CodingKey {
        case findings
        case overallCorrectness = "overall_correctness"
        case overallExplanation = "overall_explanation"
        case overallConfidenceScore = "overall_confidence_score"
    }

    public init(
        findings: [ReviewFinding] = [],
        overallCorrectness: String = "",
        overallExplanation: String = "",
        overallConfidenceScore: Float = 0.0
    ) {
        self.findings = findings
        self.overallCorrectness = overallCorrectness
        self.overallExplanation = overallExplanation
        self.overallConfidenceScore = overallConfidenceScore
    }
}

/// A single review finding describing an observed issue or recommendation.
public struct ReviewFinding: Codable, Equatable, Sendable {
    public var title: String
    public var body: String
    public var confidenceScore: Float
    public var priority: Int32
    public var codeLocation: ReviewCodeLocation

    private enum CodingKeys: String, CodingKey {
        case title, body, priority
        case confidenceScore = "confidence_score"
        case codeLocation = "code_location"
    }

    public init(
        title: String, body: String, confidenceScore: Float, priority: Int32,
        codeLocation: ReviewCodeLocation
    ) {
        self.title = title; self.body = body
        self.confidenceScore = confidenceScore; self.priority = priority
        self.codeLocation = codeLocation
    }
}

/// Location of the code related to a review finding.
///
/// `absolute_file_path` is a `PathBuf` upstream; ported as a String path
/// (CodexProtocol path-type adaptation).
public struct ReviewCodeLocation: Codable, Equatable, Sendable {
    public var absoluteFilePath: String
    public var lineRange: ReviewLineRange

    private enum CodingKeys: String, CodingKey {
        case absoluteFilePath = "absolute_file_path"
        case lineRange = "line_range"
    }

    public init(absoluteFilePath: String, lineRange: ReviewLineRange) {
        self.absoluteFilePath = absoluteFilePath; self.lineRange = lineRange
    }
}

/// Inclusive line range in a file associated with the finding.
public struct ReviewLineRange: Codable, Equatable, Sendable {
    public var start: UInt32
    public var end: UInt32

    public init(start: UInt32, end: UInt32) {
        self.start = start; self.end = end
    }
}

// MARK: - TokenUsage

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int64
    public var outputTokens: Int64
    public var totalTokens: Int64?
    public var inputTokenDetails: JSONValue?
    public var outputTokenDetails: JSONValue?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokenDetails = "input_token_details"
        case outputTokenDetails = "output_token_details"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(Int64.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int64.self, forKey: .outputTokens)
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens)
        inputTokenDetails = try container.decodeIfPresent(JSONValue.self, forKey: .inputTokenDetails)
        outputTokenDetails = try container.decodeIfPresent(JSONValue.self, forKey: .outputTokenDetails)
    }
}

// MARK: - ErrorEvent

public struct ErrorEvent: Codable, Equatable, Sendable {
    public var message: String
    public var errorInfo: CodexErrorInfo?
    /// Live-only; never enters rollout storage (`#[serde(skip)]`).
    public var misalignment: MisalignmentErrorDetails?

    enum CodingKeys: String, CodingKey {
        case message
        case errorInfo = "codex_error_info"
        case errorInfoLegacy = "error_info"
    }

    public init(
        message: String,
        errorInfo: CodexErrorInfo? = nil,
        misalignment: MisalignmentErrorDetails? = nil
    ) {
        self.message = message
        self.errorInfo = errorInfo
        self.misalignment = misalignment
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        errorInfo = try container.decodeIfPresent(CodexErrorInfo.self, forKey: .errorInfo)
            ?? container.decodeIfPresent(CodexErrorInfo.self, forKey: .errorInfoLegacy)
        misalignment = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(errorInfo, forKey: .errorInfo)
    }

    public var affectsTurnStatus: Bool {
        errorInfo.map(\.affectsTurnStatus) ?? true
    }
}

// MARK: - TurnCompleteEvent

public struct TurnCompleteEvent: Codable, Equatable, Sendable {
    public var turnId: String
    public var usage: TokenUsage?
    public var stopped: Bool
    public var interrupted: Bool

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case usage
        case stopped
        case interrupted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnId = try container.decode(String.self, forKey: .turnId)
        usage = try container.decodeIfPresent(TokenUsage.self, forKey: .usage)
        stopped = try container.decodeIfPresent(Bool.self, forKey: .stopped) ?? false
        interrupted = try container.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
    }
}

// MARK: - TurnStartedEvent

public struct TurnStartedEvent: Codable, Equatable, Sendable {
    public var turnId: String
    public var model: String?

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case model
    }
}

// MARK: - HookEventName

public enum HookEventName: String, Codable, Equatable, Sendable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case turnStart = "turn_start"
    case turnEnd = "turn_end"
    case userPrompt = "user_prompt"
    case execApproval = "exec_approval"
    case applyPatchApproval = "apply_patch_approval"
}

// MARK: - HookHandlerType

public enum HookHandlerType: String, Codable, Equatable, Sendable {
    case command
    case codex
}

// MARK: - HookExecutionMode

public enum HookExecutionMode: String, Codable, Equatable, Sendable {
    case sequential
    case parallel
}

// MARK: - HookScope

public enum HookScope: String, Codable, Equatable, Sendable {
    case local
    case global
}

// MARK: - HookSource

public enum HookSource: Codable, Equatable, Sendable {
    case agentConfig
    case profile(name: String)
    case project
    case user

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "agent_config": self = .agentConfig
        case "project": self = .project
        case "user": self = .user
        default:
            if raw.hasPrefix("profile:") {
                self = .profile(name: String(raw.dropFirst(8)))
            } else {
                self = .project
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .agentConfig: try container.encode("agent_config")
        case .profile(let name): try container.encode("profile:\(name)")
        case .project: try container.encode("project")
        case .user: try container.encode("user")
        }
    }
}

// MARK: - HookTrustStatus

public enum HookTrustStatus: String, Codable, Equatable, Sendable {
    case trusted
    case untrusted
    case skippedUntrusted = "skipped_untrusted"
}

// MARK: - HookRunStatus

public enum HookRunStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case timeout
    case skipped
}

// MARK: - TruncationPolicy

public enum TruncationPolicy: Equatable, Sendable {
    case bytes(Int)
    case tokens(Int)

    public init(_ config: TruncationPolicyConfig) {
        switch config.mode {
        case .bytes: self = .bytes(Int(config.limit))
        case .tokens: self = .tokens(Int(config.limit))
        }
    }

    public var tokenBudget: Int {
        switch self {
        case .bytes(let bytes): return Int(clamping: approxTokensFromByteCount(bytes))
        case .tokens(let tokens): return tokens
        }
    }

    public var byteBudget: Int {
        switch self {
        case .bytes(let bytes): return bytes
        case .tokens(let tokens): return approxBytesForTokens(tokens)
        }
    }

    public static func * (lhs: TruncationPolicy, rhs: Double) -> TruncationPolicy {
        switch lhs {
        case .bytes(let bytes): return .bytes(Int((Double(bytes) * rhs).rounded(.up)))
        case .tokens(let tokens): return .tokens(Int((Double(tokens) * rhs).rounded(.up)))
        }
    }
}

// MARK: - FileChange

/// serde `tag = "type"`, `rename_all = "snake_case"`.
public enum FileChange: Codable, Equatable, Sendable {
    case add(content: String)
    case delete(content: String)
    case update(unifiedDiff: String, movePath: String?)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case content
        case unifiedDiff = "unified_diff"
        case movePath = "move_path"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "add":
            self = .add(content: try keys.decode(String.self, forKey: .content))
        case "delete":
            self = .delete(content: try keys.decode(String.self, forKey: .content))
        case "update":
            self = .update(
                unifiedDiff: try keys.decode(String.self, forKey: .unifiedDiff),
                movePath: try keys.decodeIfPresent(String.self, forKey: .movePath))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown FileChange: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .add(let content):
            try container.encode("add", forKey: .type_)
            try keys.encode(content, forKey: .content)
        case .delete(let content):
            try container.encode("delete", forKey: .type_)
            try keys.encode(content, forKey: .content)
        case .update(let unifiedDiff, let movePath):
            try container.encode("update", forKey: .type_)
            try keys.encode(unifiedDiff, forKey: .unifiedDiff)
            try keys.encodeIfPresent(movePath, forKey: .movePath)
        }
    }
}

public struct Chunk: Codable, Equatable, Sendable {
    /// 1-based line index of the first line in the original file.
    public var origIndex: UInt32
    public var deletedLines: [String]
    public var insertedLines: [String]

    enum CodingKeys: String, CodingKey {
        case origIndex = "orig_index"
        case deletedLines = "deleted_lines"
        case insertedLines = "inserted_lines"
    }

    public init(origIndex: UInt32, deletedLines: [String], insertedLines: [String]) {
        self.origIndex = origIndex
        self.deletedLines = deletedLines
        self.insertedLines = insertedLines
    }
}

// MARK: - ReviewDecision

/// User's decision in response to an ExecApprovalRequest.
///
/// `ApprovedExecpolicyAmendment` and `NetworkPolicyAmendment` reference
/// types defined in `approvals.swift` (same module).
public enum ReviewDecision: Codable, Equatable, Sendable {
    case approved
    case approvedExecpolicyAmendment(proposedExecpolicyAmendment: ExecPolicyAmendment)
    case approvedForSession
    case approvedMcpPolicyAmendment
    case networkPolicyAmendment(networkPolicyAmendment: NetworkPolicyAmendment)
    case denied(rejection: String)
    case timedOut
    case abort

    public static let `default`: ReviewDecision = .denied(rejection: "denied")

    public static func denied(_ rejection: String) -> ReviewDecision {
        .denied(rejection: rejection)
    }

    public var toOpaqueString: String {
        switch self {
        case .approved: return "approved"
        case .approvedExecpolicyAmendment: return "approved_with_amendment"
        case .approvedForSession: return "approved_for_session"
        case .approvedMcpPolicyAmendment: return "approved_mcp_policy_amendment"
        case .networkPolicyAmendment(let amendment):
            switch amendment.action {
            case .allow: return "approved_with_network_policy_allow"
            case .deny: return "denied_with_network_policy_deny"
            }
        case .denied: return "denied"
        case .timedOut: return "timed_out"
        case .abort: return "abort"
        }
    }

    /// serde default externally-tagged enum + `rename_all = "snake_case"`.
    private enum ExternalKey: String, CodingKey {
        case approved
        case approvedExecpolicyAmendment = "approved_execpolicy_amendment"
        case approvedForSession = "approved_for_session"
        case approvedMcpPolicyAmendment = "approved_mcp_policy_amendment"
        case networkPolicyAmendment = "network_policy_amendment"
        case denied
        case timedOut = "timed_out"
        case abort
    }

    private enum AmendmentKeys: String, CodingKey {
        case proposedExecpolicyAmendment = "proposed_execpolicy_amendment"
    }

    private enum NetworkKeys: String, CodingKey {
        case networkPolicyAmendment = "network_policy_amendment"
    }

    private enum DeniedKeys: String, CodingKey { case rejection }

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            switch raw {
            case "approved": self = .approved
            case "approved_for_session": self = .approvedForSession
            case "approved_mcp_policy_amendment": self = .approvedMcpPolicyAmendment
            case "timed_out": self = .timedOut
            case "abort": self = .abort
            default:
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown ReviewDecision: \(raw)")
            }
            return
        }
        let container = try decoder.container(keyedBy: ExternalKey.self)
        if container.contains(.approved) {
            self = .approved
        } else if container.contains(.approvedForSession) {
            self = .approvedForSession
        } else if container.contains(.approvedMcpPolicyAmendment) {
            self = .approvedMcpPolicyAmendment
        } else if container.contains(.timedOut) {
            self = .timedOut
        } else if container.contains(.abort) {
            self = .abort
        } else if container.contains(.approvedExecpolicyAmendment) {
            let nested = try container.nestedContainer(
                keyedBy: AmendmentKeys.self, forKey: .approvedExecpolicyAmendment)
            self = .approvedExecpolicyAmendment(
                proposedExecpolicyAmendment: try nested.decode(
                    ExecPolicyAmendment.self, forKey: .proposedExecpolicyAmendment))
        } else if container.contains(.networkPolicyAmendment) {
            let nested = try container.nestedContainer(
                keyedBy: NetworkKeys.self, forKey: .networkPolicyAmendment)
            self = .networkPolicyAmendment(
                networkPolicyAmendment: try nested.decode(
                    NetworkPolicyAmendment.self, forKey: .networkPolicyAmendment))
        } else if container.contains(.denied) {
            let nested = try container.nestedContainer(keyedBy: DeniedKeys.self, forKey: .denied)
            self = .denied(rejection: try nested.decode(String.self, forKey: .rejection))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown ReviewDecision variant"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .approved:
            var container = encoder.singleValueContainer()
            try container.encode("approved")
        case .approvedForSession:
            var container = encoder.singleValueContainer()
            try container.encode("approved_for_session")
        case .approvedMcpPolicyAmendment:
            var container = encoder.singleValueContainer()
            try container.encode("approved_mcp_policy_amendment")
        case .timedOut:
            var container = encoder.singleValueContainer()
            try container.encode("timed_out")
        case .abort:
            var container = encoder.singleValueContainer()
            try container.encode("abort")
        case .approvedExecpolicyAmendment(let amendment):
            var container = encoder.container(keyedBy: ExternalKey.self)
            var nested = container.nestedContainer(
                keyedBy: AmendmentKeys.self, forKey: .approvedExecpolicyAmendment)
            try nested.encode(amendment, forKey: .proposedExecpolicyAmendment)
        case .networkPolicyAmendment(let amendment):
            var container = encoder.container(keyedBy: ExternalKey.self)
            var nested = container.nestedContainer(
                keyedBy: NetworkKeys.self, forKey: .networkPolicyAmendment)
            try nested.encode(amendment, forKey: .networkPolicyAmendment)
        case .denied(let rejection):
            var container = encoder.container(keyedBy: ExternalKey.self)
            var nested = container.nestedContainer(keyedBy: DeniedKeys.self, forKey: .denied)
            try nested.encode(rejection, forKey: .rejection)
        }
    }
}

// MARK: - InterAgentCommunication

public struct InterAgentCommunication: Codable, Equatable, Sendable {
    public var id: ResponseItemId?
    public var author: AgentPath
    public var recipient: AgentPath
    public var otherRecipients: [AgentPath]
    public var content: String
    public var encryptedContent: String?
    public var internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough?
    public var triggerTurn: Bool

    enum CodingKeys: String, CodingKey {
        case id, author, recipient, content
        case otherRecipients = "other_recipients"
        case encryptedContent = "encrypted_content"
        case internalChatMessageMetadataPassthrough =
            "internal_chat_message_metadata_passthrough"
        case triggerTurn = "trigger_turn"
    }

    public init(
        author: AgentPath,
        recipient: AgentPath,
        otherRecipients: [AgentPath],
        content: String,
        triggerTurn: Bool
    ) {
        self.id = nil
        self.author = author
        self.recipient = recipient
        self.otherRecipients = otherRecipients
        self.content = content
        self.encryptedContent = nil
        self.internalChatMessageMetadataPassthrough = nil
        self.triggerTurn = triggerTurn
    }

    public static func newEncrypted(
        author: AgentPath,
        recipient: AgentPath,
        otherRecipients: [AgentPath],
        encryptedContent: String,
        triggerTurn: Bool
    ) -> InterAgentCommunication {
        var value = InterAgentCommunication(
            author: author, recipient: recipient, otherRecipients: otherRecipients,
            content: "", triggerTurn: triggerTurn)
        value.encryptedContent = encryptedContent
        return value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ResponseItemId.self, forKey: .id)
        author = try container.decode(AgentPath.self, forKey: .author)
        recipient = try container.decode(AgentPath.self, forKey: .recipient)
        otherRecipients = try container.decodeIfPresent([AgentPath].self, forKey: .otherRecipients) ?? []
        content = try container.decode(String.self, forKey: .content)
        encryptedContent = try container.decodeIfPresent(String.self, forKey: .encryptedContent)
        internalChatMessageMetadataPassthrough = try container.decodeIfPresent(
            InternalChatMessageMetadataPassthrough.self,
            forKey: .internalChatMessageMetadataPassthrough)
        triggerTurn = try container.decode(Bool.self, forKey: .triggerTurn)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(otherRecipients, forKey: .otherRecipients)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(encryptedContent, forKey: .encryptedContent)
        try container.encodeIfPresent(
            internalChatMessageMetadataPassthrough,
            forKey: .internalChatMessageMetadataPassthrough)
        try container.encode(triggerTurn, forKey: .triggerTurn)
    }
}

// MARK: - Session / thread source

public enum InternalSessionSource: String, Codable, Equatable, Sendable {
    case memoryConsolidation = "memory_consolidation"
    case guardian
}

public enum SubAgentSource: Codable, Equatable, Sendable {
    case review
    case compact
    case threadSpawn(
        parentThreadId: ThreadId, depth: Int32, agentPath: AgentPath?,
        agentNickname: String?, agentRole: String?)
    case memoryConsolidation
    case other(String)

    private enum ExternalKey: String, CodingKey {
        case review, compact
        case threadSpawn = "thread_spawn"
        case memoryConsolidation = "memory_consolidation"
        case other
    }

    private enum SpawnKeys: String, CodingKey {
        case parentThreadId = "parent_thread_id"
        case depth
        case agentPath = "agent_path"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
    }

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            switch raw {
            case "review": self = .review
            case "compact": self = .compact
            case "memory_consolidation": self = .memoryConsolidation
            default: self = .other(raw)
            }
            return
        }
        let container = try decoder.container(keyedBy: ExternalKey.self)
        if container.contains(.review) {
            self = .review
        } else if container.contains(.compact) {
            self = .compact
        } else if container.contains(.memoryConsolidation) {
            self = .memoryConsolidation
        } else if container.contains(.other) {
            self = .other(try container.decode(String.self, forKey: .other))
        } else if container.contains(.threadSpawn) {
            let nested = try container.nestedContainer(keyedBy: SpawnKeys.self, forKey: .threadSpawn)
            self = .threadSpawn(
                parentThreadId: try nested.decode(ThreadId.self, forKey: .parentThreadId),
                depth: try nested.decode(Int32.self, forKey: .depth),
                agentPath: try nested.decodeIfPresent(AgentPath.self, forKey: .agentPath),
                agentNickname: try nested.decodeIfPresent(String.self, forKey: .agentNickname),
                agentRole: try nested.decodeIfPresent(String.self, forKey: .agentRole)
                    ?? nested.decodeIfPresent(String.self, forKey: .agentType))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown SubAgentSource"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .review:
            var container = encoder.singleValueContainer()
            try container.encode("review")
        case .compact:
            var container = encoder.singleValueContainer()
            try container.encode("compact")
        case .memoryConsolidation:
            var container = encoder.singleValueContainer()
            try container.encode("memory_consolidation")
        case .other(let value):
            var container = encoder.container(keyedBy: ExternalKey.self)
            try container.encode(value, forKey: .other)
        case .threadSpawn(let parent, let depth, let path, let nickname, let role):
            var container = encoder.container(keyedBy: ExternalKey.self)
            var nested = container.nestedContainer(keyedBy: SpawnKeys.self, forKey: .threadSpawn)
            try nested.encode(parent, forKey: .parentThreadId)
            try nested.encode(depth, forKey: .depth)
            try nested.encodeIfPresent(path, forKey: .agentPath)
            try nested.encodeIfPresent(nickname, forKey: .agentNickname)
            try nested.encodeIfPresent(role, forKey: .agentRole)
        }
    }
}

public enum SessionSource: Codable, Equatable, Sendable {
    case cli
    case vsCode
    case exec
    case mcp
    case custom(String)
    case `internal`(InternalSessionSource)
    case subAgent(SubAgentSource)
    case unknown

    public static let `default`: SessionSource = .vsCode

    private enum ExternalKey: String, CodingKey {
        case cli, vscode, exec, mcp, custom, unknown
        case `internal`
        case subAgent = "subagent"
    }

    public init(from decoder: any Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            switch raw {
            case "cli": self = .cli
            case "vscode": self = .vsCode
            case "exec": self = .exec
            case "mcp": self = .mcp
            default: self = .unknown
            }
            return
        }
        let container = try decoder.container(keyedBy: ExternalKey.self)
        if container.contains(.cli) { self = .cli }
        else if container.contains(.vscode) { self = .vsCode }
        else if container.contains(.exec) { self = .exec }
        else if container.contains(.mcp) { self = .mcp }
        else if container.contains(.unknown) { self = .unknown }
        else if container.contains(.custom) {
            self = .custom(try container.decode(String.self, forKey: .custom))
        } else if container.contains(.internal) {
            self = .internal(try container.decode(InternalSessionSource.self, forKey: .internal))
        } else if container.contains(.subAgent) {
            self = .subAgent(try container.decode(SubAgentSource.self, forKey: .subAgent))
        } else {
            self = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .cli:
            var container = encoder.singleValueContainer()
            try container.encode("cli")
        case .vsCode:
            var container = encoder.singleValueContainer()
            try container.encode("vscode")
        case .exec:
            var container = encoder.singleValueContainer()
            try container.encode("exec")
        case .mcp:
            var container = encoder.singleValueContainer()
            try container.encode("mcp")
        case .unknown:
            var container = encoder.singleValueContainer()
            try container.encode("unknown")
        case .custom(let value):
            var container = encoder.container(keyedBy: ExternalKey.self)
            try container.encode(value, forKey: .custom)
        case .internal(let source):
            var container = encoder.container(keyedBy: ExternalKey.self)
            try container.encode(source, forKey: .internal)
        case .subAgent(let source):
            var container = encoder.container(keyedBy: ExternalKey.self)
            try container.encode(source, forKey: .subAgent)
        }
    }

    public static func fromStartupArg(_ value: String) throws -> SessionSource {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SessionSourceParseError.empty }
        switch trimmed.lowercased() {
        case "cli": return .cli
        case "vscode": return .vsCode
        case "exec": return .exec
        case "mcp", "appserver", "app-server", "app_server": return .mcp
        case "unknown": return .unknown
        default: return .custom(trimmed.lowercased())
        }
    }
}

public struct SessionSourceParseError: Error, Equatable {
    public static let empty = SessionSourceParseError()
}

public enum ThreadSource: Codable, Equatable, Sendable, CustomStringConvertible {
    case user
    case subagent
    case guardianReview
    case feature(String)
    case memoryConsolidation

    public var asStr: String {
        switch self {
        case .user: return "user"
        case .subagent: return "subagent"
        case .guardianReview: return "guardian_review"
        case .feature(let feature): return feature
        case .memoryConsolidation: return "memory_consolidation"
        }
    }

    public var description: String { asStr }

    public init(_ value: String) {
        switch value {
        case "user": self = .user
        case "subagent": self = .subagent
        case "guardian_review": self = .guardianReview
        case "memory_consolidation": self = .memoryConsolidation
        default: self = .feature(value)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(asStr)
    }
}

// MARK: - Rate limits / misalignment

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int64?
    public var resetsAt: Int64?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    public init(usedPercent: Double, windowMinutes: Int64? = nil, resetsAt: Int64? = nil) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public enum RateLimitReachedType: String, Codable, Equatable, Sendable {
    case rateLimitReached = "rate_limit_reached"
    case workspaceOwnerCreditsDepleted = "workspace_owner_credits_depleted"
    case workspaceMemberCreditsDepleted = "workspace_member_credits_depleted"
    case workspaceOwnerUsageLimitReached = "workspace_owner_usage_limit_reached"
    case workspaceMemberUsageLimitReached = "workspace_member_usage_limit_reached"
}

public struct CreditsSnapshot: Codable, Equatable, Sendable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited, balance
    }
}

public struct SpendControlLimitSnapshot: Codable, Equatable, Sendable {
    public var limit: String
    public var used: String
    public var remainingPercent: Int32
    public var resetsAt: Int64

    enum CodingKeys: String, CodingKey {
        case limit, used
        case remainingPercent = "remaining_percent"
        case resetsAt = "resets_at"
    }
}

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var normalModelSlug: String?
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
    public var credits: CreditsSnapshot?
    public var individualLimit: SpendControlLimitSnapshot?
    public var spendControlReached: Bool?
    public var planType: AuthPlanType?
    public var rateLimitReachedType: RateLimitReachedType?

    enum CodingKeys: String, CodingKey {
        case limitId = "limit_id"
        case limitName = "limit_name"
        case normalModelSlug = "normal_model_slug"
        case primary, secondary, credits
        case individualLimit = "individual_limit"
        case spendControlReached = "spend_control_reached"
        case planType = "plan_type"
        case rateLimitReachedType = "rate_limit_reached_type"
    }

    public init(
        limitId: String? = nil,
        limitName: String? = nil,
        normalModelSlug: String? = nil,
        primary: RateLimitWindow? = nil,
        secondary: RateLimitWindow? = nil,
        credits: CreditsSnapshot? = nil,
        individualLimit: SpendControlLimitSnapshot? = nil,
        spendControlReached: Bool? = nil,
        planType: AuthPlanType? = nil,
        rateLimitReachedType: RateLimitReachedType? = nil
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.normalModelSlug = normalModelSlug
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.individualLimit = individualLimit
        self.spendControlReached = spendControlReached
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }
}

public struct MisalignmentSteer: Codable, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
}

public struct MisalignmentErrorDetails: Codable, Equatable, Sendable {
    public var errorType: String?
    public var detailedExplanation: String?
    public var steer: MisalignmentSteer?

    enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
        case detailedExplanation = "detailed_explanation"
        case steer
    }

    public init(
        errorType: String? = nil,
        detailedExplanation: String? = nil,
        steer: MisalignmentSteer? = nil
    ) {
        self.errorType = errorType
        self.detailedExplanation = detailedExplanation
        self.steer = steer
    }
}

// MARK: - Review / exec / patch enums used by items + events

public enum ReviewTarget: Codable, Equatable, Sendable {
    case uncommittedChanges
    case baseBranch(branch: String)
    case commit(sha: String, title: String?)
    case custom(instructions: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum Keys: String, CodingKey {
        case branch, sha, title, instructions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let keys = try decoder.container(keyedBy: Keys.self)
        switch type_ {
        case "uncommittedChanges":
            self = .uncommittedChanges
        case "baseBranch":
            self = .baseBranch(branch: try keys.decode(String.self, forKey: .branch))
        case "commit":
            self = .commit(
                sha: try keys.decode(String.self, forKey: .sha),
                title: try keys.decodeIfPresent(String.self, forKey: .title))
        case "custom":
            self = .custom(instructions: try keys.decode(String.self, forKey: .instructions))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container, debugDescription: "Unknown ReviewTarget: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var keys = encoder.container(keyedBy: Keys.self)
        switch self {
        case .uncommittedChanges:
            try container.encode("uncommittedChanges", forKey: .type_)
        case .baseBranch(let branch):
            try container.encode("baseBranch", forKey: .type_)
            try keys.encode(branch, forKey: .branch)
        case .commit(let sha, let title):
            try container.encode("commit", forKey: .type_)
            try keys.encode(sha, forKey: .sha)
            try keys.encodeIfPresent(title, forKey: .title)
        case .custom(let instructions):
            try container.encode("custom", forKey: .type_)
            try keys.encode(instructions, forKey: .instructions)
        }
    }
}

public enum ExecCommandSource: String, Codable, Equatable, Sendable {
    case agent
    case userShell = "user_shell"
    case unifiedExecStartup = "unified_exec_startup"
    case unifiedExecInteraction = "unified_exec_interaction"

    public static let `default`: ExecCommandSource = .agent
}

public enum ExecCommandStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case declined
}

public enum PatchApplyStatus: String, Codable, Equatable, Sendable {
    case completed
    case failed
    case declined
}

public enum SubAgentActivityKind: String, Codable, Equatable, Sendable {
    case started
    case interacted
    case interrupted
    case completed
}

public enum UserMessageImageKind: String, Codable, Equatable, Sendable {
    case inline
    case file
}

public struct ImageGenerationFailure: Codable, Equatable, Sendable {
    public var message: String?
    public init(message: String? = nil) { self.message = message }
}

// MARK: - Duration wire helper (serde std::time::Duration)

struct SerdeDuration: Codable, Equatable, Sendable {
    var secs: UInt64
    var nanos: UInt32

    init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        secs = UInt64(clamping: max(seconds, 0))
        nanos = UInt32(clamping: attoseconds / 1_000_000_000)
    }

    var duration: Duration {
        .seconds(Int64(secs)) + .nanoseconds(Int64(nanos))
    }
}

func encodeDuration(_ duration: Duration, to encoder: any Encoder) throws {
    try SerdeDuration(duration).encode(to: encoder)
}

func decodeDuration(from decoder: any Decoder) throws -> Duration {
    try SerdeDuration(from: decoder).duration
}

/// serde externally-tagged `Result<T, String>` (`{"Ok": T}` / `{"Err": "..."}`).
public enum SerdeResult<T: Equatable & Sendable>: Equatable, Sendable {
    case success(T)
    case failure(String)
}

func encodeResult<T: Encodable>(_ result: SerdeResult<T>, to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: ResultKey.self)
    switch result {
    case .success(let value): try container.encode(value, forKey: .ok)
    case .failure(let error): try container.encode(error, forKey: .err)
    }
}

func decodeResult<T: Decodable>(_ type: T.Type, from decoder: any Decoder) throws -> SerdeResult<T> {
    let container = try decoder.container(keyedBy: ResultKey.self)
    if container.contains(.ok) {
        return .success(try container.decode(T.self, forKey: .ok))
    }
    return .failure(try container.decode(String.self, forKey: .err))
}

private enum ResultKey: String, CodingKey {
    case ok = "Ok"
    case err = "Err"
}

// MARK: - Event / EventMsg (partial — variants needed by items + legacy_events)

public struct Event: Codable, Equatable, Sendable {
    public var id: String
    public var msg: EventMsg

    public init(id: String, msg: EventMsg) {
        self.id = id; self.msg = msg
    }
}

public struct ContextCompactedEvent: Codable, Equatable, Sendable {
    public init() {}
}

public struct AgentMessageEvent: Codable, Equatable, Sendable {
    public var message: String
    public var phase: MessagePhase?
    public var memoryCitation: MemoryCitation?
    public var delivery: AgentMessageDelivery?
    public var questions: [AsyncUserInputQuestion]?

    enum CodingKeys: String, CodingKey {
        case message, phase, delivery, questions
        case memoryCitation = "memory_citation"
    }

    public init(
        message: String,
        phase: MessagePhase? = nil,
        memoryCitation: MemoryCitation? = nil,
        delivery: AgentMessageDelivery? = nil,
        questions: [AsyncUserInputQuestion]? = nil
    ) {
        self.message = message
        self.phase = phase
        self.memoryCitation = memoryCitation
        self.delivery = delivery
        self.questions = questions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        phase = try container.decodeIfPresent(MessagePhase.self, forKey: .phase)
        memoryCitation = try container.decodeIfPresent(MemoryCitation.self, forKey: .memoryCitation)
        delivery = try container.decodeIfPresent(AgentMessageDelivery.self, forKey: .delivery)
        questions = try container.decodeIfPresent([AsyncUserInputQuestion].self, forKey: .questions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(phase, forKey: .phase)
        try container.encode(memoryCitation, forKey: .memoryCitation)
        try container.encodeIfPresent(delivery, forKey: .delivery)
        try container.encodeIfPresent(questions, forKey: .questions)
    }
}

public struct UserMessageEvent: Codable, Equatable, Sendable {
    public var clientId: String?
    public var message: String
    public var images: [String]?
    public var imageDetails: [ImageDetail?]
    public var fileIds: [String]?
    public var fileIdDetails: [ImageDetail?]
    public var imageOrder: [UserMessageImageKind]
    public var localImages: [String]
    public var localImageDetails: [ImageDetail?]
    public var audio: [String]?
    public var localAudio: [String]
    public var textElements: [TextElement]

    enum CodingKeys: String, CodingKey {
        case message, images, audio
        case clientId = "client_id"
        case imageDetails = "image_details"
        case fileIds = "file_ids"
        case fileIdDetails = "file_id_details"
        case imageOrder = "image_order"
        case localImages = "local_images"
        case localImageDetails = "local_image_details"
        case localAudio = "local_audio"
        case textElements = "text_elements"
    }

    public init(
        clientId: String? = nil,
        message: String,
        images: [String]? = nil,
        imageDetails: [ImageDetail?] = [],
        fileIds: [String]? = nil,
        fileIdDetails: [ImageDetail?] = [],
        imageOrder: [UserMessageImageKind] = [],
        localImages: [String] = [],
        localImageDetails: [ImageDetail?] = [],
        audio: [String]? = nil,
        localAudio: [String] = [],
        textElements: [TextElement] = []
    ) {
        self.clientId = clientId
        self.message = message
        self.images = images
        self.imageDetails = imageDetails
        self.fileIds = fileIds
        self.fileIdDetails = fileIdDetails
        self.imageOrder = imageOrder
        self.localImages = localImages
        self.localImageDetails = localImageDetails
        self.audio = audio
        self.localAudio = localAudio
        self.textElements = textElements
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        message = try container.decode(String.self, forKey: .message)
        images = try container.decodeIfPresent([String].self, forKey: .images)
        imageDetails = try container.decodeIfPresent([ImageDetail?].self, forKey: .imageDetails) ?? []
        fileIds = try container.decodeIfPresent([String].self, forKey: .fileIds)
        fileIdDetails = try container.decodeIfPresent([ImageDetail?].self, forKey: .fileIdDetails) ?? []
        imageOrder = try container.decodeIfPresent([UserMessageImageKind].self, forKey: .imageOrder) ?? []
        localImages = try container.decodeIfPresent([String].self, forKey: .localImages) ?? []
        localImageDetails = try container.decodeIfPresent([ImageDetail?].self, forKey: .localImageDetails) ?? []
        audio = try container.decodeIfPresent([String].self, forKey: .audio)
        localAudio = try container.decodeIfPresent([String].self, forKey: .localAudio) ?? []
        textElements = try container.decodeIfPresent([TextElement].self, forKey: .textElements) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(clientId, forKey: .clientId)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(images, forKey: .images)
        if !imageDetails.isEmpty { try container.encode(imageDetails, forKey: .imageDetails) }
        try container.encodeIfPresent(fileIds, forKey: .fileIds)
        if !fileIdDetails.isEmpty { try container.encode(fileIdDetails, forKey: .fileIdDetails) }
        if !imageOrder.isEmpty { try container.encode(imageOrder, forKey: .imageOrder) }
        try container.encode(localImages, forKey: .localImages)
        if !localImageDetails.isEmpty { try container.encode(localImageDetails, forKey: .localImageDetails) }
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encode(localAudio, forKey: .localAudio)
        try container.encode(textElements, forKey: .textElements)
    }
}

public struct AgentReasoningEvent: Codable, Equatable, Sendable {
    public var text: String
    public init(text: String) { self.text = text }
}

public struct AgentReasoningRawContentEvent: Codable, Equatable, Sendable {
    public var text: String
    public init(text: String) { self.text = text }
}

public struct McpInvocation: Codable, Equatable, Sendable {
    public var server: String
    public var tool: String
    public var arguments: JSONValue?

    public init(server: String, tool: String, arguments: JSONValue? = nil) {
        self.server = server; self.tool = tool; self.arguments = arguments
    }
}

public struct CollabAgentRef: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var agentNickname: String?
    public var agentRole: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
    }

    public init(threadId: ThreadId, agentNickname: String? = nil, agentRole: String? = nil) {
        self.threadId = threadId
        self.agentNickname = agentNickname
        self.agentRole = agentRole
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(ThreadId.self, forKey: .threadId)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
            ?? container.decodeIfPresent(String.self, forKey: .agentType)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
    }
}

public struct CollabAgentStatusEntry: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var agentNickname: String?
    public var agentRole: String?
    public var status: AgentStatus

    enum CodingKeys: String, CodingKey {
        case status
        case threadId = "thread_id"
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case agentType = "agent_type"
    }

    public init(
        threadId: ThreadId, agentNickname: String? = nil, agentRole: String? = nil,
        status: AgentStatus
    ) {
        self.threadId = threadId
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.status = status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(ThreadId.self, forKey: .threadId)
        agentNickname = try container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
            ?? container.decodeIfPresent(String.self, forKey: .agentType)
        status = try container.decode(AgentStatus.self, forKey: .status)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encodeIfPresent(agentNickname, forKey: .agentNickname)
        try container.encodeIfPresent(agentRole, forKey: .agentRole)
        try container.encode(status, forKey: .status)
    }
}

public struct ItemStartedEvent: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var turnId: String
    public var item: TurnItem
    public var startedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case item
        case threadId = "thread_id"
        case turnId = "turn_id"
        case startedAtMs = "started_at_ms"
    }

    public init(threadId: ThreadId, turnId: String, item: TurnItem, startedAtMs: Int64) {
        self.threadId = threadId
        self.turnId = turnId
        self.item = item
        self.startedAtMs = startedAtMs
    }
}

public struct ItemCompletedEvent: Codable, Equatable, Sendable {
    public var threadId: ThreadId
    public var turnId: String
    public var item: TurnItem
    public var startedAtMs: Int64?
    public var completedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case item
        case threadId = "thread_id"
        case turnId = "turn_id"
        case startedAtMs = "started_at_ms"
        case completedAtMs = "completed_at_ms"
    }

    public init(
        threadId: ThreadId, turnId: String, item: TurnItem,
        startedAtMs: Int64? = nil, completedAtMs: Int64 = 0
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.item = item
        self.startedAtMs = startedAtMs
        self.completedAtMs = completedAtMs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(ThreadId.self, forKey: .threadId)
        turnId = try container.decode(String.self, forKey: .turnId)
        item = try container.decode(TurnItem.self, forKey: .item)
        startedAtMs = try container.decodeIfPresent(Int64.self, forKey: .startedAtMs)
        completedAtMs = try container.decodeIfPresent(Int64.self, forKey: .completedAtMs) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(item, forKey: .item)
        try container.encodeIfPresent(startedAtMs, forKey: .startedAtMs)
        try container.encode(completedAtMs, forKey: .completedAtMs)
    }
}

public struct AgentMessageContentDeltaEvent: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var delta: String

    enum CodingKeys: String, CodingKey {
        case delta
        case threadId = "thread_id"
        case turnId = "turn_id"
        case itemId = "item_id"
    }

    public init(threadId: String, turnId: String, itemId: String, delta: String) {
        self.threadId = threadId; self.turnId = turnId; self.itemId = itemId; self.delta = delta
    }
}

public struct ReasoningContentDeltaEvent: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var delta: String
    public var summaryIndex: Int64

    enum CodingKeys: String, CodingKey {
        case delta
        case threadId = "thread_id"
        case turnId = "turn_id"
        case itemId = "item_id"
        case summaryIndex = "summary_index"
    }

    public init(
        threadId: String, turnId: String, itemId: String, delta: String, summaryIndex: Int64 = 0
    ) {
        self.threadId = threadId; self.turnId = turnId; self.itemId = itemId
        self.delta = delta; self.summaryIndex = summaryIndex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        turnId = try container.decode(String.self, forKey: .turnId)
        itemId = try container.decode(String.self, forKey: .itemId)
        delta = try container.decode(String.self, forKey: .delta)
        summaryIndex = try container.decodeIfPresent(Int64.self, forKey: .summaryIndex) ?? 0
    }
}

public struct ReasoningRawContentDeltaEvent: Codable, Equatable, Sendable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var delta: String
    public var contentIndex: Int64

    enum CodingKeys: String, CodingKey {
        case delta
        case threadId = "thread_id"
        case turnId = "turn_id"
        case itemId = "item_id"
        case contentIndex = "content_index"
    }

    public init(
        threadId: String, turnId: String, itemId: String, delta: String, contentIndex: Int64 = 0
    ) {
        self.threadId = threadId; self.turnId = turnId; self.itemId = itemId
        self.delta = delta; self.contentIndex = contentIndex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        turnId = try container.decode(String.self, forKey: .turnId)
        itemId = try container.decode(String.self, forKey: .itemId)
        delta = try container.decode(String.self, forKey: .delta)
        contentIndex = try container.decodeIfPresent(Int64.self, forKey: .contentIndex) ?? 0
    }
}

public struct EnteredReviewModeEvent: Codable, Equatable, Sendable {
    public var target: ReviewTarget
    public var userFacingHint: String?
    public var turnId: String?
    public var itemId: String?

    enum CodingKeys: String, CodingKey {
        case target
        case userFacingHint = "user_facing_hint"
        case turnId = "turn_id"
        case itemId = "item_id"
    }

    public init(
        target: ReviewTarget, userFacingHint: String? = nil, turnId: String? = nil,
        itemId: String? = nil
    ) {
        self.target = target
        self.userFacingHint = userFacingHint
        self.turnId = turnId
        self.itemId = itemId
    }
}

public struct ExitedReviewModeEvent: Codable, Equatable, Sendable {
    public var turnId: String?
    public var itemId: String?
    public var reviewOutput: ReviewOutputEvent?

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case itemId = "item_id"
        case reviewOutput = "review_output"
    }

    public init(turnId: String? = nil, itemId: String? = nil, reviewOutput: ReviewOutputEvent? = nil) {
        self.turnId = turnId; self.itemId = itemId; self.reviewOutput = reviewOutput
    }
}

public struct WebSearchBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    enum CodingKeys: String, CodingKey { case callId = "call_id" }
    public init(callId: String) { self.callId = callId }
}

public struct WebSearchEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var query: String
    public var action: WebSearchAction
    public var results: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case query, action, results
        case callId = "call_id"
    }

    public init(
        callId: String, query: String, action: WebSearchAction, results: [JSONValue]? = nil
    ) {
        self.callId = callId; self.query = query; self.action = action; self.results = results
    }
}

public struct ImageGenerationBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    enum CodingKeys: String, CodingKey { case callId = "call_id" }
    public init(callId: String) { self.callId = callId }
}

public struct ImageGenerationEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var status: String
    public var revisedPrompt: String?
    public var result: String
    public var transparentBackground: Bool?
    public var failure: ImageGenerationFailure?
    public var savedPath: AbsolutePathBuf?

    enum CodingKeys: String, CodingKey {
        case status, result, failure
        case callId = "call_id"
        case revisedPrompt = "revised_prompt"
        case transparentBackground = "transparent_background"
        case savedPath = "saved_path"
    }

    public init(
        callId: String, status: String, revisedPrompt: String? = nil, result: String,
        transparentBackground: Bool? = nil, failure: ImageGenerationFailure? = nil,
        savedPath: AbsolutePathBuf? = nil
    ) {
        self.callId = callId; self.status = status; self.revisedPrompt = revisedPrompt
        self.result = result; self.transparentBackground = transparentBackground
        self.failure = failure; self.savedPath = savedPath
    }
}

public struct ViewImageToolCallEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var path: PathUri

    enum CodingKeys: String, CodingKey {
        case path
        case callId = "call_id"
    }

    public init(callId: String, path: PathUri) {
        self.callId = callId; self.path = path
    }
}

public struct DynamicToolCallResponseEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var completedAtMs: Int64
    public var namespace: String?
    public var tool: String
    public var arguments: JSONValue
    public var contentItems: [DynamicToolCallOutputContentItem]
    public var success: Bool
    public var error: String?
    public var duration: Duration

    enum CodingKeys: String, CodingKey {
        case namespace, tool, arguments, success, error, duration
        case callId = "call_id"
        case turnId = "turn_id"
        case completedAtMs = "completed_at_ms"
        case contentItems = "content_items"
    }

    public init(
        callId: String, turnId: String, completedAtMs: Int64 = 0, namespace: String? = nil,
        tool: String, arguments: JSONValue, contentItems: [DynamicToolCallOutputContentItem],
        success: Bool, error: String? = nil, duration: Duration = .zero
    ) {
        self.callId = callId; self.turnId = turnId; self.completedAtMs = completedAtMs
        self.namespace = namespace; self.tool = tool; self.arguments = arguments
        self.contentItems = contentItems; self.success = success; self.error = error
        self.duration = duration
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decode(String.self, forKey: .turnId)
        completedAtMs = try container.decodeIfPresent(Int64.self, forKey: .completedAtMs) ?? 0
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
        contentItems = try container.decode([DynamicToolCallOutputContentItem].self, forKey: .contentItems)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        duration = try container.decodeIfPresent(SerdeDuration.self, forKey: .duration)?.duration ?? .zero
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(completedAtMs, forKey: .completedAtMs)
        try container.encode(namespace, forKey: .namespace)
        try container.encode(tool, forKey: .tool)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(contentItems, forKey: .contentItems)
        try container.encode(success, forKey: .success)
        try container.encode(error, forKey: .error)
        try container.encode(SerdeDuration(duration), forKey: .duration)
    }
}

public struct SubAgentActivityEvent: Codable, Equatable, Sendable {
    public var eventId: String
    public var occurredAtMs: Int64
    public var agentThreadId: ThreadId
    public var agentPath: AgentPath
    public var kind: SubAgentActivityKind

    enum CodingKeys: String, CodingKey {
        case kind
        case eventId = "event_id"
        case occurredAtMs = "occurred_at_ms"
        case agentThreadId = "agent_thread_id"
        case agentPath = "agent_path"
    }

    public init(
        eventId: String, occurredAtMs: Int64 = 0, agentThreadId: ThreadId,
        agentPath: AgentPath, kind: SubAgentActivityKind
    ) {
        self.eventId = eventId; self.occurredAtMs = occurredAtMs
        self.agentThreadId = agentThreadId; self.agentPath = agentPath; self.kind = kind
    }
}

public enum EventMsg: Equatable, Sendable {
    case error(ErrorEvent)
    case contextCompacted(ContextCompactedEvent)
    case turnStarted(TurnStartedEvent)
    case turnComplete(TurnCompleteEvent)
    case agentMessage(AgentMessageEvent)
    case userMessage(UserMessageEvent)
    case agentReasoning(AgentReasoningEvent)
    case agentReasoningRawContent(AgentReasoningRawContentEvent)
    case mcpToolCallBegin(McpToolCallBeginEvent)
    case mcpToolCallEnd(McpToolCallEndEvent)
    case webSearchBegin(WebSearchBeginEvent)
    case webSearchEnd(WebSearchEndEvent)
    case imageGenerationBegin(ImageGenerationBeginEvent)
    case imageGenerationEnd(ImageGenerationEndEvent)
    case execCommandBegin(ExecCommandBeginEvent)
    case execCommandEnd(ExecCommandEndEvent)
    case viewImageToolCall(ViewImageToolCallEvent)
    case execApprovalRequest(ExecApprovalRequestEvent)
    case applyPatchApprovalRequest(ApplyPatchApprovalRequestEvent)
    case guardianAssessment(GuardianAssessmentEvent)
    case elicitationRequest(ElicitationRequestEvent)
    case dynamicToolCallRequest(DynamicToolCallRequest)
    case dynamicToolCallResponse(DynamicToolCallResponseEvent)
    case patchApplyBegin(PatchApplyBeginEvent)
    case patchApplyEnd(PatchApplyEndEvent)
    case enteredReviewMode(EnteredReviewModeEvent)
    case exitedReviewMode(ExitedReviewModeEvent)
    case itemStarted(ItemStartedEvent)
    case itemCompleted(ItemCompletedEvent)
    case agentMessageContentDelta(AgentMessageContentDeltaEvent)
    case reasoningContentDelta(ReasoningContentDeltaEvent)
    case reasoningRawContentDelta(ReasoningRawContentDeltaEvent)
    case collabAgentSpawnBegin(CollabAgentSpawnBeginEvent)
    case collabAgentSpawnEnd(CollabAgentSpawnEndEvent)
    case collabAgentInteractionBegin(CollabAgentInteractionBeginEvent)
    case collabAgentInteractionEnd(CollabAgentInteractionEndEvent)
    case collabWaitingBegin(CollabWaitingBeginEvent)
    case collabWaitingEnd(CollabWaitingEndEvent)
    case collabCloseBegin(CollabCloseBeginEvent)
    case collabCloseEnd(CollabCloseEndEvent)
    case collabResumeBegin(CollabResumeBeginEvent)
    case collabResumeEnd(CollabResumeEndEvent)
    case subAgentActivity(SubAgentActivityEvent)
}

extension EventMsg: Codable {
    private enum TypeKey: String, CodingKey { case type_ = "type" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "error": self = .error(try ErrorEvent(from: decoder))
        case "context_compacted": self = .contextCompacted(try ContextCompactedEvent(from: decoder))
        case "task_started", "turn_started": self = .turnStarted(try TurnStartedEvent(from: decoder))
        case "task_complete", "turn_complete": self = .turnComplete(try TurnCompleteEvent(from: decoder))
        case "agent_message": self = .agentMessage(try AgentMessageEvent(from: decoder))
        case "user_message": self = .userMessage(try UserMessageEvent(from: decoder))
        case "agent_reasoning": self = .agentReasoning(try AgentReasoningEvent(from: decoder))
        case "agent_reasoning_raw_content":
            self = .agentReasoningRawContent(try AgentReasoningRawContentEvent(from: decoder))
        case "mcp_tool_call_begin": self = .mcpToolCallBegin(try McpToolCallBeginEvent(from: decoder))
        case "mcp_tool_call_end": self = .mcpToolCallEnd(try McpToolCallEndEvent(from: decoder))
        case "web_search_begin": self = .webSearchBegin(try WebSearchBeginEvent(from: decoder))
        case "web_search_end": self = .webSearchEnd(try WebSearchEndEvent(from: decoder))
        case "image_generation_begin":
            self = .imageGenerationBegin(try ImageGenerationBeginEvent(from: decoder))
        case "image_generation_end":
            self = .imageGenerationEnd(try ImageGenerationEndEvent(from: decoder))
        case "exec_command_begin": self = .execCommandBegin(try ExecCommandBeginEvent(from: decoder))
        case "exec_command_end": self = .execCommandEnd(try ExecCommandEndEvent(from: decoder))
        case "view_image_tool_call":
            self = .viewImageToolCall(try ViewImageToolCallEvent(from: decoder))
        case "exec_approval_request":
            self = .execApprovalRequest(try ExecApprovalRequestEvent(from: decoder))
        case "apply_patch_approval_request":
            self = .applyPatchApprovalRequest(try ApplyPatchApprovalRequestEvent(from: decoder))
        case "guardian_assessment":
            self = .guardianAssessment(try GuardianAssessmentEvent(from: decoder))
        case "elicitation_request":
            self = .elicitationRequest(try ElicitationRequestEvent(from: decoder))
        case "dynamic_tool_call_request":
            self = .dynamicToolCallRequest(try DynamicToolCallRequest(from: decoder))
        case "dynamic_tool_call_response":
            self = .dynamicToolCallResponse(try DynamicToolCallResponseEvent(from: decoder))
        case "patch_apply_begin": self = .patchApplyBegin(try PatchApplyBeginEvent(from: decoder))
        case "patch_apply_end": self = .patchApplyEnd(try PatchApplyEndEvent(from: decoder))
        case "entered_review_mode":
            self = .enteredReviewMode(try EnteredReviewModeEvent(from: decoder))
        case "exited_review_mode":
            self = .exitedReviewMode(try ExitedReviewModeEvent(from: decoder))
        case "item_started": self = .itemStarted(try ItemStartedEvent(from: decoder))
        case "item_completed": self = .itemCompleted(try ItemCompletedEvent(from: decoder))
        case "agent_message_content_delta":
            self = .agentMessageContentDelta(try AgentMessageContentDeltaEvent(from: decoder))
        case "reasoning_content_delta":
            self = .reasoningContentDelta(try ReasoningContentDeltaEvent(from: decoder))
        case "reasoning_raw_content_delta":
            self = .reasoningRawContentDelta(try ReasoningRawContentDeltaEvent(from: decoder))
        case "collab_agent_spawn_begin":
            self = .collabAgentSpawnBegin(try CollabAgentSpawnBeginEvent(from: decoder))
        case "collab_agent_spawn_end":
            self = .collabAgentSpawnEnd(try CollabAgentSpawnEndEvent(from: decoder))
        case "collab_agent_interaction_begin":
            self = .collabAgentInteractionBegin(try CollabAgentInteractionBeginEvent(from: decoder))
        case "collab_agent_interaction_end":
            self = .collabAgentInteractionEnd(try CollabAgentInteractionEndEvent(from: decoder))
        case "collab_waiting_begin":
            self = .collabWaitingBegin(try CollabWaitingBeginEvent(from: decoder))
        case "collab_waiting_end":
            self = .collabWaitingEnd(try CollabWaitingEndEvent(from: decoder))
        case "collab_close_begin": self = .collabCloseBegin(try CollabCloseBeginEvent(from: decoder))
        case "collab_close_end": self = .collabCloseEnd(try CollabCloseEndEvent(from: decoder))
        case "collab_resume_begin":
            self = .collabResumeBegin(try CollabResumeBeginEvent(from: decoder))
        case "collab_resume_end": self = .collabResumeEnd(try CollabResumeEndEvent(from: decoder))
        case "sub_agent_activity":
            self = .subAgentActivity(try SubAgentActivityEvent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown EventMsg: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .error(let event):
            try container.encode("error", forKey: .type_); try event.encode(to: encoder)
        case .contextCompacted(let event):
            try container.encode("context_compacted", forKey: .type_); try event.encode(to: encoder)
        case .turnStarted(let event):
            try container.encode("task_started", forKey: .type_); try event.encode(to: encoder)
        case .turnComplete(let event):
            try container.encode("task_complete", forKey: .type_); try event.encode(to: encoder)
        case .agentMessage(let event):
            try container.encode("agent_message", forKey: .type_); try event.encode(to: encoder)
        case .userMessage(let event):
            try container.encode("user_message", forKey: .type_); try event.encode(to: encoder)
        case .agentReasoning(let event):
            try container.encode("agent_reasoning", forKey: .type_); try event.encode(to: encoder)
        case .agentReasoningRawContent(let event):
            try container.encode("agent_reasoning_raw_content", forKey: .type_); try event.encode(to: encoder)
        case .mcpToolCallBegin(let event):
            try container.encode("mcp_tool_call_begin", forKey: .type_); try event.encode(to: encoder)
        case .mcpToolCallEnd(let event):
            try container.encode("mcp_tool_call_end", forKey: .type_); try event.encode(to: encoder)
        case .webSearchBegin(let event):
            try container.encode("web_search_begin", forKey: .type_); try event.encode(to: encoder)
        case .webSearchEnd(let event):
            try container.encode("web_search_end", forKey: .type_); try event.encode(to: encoder)
        case .imageGenerationBegin(let event):
            try container.encode("image_generation_begin", forKey: .type_); try event.encode(to: encoder)
        case .imageGenerationEnd(let event):
            try container.encode("image_generation_end", forKey: .type_); try event.encode(to: encoder)
        case .execCommandBegin(let event):
            try container.encode("exec_command_begin", forKey: .type_); try event.encode(to: encoder)
        case .execCommandEnd(let event):
            try container.encode("exec_command_end", forKey: .type_); try event.encode(to: encoder)
        case .viewImageToolCall(let event):
            try container.encode("view_image_tool_call", forKey: .type_); try event.encode(to: encoder)
        case .execApprovalRequest(let event):
            try container.encode("exec_approval_request", forKey: .type_); try event.encode(to: encoder)
        case .applyPatchApprovalRequest(let event):
            try container.encode("apply_patch_approval_request", forKey: .type_); try event.encode(to: encoder)
        case .guardianAssessment(let event):
            try container.encode("guardian_assessment", forKey: .type_); try event.encode(to: encoder)
        case .elicitationRequest(let event):
            try container.encode("elicitation_request", forKey: .type_); try event.encode(to: encoder)
        case .dynamicToolCallRequest(let event):
            try container.encode("dynamic_tool_call_request", forKey: .type_); try event.encode(to: encoder)
        case .dynamicToolCallResponse(let event):
            try container.encode("dynamic_tool_call_response", forKey: .type_); try event.encode(to: encoder)
        case .patchApplyBegin(let event):
            try container.encode("patch_apply_begin", forKey: .type_); try event.encode(to: encoder)
        case .patchApplyEnd(let event):
            try container.encode("patch_apply_end", forKey: .type_); try event.encode(to: encoder)
        case .enteredReviewMode(let event):
            try container.encode("entered_review_mode", forKey: .type_); try event.encode(to: encoder)
        case .exitedReviewMode(let event):
            try container.encode("exited_review_mode", forKey: .type_); try event.encode(to: encoder)
        case .itemStarted(let event):
            try container.encode("item_started", forKey: .type_); try event.encode(to: encoder)
        case .itemCompleted(let event):
            try container.encode("item_completed", forKey: .type_); try event.encode(to: encoder)
        case .agentMessageContentDelta(let event):
            try container.encode("agent_message_content_delta", forKey: .type_); try event.encode(to: encoder)
        case .reasoningContentDelta(let event):
            try container.encode("reasoning_content_delta", forKey: .type_); try event.encode(to: encoder)
        case .reasoningRawContentDelta(let event):
            try container.encode("reasoning_raw_content_delta", forKey: .type_); try event.encode(to: encoder)
        case .collabAgentSpawnBegin(let event):
            try container.encode("collab_agent_spawn_begin", forKey: .type_); try event.encode(to: encoder)
        case .collabAgentSpawnEnd(let event):
            try container.encode("collab_agent_spawn_end", forKey: .type_); try event.encode(to: encoder)
        case .collabAgentInteractionBegin(let event):
            try container.encode("collab_agent_interaction_begin", forKey: .type_); try event.encode(to: encoder)
        case .collabAgentInteractionEnd(let event):
            try container.encode("collab_agent_interaction_end", forKey: .type_); try event.encode(to: encoder)
        case .collabWaitingBegin(let event):
            try container.encode("collab_waiting_begin", forKey: .type_); try event.encode(to: encoder)
        case .collabWaitingEnd(let event):
            try container.encode("collab_waiting_end", forKey: .type_); try event.encode(to: encoder)
        case .collabCloseBegin(let event):
            try container.encode("collab_close_begin", forKey: .type_); try event.encode(to: encoder)
        case .collabCloseEnd(let event):
            try container.encode("collab_close_end", forKey: .type_); try event.encode(to: encoder)
        case .collabResumeBegin(let event):
            try container.encode("collab_resume_begin", forKey: .type_); try event.encode(to: encoder)
        case .collabResumeEnd(let event):
            try container.encode("collab_resume_end", forKey: .type_); try event.encode(to: encoder)
        case .subAgentActivity(let event):
            try container.encode("sub_agent_activity", forKey: .type_); try event.encode(to: encoder)
        }
    }
}

// MARK: - Command / MCP / patch / collab event payloads

public struct ExecCommandBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var pluginId: String?
    public var scriptPath: String?
    public var processId: String?
    public var turnId: String
    public var startedAtMs: Int64
    public var command: [String]
    public var cwd: PathUri
    public var parsedCmd: [ParsedCommand]
    public var source: ExecCommandSource
    public var interactionInput: String?

    enum CodingKeys: String, CodingKey {
        case command, cwd, source
        case callId = "call_id"
        case pluginId = "plugin_id"
        case scriptPath = "script_path"
        case processId = "process_id"
        case turnId = "turn_id"
        case startedAtMs = "started_at_ms"
        case parsedCmd = "parsed_cmd"
        case interactionInput = "interaction_input"
    }

    public init(
        callId: String, pluginId: String? = nil, scriptPath: String? = nil,
        processId: String? = nil, turnId: String, startedAtMs: Int64 = 0,
        command: [String], cwd: PathUri, parsedCmd: [ParsedCommand],
        source: ExecCommandSource = .agent, interactionInput: String? = nil
    ) {
        self.callId = callId; self.pluginId = pluginId; self.scriptPath = scriptPath
        self.processId = processId; self.turnId = turnId; self.startedAtMs = startedAtMs
        self.command = command; self.cwd = cwd; self.parsedCmd = parsedCmd
        self.source = source; self.interactionInput = interactionInput
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        scriptPath = try container.decodeIfPresent(String.self, forKey: .scriptPath)
        processId = try container.decodeIfPresent(String.self, forKey: .processId)
        turnId = try container.decode(String.self, forKey: .turnId)
        startedAtMs = try container.decodeIfPresent(Int64.self, forKey: .startedAtMs) ?? 0
        command = try container.decode([String].self, forKey: .command)
        cwd = try container.decode(PathUri.self, forKey: .cwd)
        parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
        source = try container.decodeIfPresent(ExecCommandSource.self, forKey: .source) ?? .agent
        interactionInput = try container.decodeIfPresent(String.self, forKey: .interactionInput)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(scriptPath, forKey: .scriptPath)
        try container.encodeIfPresent(processId, forKey: .processId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(parsedCmd, forKey: .parsedCmd)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(interactionInput, forKey: .interactionInput)
    }
}

public struct ExecCommandEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var pluginId: String?
    public var scriptPath: String?
    public var processId: String?
    public var turnId: String
    public var completedAtMs: Int64
    public var command: [String]
    public var cwd: PathUri
    public var parsedCmd: [ParsedCommand]
    public var source: ExecCommandSource
    public var interactionInput: String?
    public var stdout: String
    public var stderr: String
    public var aggregatedOutput: String
    public var exitCode: Int32
    public var duration: Duration
    public var formattedOutput: String
    public var status: ExecCommandStatus

    enum CodingKeys: String, CodingKey {
        case command, cwd, source, stdout, stderr, duration, status
        case callId = "call_id"
        case pluginId = "plugin_id"
        case scriptPath = "script_path"
        case processId = "process_id"
        case turnId = "turn_id"
        case completedAtMs = "completed_at_ms"
        case parsedCmd = "parsed_cmd"
        case interactionInput = "interaction_input"
        case aggregatedOutput = "aggregated_output"
        case exitCode = "exit_code"
        case formattedOutput = "formatted_output"
    }

    public init(
        callId: String, pluginId: String? = nil, scriptPath: String? = nil,
        processId: String? = nil, turnId: String, completedAtMs: Int64 = 0,
        command: [String], cwd: PathUri, parsedCmd: [ParsedCommand],
        source: ExecCommandSource = .agent, interactionInput: String? = nil,
        stdout: String, stderr: String, aggregatedOutput: String = "",
        exitCode: Int32, duration: Duration = .zero, formattedOutput: String,
        status: ExecCommandStatus
    ) {
        self.callId = callId; self.pluginId = pluginId; self.scriptPath = scriptPath
        self.processId = processId; self.turnId = turnId; self.completedAtMs = completedAtMs
        self.command = command; self.cwd = cwd; self.parsedCmd = parsedCmd
        self.source = source; self.interactionInput = interactionInput
        self.stdout = stdout; self.stderr = stderr; self.aggregatedOutput = aggregatedOutput
        self.exitCode = exitCode; self.duration = duration
        self.formattedOutput = formattedOutput; self.status = status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        scriptPath = try container.decodeIfPresent(String.self, forKey: .scriptPath)
        processId = try container.decodeIfPresent(String.self, forKey: .processId)
        turnId = try container.decode(String.self, forKey: .turnId)
        completedAtMs = try container.decodeIfPresent(Int64.self, forKey: .completedAtMs) ?? 0
        command = try container.decode([String].self, forKey: .command)
        cwd = try container.decode(PathUri.self, forKey: .cwd)
        parsedCmd = try container.decode([ParsedCommand].self, forKey: .parsedCmd)
        source = try container.decodeIfPresent(ExecCommandSource.self, forKey: .source) ?? .agent
        interactionInput = try container.decodeIfPresent(String.self, forKey: .interactionInput)
        stdout = try container.decode(String.self, forKey: .stdout)
        stderr = try container.decode(String.self, forKey: .stderr)
        aggregatedOutput = try container.decodeIfPresent(String.self, forKey: .aggregatedOutput) ?? ""
        exitCode = try container.decode(Int32.self, forKey: .exitCode)
        duration = try container.decodeIfPresent(SerdeDuration.self, forKey: .duration)?.duration ?? .zero
        formattedOutput = try container.decode(String.self, forKey: .formattedOutput)
        status = try container.decode(ExecCommandStatus.self, forKey: .status)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(scriptPath, forKey: .scriptPath)
        try container.encodeIfPresent(processId, forKey: .processId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(completedAtMs, forKey: .completedAtMs)
        try container.encode(command, forKey: .command)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(parsedCmd, forKey: .parsedCmd)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(interactionInput, forKey: .interactionInput)
        try container.encode(stdout, forKey: .stdout)
        try container.encode(stderr, forKey: .stderr)
        try container.encode(aggregatedOutput, forKey: .aggregatedOutput)
        try container.encode(exitCode, forKey: .exitCode)
        try container.encode(SerdeDuration(duration), forKey: .duration)
        try container.encode(formattedOutput, forKey: .formattedOutput)
        try container.encode(status, forKey: .status)
    }
}

public struct McpToolCallBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var invocation: McpInvocation
    public var connectorId: String?
    public var mcpAppResourceUri: String?
    public var mcpAppUi: McpAppUi?
    public var linkId: String?
    public var appName: String?
    public var actionName: String?
    public var pluginId: String?
    public var readOnlyHint: Bool?

    enum CodingKeys: String, CodingKey {
        case invocation
        case callId = "call_id"
        case turnId = "turn_id"
        case connectorId = "connector_id"
        case mcpAppResourceUri = "mcp_app_resource_uri"
        case mcpAppUi = "mcp_app_ui"
        case linkId = "link_id"
        case appName = "app_name"
        case actionName = "action_name"
        case pluginId = "plugin_id"
        case readOnlyHint = "read_only_hint"
    }

    public init(
        callId: String, turnId: String = "", invocation: McpInvocation,
        connectorId: String? = nil, mcpAppResourceUri: String? = nil,
        mcpAppUi: McpAppUi? = nil, linkId: String? = nil, appName: String? = nil,
        actionName: String? = nil, pluginId: String? = nil, readOnlyHint: Bool? = nil
    ) {
        self.callId = callId; self.turnId = turnId; self.invocation = invocation
        self.connectorId = connectorId; self.mcpAppResourceUri = mcpAppResourceUri
        self.mcpAppUi = mcpAppUi; self.linkId = linkId; self.appName = appName
        self.actionName = actionName; self.pluginId = pluginId; self.readOnlyHint = readOnlyHint
    }
}

public struct McpToolCallEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var invocation: McpInvocation
    public var connectorId: String?
    public var mcpAppResourceUri: String?
    public var mcpAppUi: McpAppUi?
    public var linkId: String?
    public var appName: String?
    public var actionName: String?
    public var pluginId: String?
    public var readOnlyHint: Bool?
    public var duration: Duration
    public var result: SerdeResult<CallToolResult>

    enum CodingKeys: String, CodingKey {
        case invocation, duration, result
        case callId = "call_id"
        case turnId = "turn_id"
        case connectorId = "connector_id"
        case mcpAppResourceUri = "mcp_app_resource_uri"
        case mcpAppUi = "mcp_app_ui"
        case linkId = "link_id"
        case appName = "app_name"
        case actionName = "action_name"
        case pluginId = "plugin_id"
        case readOnlyHint = "read_only_hint"
    }

    public init(
        callId: String, turnId: String = "", invocation: McpInvocation,
        connectorId: String? = nil, mcpAppResourceUri: String? = nil,
        mcpAppUi: McpAppUi? = nil, linkId: String? = nil, appName: String? = nil,
        actionName: String? = nil, pluginId: String? = nil, readOnlyHint: Bool? = nil,
        duration: Duration, result: SerdeResult<CallToolResult>
    ) {
        self.callId = callId; self.turnId = turnId; self.invocation = invocation
        self.connectorId = connectorId; self.mcpAppResourceUri = mcpAppResourceUri
        self.mcpAppUi = mcpAppUi; self.linkId = linkId; self.appName = appName
        self.actionName = actionName; self.pluginId = pluginId; self.readOnlyHint = readOnlyHint
        self.duration = duration; self.result = result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        invocation = try container.decode(McpInvocation.self, forKey: .invocation)
        connectorId = try container.decodeIfPresent(String.self, forKey: .connectorId)
        mcpAppResourceUri = try container.decodeIfPresent(String.self, forKey: .mcpAppResourceUri)
        mcpAppUi = try container.decodeIfPresent(McpAppUi.self, forKey: .mcpAppUi)
        linkId = try container.decodeIfPresent(String.self, forKey: .linkId)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        actionName = try container.decodeIfPresent(String.self, forKey: .actionName)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
        readOnlyHint = try container.decodeIfPresent(Bool.self, forKey: .readOnlyHint)
        duration = try container.decode(SerdeDuration.self, forKey: .duration).duration
        if let nested = try? container.superDecoder(forKey: .result) {
            result = try decodeResult(CallToolResult.self, from: nested)
        } else {
            result = .failure("missing result")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encode(turnId, forKey: .turnId)
        try container.encode(invocation, forKey: .invocation)
        try container.encodeIfPresent(connectorId, forKey: .connectorId)
        try container.encodeIfPresent(mcpAppResourceUri, forKey: .mcpAppResourceUri)
        try container.encodeIfPresent(mcpAppUi, forKey: .mcpAppUi)
        try container.encodeIfPresent(linkId, forKey: .linkId)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(actionName, forKey: .actionName)
        try container.encodeIfPresent(pluginId, forKey: .pluginId)
        try container.encodeIfPresent(readOnlyHint, forKey: .readOnlyHint)
        try container.encode(SerdeDuration(duration), forKey: .duration)
        try encodeResult(result, to: container.superEncoder(forKey: .result))
    }

    public var isSuccess: Bool {
        switch result {
        case .success(let value): return value.isError != true
        case .failure: return false
        }
    }
}

public struct PatchApplyBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var autoApproved: Bool
    public var changes: [String: FileChange]

    enum CodingKeys: String, CodingKey {
        case changes
        case callId = "call_id"
        case turnId = "turn_id"
        case autoApproved = "auto_approved"
    }

    public init(callId: String, turnId: String = "", autoApproved: Bool, changes: [String: FileChange]) {
        self.callId = callId; self.turnId = turnId
        self.autoApproved = autoApproved; self.changes = changes
    }
}

public struct PatchApplyEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var stdout: String
    public var stderr: String
    public var success: Bool
    public var changes: [String: FileChange]
    public var status: PatchApplyStatus

    enum CodingKeys: String, CodingKey {
        case stdout, stderr, success, changes, status
        case callId = "call_id"
        case turnId = "turn_id"
    }

    public init(
        callId: String, turnId: String = "", stdout: String, stderr: String,
        success: Bool, changes: [String: FileChange] = [:], status: PatchApplyStatus
    ) {
        self.callId = callId; self.turnId = turnId; self.stdout = stdout
        self.stderr = stderr; self.success = success; self.changes = changes
        self.status = status
    }
}

public struct CollabAgentSpawnBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var startedAtMs: Int64
    public var senderThreadId: ThreadId
    public var prompt: String
    public var model: String
    public var reasoningEffort: ReasoningEffort

    enum CodingKeys: String, CodingKey {
        case prompt, model
        case callId = "call_id"
        case startedAtMs = "started_at_ms"
        case senderThreadId = "sender_thread_id"
        case reasoningEffort = "reasoning_effort"
    }

    public init(
        callId: String, startedAtMs: Int64 = 0, senderThreadId: ThreadId,
        prompt: String, model: String, reasoningEffort: ReasoningEffort
    ) {
        self.callId = callId; self.startedAtMs = startedAtMs
        self.senderThreadId = senderThreadId; self.prompt = prompt
        self.model = model; self.reasoningEffort = reasoningEffort
    }
}

public struct CollabAgentSpawnEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var completedAtMs: Int64
    public var senderThreadId: ThreadId
    public var newThreadId: ThreadId?
    public var newAgentNickname: String?
    public var newAgentRole: String?
    public var prompt: String
    public var model: String
    public var reasoningEffort: ReasoningEffort
    public var status: AgentStatus

    enum CodingKeys: String, CodingKey {
        case prompt, model, status
        case callId = "call_id"
        case completedAtMs = "completed_at_ms"
        case senderThreadId = "sender_thread_id"
        case newThreadId = "new_thread_id"
        case newAgentNickname = "new_agent_nickname"
        case newAgentRole = "new_agent_role"
        case reasoningEffort = "reasoning_effort"
    }

    public init(
        callId: String, completedAtMs: Int64 = 0, senderThreadId: ThreadId,
        newThreadId: ThreadId?, newAgentNickname: String?, newAgentRole: String?,
        prompt: String, model: String, reasoningEffort: ReasoningEffort, status: AgentStatus
    ) {
        self.callId = callId; self.completedAtMs = completedAtMs
        self.senderThreadId = senderThreadId; self.newThreadId = newThreadId
        self.newAgentNickname = newAgentNickname; self.newAgentRole = newAgentRole
        self.prompt = prompt; self.model = model
        self.reasoningEffort = reasoningEffort; self.status = status
    }
}

public struct CollabAgentInteractionBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var startedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadId: ThreadId
    public var prompt: String

    enum CodingKeys: String, CodingKey {
        case prompt
        case callId = "call_id"
        case startedAtMs = "started_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadId = "receiver_thread_id"
    }

    public init(
        callId: String, startedAtMs: Int64 = 0, senderThreadId: ThreadId,
        receiverThreadId: ThreadId, prompt: String
    ) {
        self.callId = callId; self.startedAtMs = startedAtMs
        self.senderThreadId = senderThreadId; self.receiverThreadId = receiverThreadId
        self.prompt = prompt
    }
}

public struct CollabAgentInteractionEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var completedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadId: ThreadId
    public var receiverAgentNickname: String?
    public var receiverAgentRole: String?
    public var prompt: String
    public var status: AgentStatus

    enum CodingKeys: String, CodingKey {
        case prompt, status
        case callId = "call_id"
        case completedAtMs = "completed_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadId = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
    }

    public init(
        callId: String, completedAtMs: Int64 = 0, senderThreadId: ThreadId,
        receiverThreadId: ThreadId, receiverAgentNickname: String?,
        receiverAgentRole: String?, prompt: String, status: AgentStatus
    ) {
        self.callId = callId; self.completedAtMs = completedAtMs
        self.senderThreadId = senderThreadId; self.receiverThreadId = receiverThreadId
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole
        self.prompt = prompt; self.status = status
    }
}

public struct CollabWaitingBeginEvent: Codable, Equatable, Sendable {
    public var startedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadIds: [ThreadId]
    public var receiverAgents: [CollabAgentRef]
    public var callId: String

    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case startedAtMs = "started_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadIds = "receiver_thread_ids"
        case receiverAgents = "receiver_agents"
    }

    public init(
        startedAtMs: Int64 = 0, senderThreadId: ThreadId, receiverThreadIds: [ThreadId],
        receiverAgents: [CollabAgentRef] = [], callId: String
    ) {
        self.startedAtMs = startedAtMs; self.senderThreadId = senderThreadId
        self.receiverThreadIds = receiverThreadIds; self.receiverAgents = receiverAgents
        self.callId = callId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encode(senderThreadId, forKey: .senderThreadId)
        try container.encode(receiverThreadIds, forKey: .receiverThreadIds)
        if !receiverAgents.isEmpty { try container.encode(receiverAgents, forKey: .receiverAgents) }
        try container.encode(callId, forKey: .callId)
    }
}

public struct CollabWaitingEndEvent: Codable, Equatable, Sendable {
    public var senderThreadId: ThreadId
    public var callId: String
    public var completedAtMs: Int64
    public var agentStatuses: [CollabAgentStatusEntry]
    public var statuses: [String: AgentStatus]

    enum CodingKeys: String, CodingKey {
        case statuses
        case senderThreadId = "sender_thread_id"
        case callId = "call_id"
        case completedAtMs = "completed_at_ms"
        case agentStatuses = "agent_statuses"
    }

    public init(
        senderThreadId: ThreadId, callId: String, completedAtMs: Int64 = 0,
        agentStatuses: [CollabAgentStatusEntry] = [], statuses: [String: AgentStatus]
    ) {
        self.senderThreadId = senderThreadId; self.callId = callId
        self.completedAtMs = completedAtMs; self.agentStatuses = agentStatuses
        self.statuses = statuses
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderThreadId, forKey: .senderThreadId)
        try container.encode(callId, forKey: .callId)
        try container.encode(completedAtMs, forKey: .completedAtMs)
        if !agentStatuses.isEmpty { try container.encode(agentStatuses, forKey: .agentStatuses) }
        try container.encode(statuses, forKey: .statuses)
    }
}

public struct CollabCloseBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var startedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadId: ThreadId

    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case startedAtMs = "started_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadId = "receiver_thread_id"
    }

    public init(
        callId: String, startedAtMs: Int64 = 0, senderThreadId: ThreadId,
        receiverThreadId: ThreadId
    ) {
        self.callId = callId; self.startedAtMs = startedAtMs
        self.senderThreadId = senderThreadId; self.receiverThreadId = receiverThreadId
    }
}

public struct CollabCloseEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var completedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadId: ThreadId
    public var receiverAgentNickname: String?
    public var receiverAgentRole: String?
    public var status: AgentStatus

    enum CodingKeys: String, CodingKey {
        case status
        case callId = "call_id"
        case completedAtMs = "completed_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadId = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
    }

    public init(
        callId: String, completedAtMs: Int64 = 0, senderThreadId: ThreadId,
        receiverThreadId: ThreadId, receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil, status: AgentStatus
    ) {
        self.callId = callId; self.completedAtMs = completedAtMs
        self.senderThreadId = senderThreadId; self.receiverThreadId = receiverThreadId
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole; self.status = status
    }
}

public struct CollabResumeBeginEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var startedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadId: ThreadId
    public var receiverAgentNickname: String?
    public var receiverAgentRole: String?

    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case startedAtMs = "started_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadId = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
    }

    public init(
        callId: String, startedAtMs: Int64 = 0, senderThreadId: ThreadId,
        receiverThreadId: ThreadId, receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil
    ) {
        self.callId = callId; self.startedAtMs = startedAtMs
        self.senderThreadId = senderThreadId; self.receiverThreadId = receiverThreadId
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole
    }
}

public struct CollabResumeEndEvent: Codable, Equatable, Sendable {
    public var callId: String
    public var completedAtMs: Int64
    public var senderThreadId: ThreadId
    public var receiverThreadId: ThreadId
    public var receiverAgentNickname: String?
    public var receiverAgentRole: String?
    public var status: AgentStatus

    enum CodingKeys: String, CodingKey {
        case status
        case callId = "call_id"
        case completedAtMs = "completed_at_ms"
        case senderThreadId = "sender_thread_id"
        case receiverThreadId = "receiver_thread_id"
        case receiverAgentNickname = "receiver_agent_nickname"
        case receiverAgentRole = "receiver_agent_role"
    }

    public init(
        callId: String, completedAtMs: Int64 = 0, senderThreadId: ThreadId,
        receiverThreadId: ThreadId, receiverAgentNickname: String? = nil,
        receiverAgentRole: String? = nil, status: AgentStatus
    ) {
        self.callId = callId; self.completedAtMs = completedAtMs
        self.senderThreadId = senderThreadId; self.receiverThreadId = receiverThreadId
        self.receiverAgentNickname = receiverAgentNickname
        self.receiverAgentRole = receiverAgentRole; self.status = status
    }
}


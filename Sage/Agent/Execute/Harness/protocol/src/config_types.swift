//
//  config_types.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/config_types.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Configuration enums and value types used throughout the harness. Upstream
//  derives `strum::Display`, `EnumIter`, and `schemars::JsonSchema` for schema
//  generation; Swift omits those (runtime JSON schema is not needed). serde
//  rename rules are mapped to CodingKeys or raw-value enums.
//
//  WildMatchPattern (EnvironmentVariablePattern) is replaced by a thin
//  fnmatch-style wrapper using `fnmatch(3)`.
//

import Foundation

// MARK: - ToolResultLogConfig

public struct ToolResultLogConfig: Codable, Equatable, Sendable {
    public var maxBytes: Int

    public init(maxBytes: Int = 2 * 1024) {
        self.maxBytes = maxBytes
    }

    enum CodingKeys: String, CodingKey {
        case maxBytes = "max_bytes"
    }
}

// MARK: - AutoCompactTokenLimitScope

public enum AutoCompactTokenLimitScope: String, Codable, Equatable, Sendable {
    case total
    case bodyAfterPrefix = "body_after_prefix"
}

// MARK: - ReasoningSummary

public enum ReasoningSummary: String, Codable, Equatable, Sendable {
    case auto
    case concise
    case detailed
    case none
}

// MARK: - Verbosity

public enum Verbosity: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
}

// MARK: - SandboxMode

/// Wire: `kebab-case`.
public enum SandboxMode: String, Codable, Equatable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

// MARK: - ProfileV2Name

/// Validated plain profile-v2 name used to select `$CODEX_HOME/<name>.config.toml`.
public struct ProfileV2Name: Equatable, Hashable, CustomStringConvertible, Sendable {
    private let value: String

    public var description: String { value }

    public init(_ value: String) throws {
        guard !value.isEmpty,
              value.utf8.allSatisfy({ $0.isASCIIAlphanumeric || $0 == UInt8(ascii: "_") || $0 == UInt8(ascii: "-") })
        else {
            throw ProfileV2NameParseError(value: value)
        }
        self.value = value
    }

    public var asStr: String { value }
}

public struct ProfileV2NameParseError: Error, Equatable, CustomStringConvertible {
    public let value: String
    public var description: String {
        "invalid --profile value `\(value)`; pass a plain name such as `work`"
    }
}

private extension UInt8 {
    var isASCIIAlphanumeric: Bool {
        (self >= 48 && self <= 57) || (self >= 65 && self <= 90) || (self >= 97 && self <= 122)
    }
}

// MARK: - ApprovalsReviewer

public enum ApprovalsReviewer: Equatable, Sendable {
    case user
    case autoReview
}

extension ApprovalsReviewer: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "user": self = .user
        case "auto_review", "guardian_subagent": self = .autoReview
        default: throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Unknown ApprovalsReviewer: \(raw)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .user: try container.encode("user")
        case .autoReview: try container.encode("auto_review")
        }
    }
}

extension ApprovalsReviewer: CustomStringConvertible {
    public var description: String {
        switch self {
        case .user: "user"
        case .autoReview: "auto_review"
        }
    }
}

// MARK: - ShellEnvironmentPolicyInherit

public enum ShellEnvironmentPolicyInherit: String, Codable, Equatable, Sendable {
    case core
    case all
    case none = "none"
}

// MARK: - ShellEnvironmentPolicyFilter

public enum ShellEnvironmentPolicyFilter: String, Codable, Equatable, Sendable {
    case include
    case exclude
}

// MARK: - EnvironmentVariablePattern (adapted)

/// Thin fnmatch-style wrapper replacing upstream's `WildMatchPattern<'*', '?'>`.
public struct EnvironmentVariablePattern: Equatable, Sendable {
    private let pattern: String
    private let caseInsensitive: Bool

    public init(_ pattern: String, caseInsensitive: Bool = false) {
        self.pattern = pattern
        self.caseInsensitive = caseInsensitive
    }

    /// Case-insensitive constructor matching upstream `new_case_insensitive`.
    public static func newCaseInsensitive(_ pattern: String) -> EnvironmentVariablePattern {
        EnvironmentVariablePattern(pattern, caseInsensitive: true)
    }

    public func matches(_ name: String) -> Bool {
        let p = caseInsensitive ? pattern.lowercased() : pattern
        let n = caseInsensitive ? name.lowercased() : name
        return fnmatchSimple(pattern: p, string: n)
    }
}

/// Minimal fnmatch supporting `*` and `?` wildcards.
private func fnmatchSimple(pattern: String, string: String) -> Bool {
    func helper(pi: String.Index, si: String.Index) -> Bool {
        var pi = pi, si = si
        while pi < pattern.endIndex {
            let pc = pattern[pi]
            if pc == "*" {
                pi = pattern.index(after: pi)
                if pi == pattern.endIndex { return true }
                while si <= string.endIndex {
                    if si < string.endIndex, helper(pi: pi, si: si) { return true }
                    if si == string.endIndex { break }
                    si = string.index(after: si)
                }
                return false
            } else if pc == "?" {
                guard si < string.endIndex else { return false }
                pi = pattern.index(after: pi)
                si = string.index(after: si)
            } else {
                guard si < string.endIndex, pattern[pi] == string[si] else { return false }
                pi = pattern.index(after: pi)
                si = string.index(after: si)
            }
        }
        return si == string.endIndex
    }
    return helper(pi: pattern.startIndex, si: string.startIndex)
}

// MARK: - ShellEnvironmentPolicy

public struct ShellEnvironmentPolicy: Equatable, Sendable {
    public var inherit: ShellEnvironmentPolicyInherit
    public var ignoreDefaultExcludes: Bool
    public var exclude: [EnvironmentVariablePattern]
    public var set: [String: String]
    public var includeOnly: [EnvironmentVariablePattern]
    public var useProfile: Bool

    public init(
        inherit: ShellEnvironmentPolicyInherit = .all,
        ignoreDefaultExcludes: Bool = true,
        exclude: [EnvironmentVariablePattern] = [],
        set: [String: String] = [:],
        includeOnly: [EnvironmentVariablePattern] = [],
        useProfile: Bool = false
    ) {
        self.inherit = inherit
        self.ignoreDefaultExcludes = ignoreDefaultExcludes
        self.exclude = exclude
        self.set = set
        self.includeOnly = includeOnly
        self.useProfile = useProfile
    }
}

// MARK: - WindowsSandboxLevel

/// Wire: `kebab-case`.
public enum WindowsSandboxLevel: String, Codable, Equatable, Sendable {
    case disabled
    case restrictedToken = "restricted-token"
    case elevated
}

// MARK: - WindowsSandboxProxySettingsMode

public enum WindowsSandboxProxySettingsMode: String, Codable, Equatable, Sendable {
    case reconcile
    case preserve
}

// MARK: - Personality

public enum Personality: String, Codable, Comparable, Equatable, Sendable {
    case none
    case friendly
    case pragmatic

    public static func < (lhs: Personality, rhs: Personality) -> Bool {
        let order: [Personality] = [.none, .friendly, .pragmatic]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

// MARK: - MultiAgentMode

public enum MultiAgentMode: Equatable, Sendable {
    case custom(String)
    case explicitRequestOnly
    case proactive
}

extension MultiAgentMode: Codable {
    private enum Wire: String, Codable {
        case none, custom, explicitRequestOnly, proactive
    }
    private enum TypeKey: String, CodingKey { case type_ = "type" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            switch str {
            case "none": self = .custom("")
            case "explicitRequestOnly": self = .explicitRequestOnly
            case "proactive": self = .proactive
            default: self = .custom(str)
            }
            return
        }
        // Fallback: try as object with { "custom": "..." }
        let keyed = try decoder.container(keyedBy: JSONCodingKey.self)
        if let val = try keyed.decodeIfPresent(String.self, forKey: JSONCodingKey(stringValue: "custom")!) {
            self = .custom(val)
        } else if keyed.contains(JSONCodingKey(stringValue: "explicitRequestOnly")!) {
            self = .explicitRequestOnly
        } else if keyed.contains(JSONCodingKey(stringValue: "proactive")!) {
            self = .proactive
        } else if keyed.contains(JSONCodingKey(stringValue: "none")!) {
            self = .custom("")
        } else {
            self = .explicitRequestOnly
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .custom(let s) where s.isEmpty:
            try container.encode("none")
        case .custom(let s):
            // Encode as { "custom": "..." }
            var keyed = encoder.container(keyedBy: JSONCodingKey.self)
            try keyed.encode(s, forKey: JSONCodingKey(stringValue: "custom")!)
        case .explicitRequestOnly:
            try container.encode("explicitRequestOnly")
        case .proactive:
            try container.encode("proactive")
        }
    }
}

// MARK: - WebSearchMode

public enum WebSearchMode: String, Codable, Equatable, Sendable {
    case disabled
    case cached
    case indexed
    case live

    /// Restricts search to the access permitted by both modes.
    public func restrictTo(_ requested: WebSearchMode) -> WebSearchMode {
        switch (self, requested) {
        case (.disabled, _), (_, .disabled): return .disabled
        case (.cached, _), (_, .cached): return .cached
        case (.indexed, _), (_, .indexed): return .indexed
        case (.live, .live): return .live
        default: return .cached
        }
    }
}

// MARK: - ToolExposureSurface

public enum ToolExposureSurface: String, Codable, Equatable, Sendable {
    case codeMode = "code_mode"
    case deferred
    case direct
}

// MARK: - WebSearch types

public enum WebSearchContextSize: String, Codable, Equatable, Sendable {
    case low, medium, high
}

public struct WebSearchLocation: Codable, Equatable, Sendable {
    public var country: String?
    public var region: String?
    public var city: String?
    public var timezone: String?

    public init(country: String? = nil, region: String? = nil, city: String? = nil, timezone: String? = nil) {
        self.country = country; self.region = region; self.city = city; self.timezone = timezone
    }

    public func merge(_ other: WebSearchLocation) -> WebSearchLocation {
        WebSearchLocation(
            country: other.country ?? country,
            region: other.region ?? region,
            city: other.city ?? city,
            timezone: other.timezone ?? timezone
        )
    }
}

public struct WebSearchToolConfig: Codable, Equatable, Sendable {
    public var contextSize: WebSearchContextSize?
    public var allowedDomains: [String]?
    public var location: WebSearchLocation?

    enum CodingKeys: String, CodingKey {
        case contextSize = "context_size"
        case allowedDomains = "allowed_domains"
        case location
    }

    public init(contextSize: WebSearchContextSize? = nil, allowedDomains: [String]? = nil, location: WebSearchLocation? = nil) {
        self.contextSize = contextSize; self.allowedDomains = allowedDomains; self.location = location
    }

    public func merge(_ other: WebSearchToolConfig) -> WebSearchToolConfig {
        WebSearchToolConfig(
            contextSize: other.contextSize ?? contextSize,
            allowedDomains: other.allowedDomains ?? allowedDomains,
            location: {
                switch (location, other.location) {
                case let (.some(l), .some(o)): return l.merge(o)
                case (.some(let l), .none): return l
                case (.none, .some(let o)): return o
                case (.none, .none): return nil
                }
            }()
        )
    }
}

public struct WebSearchFilters: Codable, Equatable, Sendable {
    public var allowedDomains: [String]?
    enum CodingKeys: String, CodingKey { case allowedDomains = "allowed_domains" }
}

public enum WebSearchUserLocationType: String, Codable, Equatable, Sendable {
    case approximate
}

public struct WebSearchUserLocation: Codable, Equatable, Sendable {
    public var type_: WebSearchUserLocationType
    public var country: String?
    public var region: String?
    public var city: String?
    public var timezone: String?

    enum CodingKeys: String, CodingKey {
        case type_ = "type"
        case country, region, city, timezone
    }

    public init(type_: WebSearchUserLocationType = .approximate, country: String? = nil, region: String? = nil, city: String? = nil, timezone: String? = nil) {
        self.type_ = type_; self.country = country; self.region = region; self.city = city; self.timezone = timezone
    }
}

public struct WebSearchConfig: Codable, Equatable, Sendable {
    public var filters: WebSearchFilters?
    public var userLocation: WebSearchUserLocation?
    public var searchContextSize: WebSearchContextSize?

    enum CodingKeys: String, CodingKey {
        case filters
        case userLocation = "user_location"
        case searchContextSize = "search_context_size"
    }
}

// MARK: - ServiceTier

public enum ServiceTier: String, Codable, Equatable, Sendable {
    case fast
    case flex

    public var requestValue: String {
        switch self {
        case .fast: "priority"
        case .flex: "flex"
        }
    }

    public static func fromRequestValue(_ value: String) -> ServiceTier? {
        switch value {
        case "fast", "priority": .fast
        case "flex": .flex
        default: nil
        }
    }
}

/// Request/config sentinel for explicit standard routing.
public let serviceTierDefaultRequestValue = "default"

// MARK: - ForcedLoginMethod

public enum ForcedLoginMethod: String, Codable, Equatable, Sendable {
    case chatgpt
    case api
}

// MARK: - TrustLevel

public enum TrustLevel: String, Codable, Equatable, Sendable {
    case trusted
    case untrusted
}

// MARK: - AltScreenMode

public enum AltScreenMode: String, Codable, Equatable, Sendable {
    case auto
    case always
    case never
}

// MARK: - ModeKind

public enum ModeKind: String, Codable, Hashable, Sendable {
    case plan
    case `default`

    public var displayName: String {
        switch self {
        case .plan: "Plan"
        case .default: "Default"
        }
    }

    public var isTuiVisible: Bool {
        switch self { case .plan, .default: true }
    }

    public var allowsRequestUserInput: Bool {
        switch self { case .plan: true; default: false }
    }
}

extension ModeKind {
    /// Accept legacy aliases: code, pair_programming, execute, custom → .default
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "plan": self = .plan
        case "default", "code", "pair_programming", "execute", "custom": self = .default
        default:
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown ModeKind: \(raw)")
        }
    }
}

public let tuiVisibleCollaborationModes: [ModeKind] = [.default, .plan]

// MARK: - CollaborationMode

public struct CollaborationMode: Codable, Equatable, Hashable, Sendable {
    public var mode: ModeKind
    public var settings: Settings

    public var model: String { settings.model }

    public var reasoningEffort: ReasoningEffort? { settings.reasoningEffort }

    public func withUpdates(
        model: String? = nil,
        effort: ReasoningEffort?? = nil,
        developerInstructions: String?? = nil
    ) -> CollaborationMode {
        CollaborationMode(
            mode: mode,
            settings: Settings(
                model: model ?? settings.model,
                reasoningEffort: effort ?? settings.reasoningEffort,
                developerInstructions: developerInstructions ?? settings.developerInstructions
            )
        )
    }

    public func applyMask(_ mask: CollaborationModeMask) -> CollaborationMode {
        CollaborationMode(
            mode: mask.mode ?? mode,
            settings: Settings(
                model: mask.model ?? settings.model,
                reasoningEffort: mask.reasoningEffort ?? settings.reasoningEffort,
                developerInstructions: mask.developerInstructions ?? settings.developerInstructions
            )
        )
    }
}

public struct Settings: Codable, Equatable, Hashable, Sendable {
    public var model: String
    public var reasoningEffort: ReasoningEffort?
    public var developerInstructions: String?

    enum CodingKeys: String, CodingKey {
        case model
        case reasoningEffort = "reasoning_effort"
        case developerInstructions = "developer_instructions"
    }

    public init(model: String, reasoningEffort: ReasoningEffort? = nil, developerInstructions: String? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.developerInstructions = developerInstructions
    }
}

public struct CollaborationModeMask: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var mode: ModeKind?
    public var model: String?
    public var reasoningEffort: ReasoningEffort??
    public var developerInstructions: String??

    enum CodingKeys: String, CodingKey {
        case name, mode, model
        case reasoningEffort = "reasoning_effort"
        case developerInstructions = "developer_instructions"
    }
}

// MARK: - ReasoningEffort

/// See https://platform.openai.com/docs/guides/reasoning
public enum ReasoningEffort: Hashable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xHigh
    case max
    case ultra
    case persistent
    case custom(String)

    public var asStr: String {
        switch self {
        case .none: "none"
        case .minimal: "minimal"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xHigh: "xhigh"
        case .max: "max"
        case .ultra: "ultra"
        case .persistent: "persistent"
        case .custom(let s): s
        }
    }

    public init?(string: String) {
        switch string {
        case "none": self = .none
        case "minimal": self = .minimal
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "xhigh": self = .xHigh
        case "max": self = .max
        case "ultra": self = .ultra
        case "persistent": self = .persistent
        case "": return nil
        default: self = .custom(string)
        }
    }
}

extension ReasoningEffort: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        guard let value = ReasoningEffort(string: str) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "reasoning_effort must not be empty")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(asStr)
    }
}

extension ReasoningEffort: CustomStringConvertible {
    public var description: String { asStr }
}

extension ReasoningEffort: Equatable {}

// MARK: - ModelProviderAuthInfo (adapted: cwd uses String, not AbsolutePathBuf)

public struct ModelProviderAuthInfo: Codable, Equatable, Sendable {
    public var command: String
    public var args: [String]
    public var timeoutMs: UInt64
    public var refreshIntervalMs: UInt64
    public var cwd: String

    enum CodingKeys: String, CodingKey {
        case command, args
        case timeoutMs = "timeout_ms"
        case refreshIntervalMs = "refresh_interval_ms"
        case cwd
    }

    public init(
        command: String,
        args: [String] = [],
        timeoutMs: UInt64 = 5_000,
        refreshIntervalMs: UInt64 = 300_000,
        cwd: String = "."
    ) {
        self.command = command
        self.args = args
        self.timeoutMs = timeoutMs
        self.refreshIntervalMs = refreshIntervalMs
        self.cwd = cwd
    }

    public var timeout: Duration {
        .milliseconds(Int64(timeoutMs))
    }

    public var refreshInterval: Duration? {
        refreshIntervalMs > 0 ? .milliseconds(Int64(refreshIntervalMs)) : nil
    }
}

// JSONCodingKey is defined in json_value.swift

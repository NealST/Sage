//
//  auth.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/auth.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Authentication modes and plan classification for OpenAI-backed providers.
//

import Foundation

// MARK: - AuthMode

public enum AuthMode: String, Codable, Equatable, Sendable, CustomStringConvertible {
    case apiKey = "apikey"
    case chatgpt = "chatgpt"
    case chatgptAuthTokens = "chatgptAuthTokens"
    case headers = "headers"
    case agentIdentity = "agentIdentity"
    case personalAccessToken = "personalAccessToken"
    case bedrockApiKey = "bedrockApiKey"
    case bedrockAccessKeys = "bedrockAccessKeys"

    public var description: String { rawValue }

    public var hasChatgptAccount: Bool {
        switch self {
        case .chatgpt, .chatgptAuthTokens, .personalAccessToken: true
        case .apiKey, .headers, .agentIdentity, .bedrockApiKey, .bedrockAccessKeys: false
        }
    }

    public var usesCodexBackend: Bool {
        switch self {
        case .chatgpt, .chatgptAuthTokens, .headers, .agentIdentity, .personalAccessToken: true
        case .apiKey, .bedrockApiKey, .bedrockAccessKeys: false
        }
    }
}

// MARK: - KnownPlan

public enum KnownPlan: String, Codable, Equatable, Sendable {
    case free
    case go
    case plus
    case pro
    case proLite = "prolite"
    case proMax = "promax"
    case team
    case selfServeBusinessProLite = "self_serve_business_prolite"
    case selfServeBusinessUsageBased = "self_serve_business_usage_based"
    case business
    case ent26
    case enterpriseCbpAutomation = "enterprise_cbp_automation"
    case enterpriseCbpUsageBased = "enterprise_cbp_usage_based"
    case enterprise
    case edu
    case eduPlus = "edu_plus"
    case eduPro = "edu_pro"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "hc": self = .enterprise
        case "education": self = .edu
        default:
            guard let known = KnownPlan(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown plan: \(raw)")
            }
            self = known
        }
    }

    public var displayName: String {
        switch self {
        case .free: "Free"
        case .go: "Go"
        case .plus: "Plus"
        case .pro: "Pro (More)"
        case .proLite: "Pro"
        case .proMax: "Pro (Max)"
        case .team: "Team"
        case .selfServeBusinessProLite: "Self Serve Business ProLite"
        case .selfServeBusinessUsageBased: "Self Serve Business Usage Based"
        case .business: "Business"
        case .ent26: "Enterprise"
        case .enterpriseCbpAutomation: "Enterprise (Automation)"
        case .enterpriseCbpUsageBased: "Enterprise CBP Usage Based"
        case .enterprise: "Enterprise"
        case .edu: "Edu"
        case .eduPlus: "Edu Plus"
        case .eduPro: "Edu Pro"
        }
    }

    public var isWorkspaceAccount: Bool {
        switch self {
        case .team, .selfServeBusinessProLite, .selfServeBusinessUsageBased,
             .business, .ent26, .enterpriseCbpAutomation, .enterpriseCbpUsageBased,
             .enterprise, .edu, .eduPlus, .eduPro:
            true
        default:
            false
        }
    }
}

// MARK: - AuthPlanType (upstream: auth::PlanType)

public enum AuthPlanType: Equatable, Sendable {
    case known(KnownPlan)
    case unknown(String)

    public static func fromRawValue(_ raw: String) -> AuthPlanType {
        let lower = raw.lowercased()
        switch lower {
        case "free": return .known(.free)
        case "go": return .known(.go)
        case "plus": return .known(.plus)
        case "pro": return .known(.pro)
        case "prolite": return .known(.proLite)
        case "promax": return .known(.proMax)
        case "team": return .known(.team)
        case "self_serve_business_prolite": return .known(.selfServeBusinessProLite)
        case "self_serve_business_usage_based": return .known(.selfServeBusinessUsageBased)
        case "business": return .known(.business)
        case "ent26": return .known(.ent26)
        case "enterprise_cbp_automation": return .known(.enterpriseCbpAutomation)
        case "enterprise_cbp_usage_based": return .known(.enterpriseCbpUsageBased)
        case "enterprise", "hc": return .known(.enterprise)
        case "education", "edu": return .known(.edu)
        case "edu_plus": return .known(.eduPlus)
        case "edu_pro": return .known(.eduPro)
        default: return .unknown(raw)
        }
    }
}

extension AuthPlanType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let known = try? KnownPlan(from: decoder) {
            self = .known(known)
        } else {
            self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .known(let plan): try container.encode(plan)
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

// MARK: - RefreshTokenFailedReason

public enum RefreshTokenFailedReason: Equatable, Sendable {
    case expired
    case exhausted
    case revoked
    case other
}

// MARK: - RefreshTokenFailedError

public struct RefreshTokenFailedError: Error, Equatable, CustomStringConvertible {
    public var reason: RefreshTokenFailedReason
    public var message: String

    public init(reason: RefreshTokenFailedReason, message: String) {
        self.reason = reason; self.message = message
    }

    public var description: String { message }
}

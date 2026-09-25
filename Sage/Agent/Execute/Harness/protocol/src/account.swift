//
//  account.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/account.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Account types and plan family helpers.
//

import Foundation

// MARK: - AccountPlanType (upstream: account::PlanType)

/// Account-facing plan type. Wire names use `lowercase` with a few explicit overrides.
public enum AccountPlanType: String, Codable, Equatable, Sendable {
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
    case unknown

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AccountPlanType(rawValue: raw) ?? .unknown
    }

    public var isTeamLike: Bool {
        switch self {
        case .team, .selfServeBusinessProLite, .selfServeBusinessUsageBased: true
        default: false
        }
    }

    public var isBusinessLike: Bool {
        switch self {
        case .business, .ent26, .enterpriseCbpAutomation, .enterpriseCbpUsageBased: true
        default: false
        }
    }

    public var isEducationLike: Bool {
        switch self {
        case .edu, .eduPlus, .eduPro: true
        default: false
        }
    }

    public var isWorkspaceAccount: Bool {
        isTeamLike || isBusinessLike || isEducationLike || self == .enterprise
    }
}

// MARK: - AuthPlanType → AccountPlanType

extension AccountPlanType {
    public init(from authPlan: AuthPlanType) {
        switch authPlan {
        case .known(let plan): self = AccountPlanType(from: plan)
        case .unknown: self = .unknown
        }
    }

    public init(from plan: KnownPlan) {
        switch plan {
        case .free: self = .free
        case .go: self = .go
        case .plus: self = .plus
        case .pro: self = .pro
        case .proLite: self = .proLite
        case .proMax: self = .proMax
        case .team: self = .team
        case .selfServeBusinessProLite: self = .selfServeBusinessProLite
        case .selfServeBusinessUsageBased: self = .selfServeBusinessUsageBased
        case .business: self = .business
        case .ent26: self = .ent26
        case .enterpriseCbpAutomation: self = .enterpriseCbpAutomation
        case .enterpriseCbpUsageBased: self = .enterpriseCbpUsageBased
        case .enterprise: self = .enterprise
        case .edu: self = .edu
        case .eduPlus: self = .eduPlus
        case .eduPro: self = .eduPro
        }
    }
}

// MARK: - ProviderAccount

public enum ProviderAccount: Equatable, Sendable {
    case apiKey
    case chatgpt(email: String?, planType: AccountPlanType)
    case amazonBedrock(usesCodexManagedCredentials: Bool)
}

//
//  network_policy_decision.swift
//  Sage
//
//  Port of codex-rs/core/src/network_policy_decision.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexExecPolicy
import CodexProtocol
import CodexSandboxing

struct ExecPolicyNetworkRuleAmendment: Equatable, Sendable {
    var protocol_: NetworkRuleProtocol
    var decision: Decision
    var justification: String
}

func parseNetworkPolicyDecision(_ value: String) -> NetworkPolicyDecision? {
    switch value {
    case "deny": return .deny
    case "ask": return .ask
    default: return nil
    }
}

func networkApprovalContextFromPayload(
    _ payload: NetworkPolicyDecisionPayload
) -> NetworkApprovalContext? {
    if !payload.isAskFromDecider { return nil }
    guard let protocol_ = payload.protocol_ else { return nil }
    guard let host = payload.host?.trimmingCharacters(in: .whitespacesAndNewlines),
          !host.isEmpty else {
        return nil
    }
    return NetworkApprovalContext(host: host, protocol_: protocol_)
}

func deniedNetworkPolicyMessage(_ blocked: BlockedRequest) -> String? {
    let decision = blocked.decision.flatMap(parseNetworkPolicyDecision)
    if decision != .deny { return nil }
    let host = blocked.host.trimmingCharacters(in: .whitespacesAndNewlines)
    if host.isEmpty {
        return "Network access was blocked by policy."
    }
    let detail: String
    switch blocked.reason {
    case "denied":
        detail = "domain is explicitly denied by policy and cannot be approved from this prompt"
    case "not_allowed":
        detail = "domain is not on the allowlist for the current sandbox mode"
    case "not_allowed_local":
        detail = "local/private network addresses are blocked by the sandbox policy"
    case "method_not_allowed":
        detail = "request method is blocked by the current network mode"
    case "proxy_disabled":
        detail = "network proxy is disabled"
    default:
        detail = "request is blocked by network policy"
    }
    return "Network access to \"\(host)\" was blocked: \(detail)."
}

func execpolicyNetworkRuleAmendment(
    _ amendment: NetworkPolicyAmendment,
    networkApprovalContext: NetworkApprovalContext,
    host: String
) -> ExecPolicyNetworkRuleAmendment {
    let protocol_: NetworkRuleProtocol
    switch networkApprovalContext.protocol_ {
    case .http: protocol_ = .http
    case .https: protocol_ = .https
    case .socks5Tcp: protocol_ = .socks5Tcp
    case .socks5Udp: protocol_ = .socks5Udp
    }
    let decision: Decision
    let actionVerb: String
    switch amendment.action {
    case .allow:
        decision = .allow
        actionVerb = "Allow"
    case .deny:
        decision = .forbidden
        actionVerb = "Deny"
    }
    let protocolLabel: String
    switch networkApprovalContext.protocol_ {
    case .http: protocolLabel = "http"
    case .https: protocolLabel = "https_connect"
    case .socks5Tcp: protocolLabel = "socks5_tcp"
    case .socks5Udp: protocolLabel = "socks5_udp"
    }
    return ExecPolicyNetworkRuleAmendment(
        protocol_: protocol_,
        decision: decision,
        justification: "\(actionVerb) \(protocolLabel) access to \(host)"
    )
}

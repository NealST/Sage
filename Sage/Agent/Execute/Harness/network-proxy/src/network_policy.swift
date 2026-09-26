//
//  network_policy.swift
//  CodexNetworkProxy
//
//  Port of codex-rs/network-proxy/src/network_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Type layer only. Audit observers and the proxy process wait; decision
//  helpers stay usable by Phase 4 handlers.
//

import Foundation

public enum NetworkProtocolKind: String, Equatable, Sendable {
    case http
    case httpsConnect = "https_connect"
    case socks5Tcp = "socks5_tcp"
    case socks5Udp = "socks5_udp"

    public func asPolicyProtocol() -> String { rawValue }
}

public struct NetworkPolicyAuditEvent: Equatable, Sendable {
    public var timestamp: String
    public var scope: String
    public var decision: String
    public var source: String
    public var reason: String
    public var protocolKind: NetworkProtocolKind
    public var host: String
    public var port: UInt16
    public var method: String?
    public var client: String?
    public var policyOverride: Bool
}

public enum ProxyNetworkPolicyDecision: String, Codable, Equatable, Sendable {
    case deny
    case ask

    public func asString() -> String { rawValue }
}

public enum ProxyNetworkDecisionSource: String, Codable, Equatable, Sendable {
    case baselinePolicy = "baseline_policy"
    case modeGuard = "mode_guard"
    case proxyState = "proxy_state"
    case decider

    public func asString() -> String { rawValue }
}

public struct NetworkPolicyRequest: Equatable, Sendable {
    public var protocolKind: NetworkProtocolKind
    public var host: String
    public var port: UInt16
    public var environmentId: String?
    public var clientAddr: String?
    public var method: String?
    public var command: String?
    public var execPolicyHint: String?
    public var executionId: String?

    public init(
        protocolKind: NetworkProtocolKind,
        host: String,
        port: UInt16,
        environmentId: String? = nil,
        clientAddr: String? = nil,
        method: String? = nil,
        command: String? = nil,
        execPolicyHint: String? = nil,
        executionId: String? = nil
    ) {
        self.protocolKind = protocolKind
        self.host = host
        self.port = port
        self.environmentId = environmentId
        self.clientAddr = clientAddr
        self.method = method
        self.command = command
        self.execPolicyHint = execPolicyHint
        self.executionId = executionId
    }
}

public enum NetworkDecision: Equatable, Sendable {
    case allow
    case deny(reason: String, source: ProxyNetworkDecisionSource, decision: ProxyNetworkPolicyDecision)

    public static func deny(_ reason: String) -> NetworkDecision {
        deny(reason, source: .decider)
    }

    public static func ask(_ reason: String) -> NetworkDecision {
        ask(reason, source: .decider)
    }

    public static func deny(_ reason: String, source: ProxyNetworkDecisionSource) -> NetworkDecision {
        .deny(
            reason: reason.isEmpty ? REASON_POLICY_DENIED : reason,
            source: source,
            decision: .deny
        )
    }

    public static func ask(_ reason: String, source: ProxyNetworkDecisionSource) -> NetworkDecision {
        .deny(
            reason: reason.isEmpty ? REASON_POLICY_DENIED : reason,
            source: source,
            decision: .ask
        )
    }
}

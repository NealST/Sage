//
//  network_policy.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/network_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Wire payload for a network-policy decision. Upstream depends on
//  `codex-network-proxy` (`NetworkPolicyDecision` / `NetworkDecisionSource`);
//  those types are inlined here because the local proxy process is
//  `excluded` (plan §2.3). Keep the camelCase wire keys.
//

import Foundation

public enum NetworkPolicyDecision: String, Codable, Equatable, Sendable {
    case allow
    case deny
    case ask
}

public enum NetworkDecisionSource: String, Codable, Equatable, Sendable {
    case decider
    case cache
    case policy
    case user
}

public struct NetworkPolicyDecisionPayload: Codable, Equatable, Sendable {
    public var decision: NetworkPolicyDecision
    public var source: NetworkDecisionSource
    public var protocol_: NetworkApprovalProtocol?
    public var host: String?
    public var reason: String?
    public var port: UInt16?

    enum CodingKeys: String, CodingKey {
        case decision, source, host, reason, port
        case protocol_ = "protocol"
    }

    public init(
        decision: NetworkPolicyDecision,
        source: NetworkDecisionSource,
        protocol_: NetworkApprovalProtocol? = nil,
        host: String? = nil,
        reason: String? = nil,
        port: UInt16? = nil
    ) {
        self.decision = decision
        self.source = source
        self.protocol_ = protocol_
        self.host = host
        self.reason = reason
        self.port = port
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decision = try container.decode(NetworkPolicyDecision.self, forKey: .decision)
        source = try container.decode(NetworkDecisionSource.self, forKey: .source)
        protocol_ = try container.decodeIfPresent(NetworkApprovalProtocol.self, forKey: .protocol_)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port)
    }

    public var isAskFromDecider: Bool {
        decision == .ask && source == .decider
    }
}

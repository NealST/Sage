//
//  network_proxy_types.swift
//  CodexSandboxing
//
//  Port of the network-proxy types referenced by sandboxing (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The local proxy process is excluded (plan §2.3). These are the type-layer
//  fields seatbelt / violation / manager need so Phase 3 can compile without
//  the Phase 4 network-proxy crate.
//

import Foundation

public enum NetworkMode: String, Codable, Equatable, Sendable {
    case limited
    case full
}

public struct BlockedRequestArgs: Equatable, Sendable {
    public var host: String
    public var reason: String
    public var client: String?
    public var method: String?
    public var mode: NetworkMode?
    public var protocol_: String
    public var decision: String?
    public var source: String?
    public var port: UInt16?
    public var timestamp: Int64

    public init(
        host: String,
        reason: String,
        client: String? = nil,
        method: String? = nil,
        mode: NetworkMode? = nil,
        protocol_: String,
        decision: String? = nil,
        source: String? = nil,
        port: UInt16? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970)
    ) {
        self.host = host
        self.reason = reason
        self.client = client
        self.method = method
        self.mode = mode
        self.protocol_ = protocol_
        self.decision = decision
        self.source = source
        self.port = port
        self.timestamp = timestamp
    }
}

public struct BlockedRequest: Equatable, Sendable {
    public var host: String
    public var reason: String
    public var client: String?
    public var method: String?
    public var mode: NetworkMode?
    public var protocol_: String
    public var decision: String?
    public var source: String?
    public var port: UInt16?
    public var timestamp: Int64

    public init(_ args: BlockedRequestArgs) {
        host = args.host
        reason = args.reason
        client = args.client
        method = args.method
        mode = args.mode
        protocol_ = args.protocol_
        decision = args.decision
        source = args.source
        port = args.port
        timestamp = args.timestamp
    }

    public static func new(_ args: BlockedRequestArgs) -> BlockedRequest {
        BlockedRequest(args)
    }
}

public let PROXY_URL_ENV_KEYS = [
    "ALL_PROXY", "all_proxy",
    "HTTP_PROXY", "http_proxy",
    "HTTPS_PROXY", "https_proxy",
]

public func hasProxyURLEnvVars(_ env: [String: String]) -> Bool {
    PROXY_URL_ENV_KEYS.contains { key in
        env[key].map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
    }
}

public func proxyURLEnvValue(_ env: [String: String], key: String) -> String? {
    env[key]
}

public struct ManagedNetworkSandboxContext: Equatable, Sendable {
    public var loopbackPorts: [UInt16]
    public var allowLocalBinding: Bool
    public var allowUnixSockets: [String]
    public var dangerouslyAllowAllUnixSockets: Bool

    public init(
        loopbackPorts: [UInt16] = [],
        allowLocalBinding: Bool = false,
        allowUnixSockets: [String] = [],
        dangerouslyAllowAllUnixSockets: Bool = false
    ) {
        self.loopbackPorts = loopbackPorts
        self.allowLocalBinding = allowLocalBinding
        self.allowUnixSockets = allowUnixSockets
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
    }
}

public struct NetworkProxy: Equatable, Sendable {
    public var allowUnixSockets: [String]
    public var dangerouslyAllowAllUnixSockets: Bool
    public var allowLocalBinding: Bool
    public var environmentEnv: [String: String]

    public init(
        allowUnixSockets: [String] = [],
        dangerouslyAllowAllUnixSockets: Bool = false,
        allowLocalBinding: Bool = false,
        environmentEnv: [String: String] = [:]
    ) {
        self.allowUnixSockets = allowUnixSockets
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.allowLocalBinding = allowLocalBinding
        self.environmentEnv = environmentEnv
    }

    public func allowUnixSocketsValue() -> [String] { allowUnixSockets }
    public func dangerouslyAllowAllUnixSocketsValue() -> Bool { dangerouslyAllowAllUnixSockets }
    public func allowLocalBindingValue() -> Bool { allowLocalBinding }

    public func applyToEnvForOptionalEnvironment(
        _ env: inout [String: String],
        environmentId: String?
    ) throws {
        _ = environmentId
        for (key, value) in environmentEnv {
            env[key] = value
        }
    }
}

public func sharedDaemonSocketDirectory() throws -> String {
    let temporaryRoot = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path
    let uid = geteuid()
    return (temporaryRoot as NSString).appendingPathComponent("codex-daemon-\(uid)")
}

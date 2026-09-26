//
//  config.swift
//  CodexNetworkProxy
//
//  Port of codex-rs/network-proxy/src/config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Type layer only. Credential-broker process wiring and MITM hooks are
//  omitted (plan §2.3).
//

import Foundation

public enum NetworkDomainPermission: String, Codable, Equatable, Sendable, Comparable {
    case none
    case allow
    case deny

    public static func < (lhs: NetworkDomainPermission, rhs: NetworkDomainPermission) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .none: return 0
        case .allow: return 1
        case .deny: return 2
        }
    }
}

public struct NetworkDomainPermissionEntry: Equatable, Sendable {
    public var pattern: String
    public var permission: NetworkDomainPermission

    public init(pattern: String, permission: NetworkDomainPermission) {
        self.pattern = pattern
        self.permission = permission
    }
}

public struct NetworkDomainPermissions: Equatable, Sendable {
    public var entries: [NetworkDomainPermissionEntry]

    public init(entries: [NetworkDomainPermissionEntry] = []) {
        self.entries = entries
    }

    public func effectiveEntries() -> [NetworkDomainPermissionEntry] {
        var order: [String] = []
        var effective: [String: NetworkDomainPermission] = [:]
        for entry in entries {
            if effective[entry.pattern] == nil {
                order.append(entry.pattern)
            }
            let current = effective[entry.pattern] ?? entry.permission
            effective[entry.pattern] = max(current, entry.permission)
        }
        return order.compactMap { pattern in
            effective[pattern].map { NetworkDomainPermissionEntry(pattern: pattern, permission: $0) }
        }
    }
}

public enum NetworkUnixSocketPermission: String, Codable, Equatable, Sendable {
    case allow
    case deny
}

public struct NetworkUnixSocketPermissions: Equatable, Sendable {
    public var entries: [String: NetworkUnixSocketPermission]

    public init(entries: [String: NetworkUnixSocketPermission] = [:]) {
        self.entries = entries
    }
}

public struct NetworkMitmCaConfig: Equatable, Sendable {
    public var certificateFile: String
    public var privateKeyFile: String
}

public enum NetworkMode: String, Codable, Equatable, Sendable {
    case limited
    case full

    public static let `default`: NetworkMode = .full

    public func allowsMethod(_ method: String) -> Bool {
        switch self {
        case .full: return true
        case .limited: return ["GET", "HEAD", "OPTIONS"].contains(method)
        }
    }
}

public struct NetworkProxyConfig: Equatable, Sendable {
    public var enabled: Bool
    public var proxyURL: String
    public var enableSocks5: Bool
    public var socksURL: String
    public var enableSocks5UDP: Bool
    public var allowUpstreamProxy: Bool
    public var dangerouslyAllowNonLoopbackProxy: Bool
    public var dangerouslyAllowAllUnixSockets: Bool?
    public var mode: NetworkMode
    public var domains: NetworkDomainPermissions?
    public var unixSockets: NetworkUnixSocketPermissions?
    public var allowLocalBinding: Bool?
    public var mitm: Bool
    public var mitmCa: NetworkMitmCaConfig?
    public var credentialBroker: Bool

    public init(
        enabled: Bool = false,
        proxyURL: String = "http://127.0.0.1:3128",
        enableSocks5: Bool = true,
        socksURL: String = "http://127.0.0.1:8081",
        enableSocks5UDP: Bool = true,
        allowUpstreamProxy: Bool = true,
        dangerouslyAllowNonLoopbackProxy: Bool = false,
        dangerouslyAllowAllUnixSockets: Bool? = nil,
        mode: NetworkMode = .full,
        domains: NetworkDomainPermissions? = nil,
        unixSockets: NetworkUnixSocketPermissions? = nil,
        allowLocalBinding: Bool? = nil,
        mitm: Bool = false,
        mitmCa: NetworkMitmCaConfig? = nil,
        credentialBroker: Bool = false
    ) {
        self.enabled = enabled
        self.proxyURL = proxyURL
        self.enableSocks5 = enableSocks5
        self.socksURL = socksURL
        self.enableSocks5UDP = enableSocks5UDP
        self.allowUpstreamProxy = allowUpstreamProxy
        self.dangerouslyAllowNonLoopbackProxy = dangerouslyAllowNonLoopbackProxy
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.mode = mode
        self.domains = domains
        self.unixSockets = unixSockets
        self.allowLocalBinding = allowLocalBinding
        self.mitm = mitm
        self.mitmCa = mitmCa
        self.credentialBroker = credentialBroker
    }

    public func allowLocalBindingResolved() -> Bool {
        allowLocalBinding ?? false
    }

    public func allowedDomains() -> [String]? {
        domainEntries(.allow)
    }

    public func deniedDomains() -> [String]? {
        domainEntries(.deny)
    }

    public mutating func upsertDomainPermission(host: String, permission: NetworkDomainPermission) {
        var domains = self.domains ?? NetworkDomainPermissions()
        let normalized = normalizeHost(host)
        domains.entries.removeAll { normalizeHost($0.pattern) == normalized }
        domains.entries.append(NetworkDomainPermissionEntry(pattern: host, permission: permission))
        self.domains = domains.entries.isEmpty ? nil : domains
    }

    private func domainEntries(_ permission: NetworkDomainPermission) -> [String]? {
        guard let domains else { return nil }
        let entries = domains.effectiveEntries()
            .filter { $0.permission == permission }
            .map(\.pattern)
        return entries.isEmpty ? nil : entries
    }
}

//
//  environment_policy.swift
//  CodexNetworkProxy
//
//  Port of codex-rs/network-proxy/src/environment_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

public struct EnvironmentNetworkPolicy: Equatable, Sendable {
    public var domains: NetworkDomainPermissions?
    public var unixSockets: NetworkUnixSocketPermissions?
    public var allowUpstreamProxy: Bool
    public var dangerouslyAllowAllUnixSockets: Bool
    public var allowLocalBinding: Bool?
    public var managedAllowedDomainsOnly: Bool

    public init(
        domains: NetworkDomainPermissions? = nil,
        unixSockets: NetworkUnixSocketPermissions? = nil,
        allowUpstreamProxy: Bool = true,
        dangerouslyAllowAllUnixSockets: Bool = false,
        allowLocalBinding: Bool? = nil,
        managedAllowedDomainsOnly: Bool = false
    ) {
        self.domains = domains
        self.unixSockets = unixSockets
        self.allowUpstreamProxy = allowUpstreamProxy
        self.dangerouslyAllowAllUnixSockets = dangerouslyAllowAllUnixSockets
        self.allowLocalBinding = allowLocalBinding
        self.managedAllowedDomainsOnly = managedAllowedDomainsOnly
    }

    public static func from(config: NetworkProxyConfig, managedAllowedDomainsOnly: Bool) -> EnvironmentNetworkPolicy {
        EnvironmentNetworkPolicy(
            domains: config.domains,
            unixSockets: config.unixSockets,
            allowUpstreamProxy: config.allowUpstreamProxy,
            dangerouslyAllowAllUnixSockets: config.dangerouslyAllowAllUnixSockets ?? false,
            allowLocalBinding: config.allowLocalBinding,
            managedAllowedDomainsOnly: managedAllowedDomainsOnly
        )
    }

    public func apply(to config: inout NetworkProxyConfig) {
        let inheritedDenials = config.deniedDomains() ?? []
        config.domains = domains
        for domain in inheritedDenials {
            config.upsertDomainPermission(host: domain, permission: .deny)
        }
        let inheritedAllowAll = config.dangerouslyAllowAllUnixSockets ?? (config.unixSockets == nil)
        let inheritedSockets = config.unixSockets ?? NetworkUnixSocketPermissions()
        var effective = unixSockets ?? NetworkUnixSocketPermissions()
        let inheritedPermitsAll = inheritedAllowAll
            && !inheritedSockets.entries.values.contains(.deny)
        let ownerPermitsAll = dangerouslyAllowAllUnixSockets
            && !effective.entries.values.contains(.deny)
        effective.entries = effective.entries.filter { path, permission in
            permission == .deny
                || inheritedPermitsAll
                || inheritedSockets.entries[path] == .allow
        }
        for (path, permission) in inheritedSockets.entries {
            if ownerPermitsAll || permission == .deny {
                effective.entries[path] = permission
            }
        }
        config.unixSockets = effective.entries.isEmpty ? nil : effective
        config.dangerouslyAllowAllUnixSockets = inheritedPermitsAll && ownerPermitsAll
        config.allowUpstreamProxy = config.allowUpstreamProxy && allowUpstreamProxy
        switch (config.allowLocalBinding, allowLocalBinding) {
        case let (controller?, owner?):
            config.allowLocalBinding = controller && owner
        case let (controller, owner):
            config.allowLocalBinding = controller ?? owner
        }
    }
}

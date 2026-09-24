//
//  network_proxy_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/config/network_proxy_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Mac has no local proxy process. This is the same allow / deny / ask
//  decision Codex makes before a blocked request becomes an approval.
//

import Foundation

struct NetworkProxyConfig: Sendable, Equatable {
    var enabled = true
    var proxyURL = "http://127.0.0.1:3128"
    var enableSocks5 = false
    var credentialBroker = false
    var allowLocalBinding = false
    var allowedDomains: [String] = []
    var deniedDomains: [String] = []
}

struct NetworkProxyConstraints: Sendable, Equatable {
    var enabled: Bool?
    var allowlistExpansionEnabled: Bool?
    var allowedDomains: [String]?
    var deniedDomains: [String]?
}

struct NetworkProxySpec: Sendable, Equatable {
    private var baseConfig: NetworkProxyConfig
    private var requirements: NetworkProxyConstraints?
    private(set) var config: NetworkProxyConfig
    private(set) var constraints: NetworkProxyConstraints
    private(set) var hardDenyAllowlistMisses: Bool

    private init(
        baseConfig: NetworkProxyConfig,
        requirements: NetworkProxyConstraints?,
        config: NetworkProxyConfig,
        constraints: NetworkProxyConstraints,
        hardDenyAllowlistMisses: Bool
    ) {
        self.baseConfig = baseConfig
        self.requirements = requirements
        self.config = config
        self.constraints = constraints
        self.hardDenyAllowlistMisses = hardDenyAllowlistMisses
    }

    /// Seatbelt denies `network*` unless the command was granted network.
    /// Misses are not a hard deny, so the orchestrator can ask once.
    static let seatbelt = NetworkProxySpec(
        baseConfig: NetworkProxyConfig(),
        requirements: nil,
        config: NetworkProxyConfig(),
        constraints: NetworkProxyConstraints(),
        hardDenyAllowlistMisses: false
    )

    var enabled: Bool { config.enabled }

    var credentialBrokerEnabled: Bool {
        config.credentialBroker && constraints.enabled != false
    }

    var socksEnabled: Bool { config.enableSocks5 }

    func proxyHostAndPort(defaultPort: Int = 3128) -> String {
        let trimmed = config.proxyURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "socks5://", with: "")
        if trimmed.contains(":") { return trimmed }
        return "\(trimmed):\(defaultPort)"
    }

    static func from(
        config: NetworkProxyConfig,
        requirements: NetworkProxyConstraints? = nil
    ) -> NetworkProxySpec {
        let hardDeny = requirements?.allowedDomains?.isEmpty == false
            && requirements?.allowlistExpansionEnabled == false
        var resolved = config
        var constraints = NetworkProxyConstraints()
        if let requirements {
            if let allowed = requirements.allowedDomains {
                resolved.allowedDomains = allowed
            }
            if let denied = requirements.deniedDomains {
                resolved.deniedDomains = denied
            }
            if requirements.enabled == false {
                resolved.enabled = false
            }
            constraints = requirements
        }
        return NetworkProxySpec(
            baseConfig: config,
            requirements: requirements,
            config: resolved,
            constraints: constraints,
            hardDenyAllowlistMisses: hardDeny
        )
    }

    func recompute() -> NetworkProxySpec {
        Self.from(config: baseConfig, requirements: requirements)
    }

    /// Owner policy may tighten a controller allowlist. Denials always win.
    func applyingEnvironment(
        allowedDomains: [String],
        deniedDomains: [String],
        managedAllowedDomainsOnly: Bool
    ) -> NetworkProxySpec {
        var spec = self
        let fixed = spec.hardDenyAllowlistMisses || spec.constraints.allowlistExpansionEnabled == false
        spec.hardDenyAllowlistMisses = spec.hardDenyAllowlistMisses || managedAllowedDomainsOnly
        if !fixed, !spec.hardDenyAllowlistMisses {
            var allowed = Set(spec.config.allowedDomains.map(normalizeHost))
            allowed.formUnion(allowedDomains.map(normalizeHost))
            spec.config.allowedDomains = allowed.sorted()
            spec.constraints.allowlistExpansionEnabled = true
        }
        var denied = Set(spec.config.deniedDomains.map(normalizeHost))
        denied.formUnion(deniedDomains.map(normalizeHost))
        spec.config.deniedDomains = denied.sorted()
        spec.config.allowedDomains.removeAll { denied.contains(normalizeHost($0)) }
        spec.constraints.deniedDomains = spec.config.deniedDomains
        return spec
    }

    enum Decision: Equatable {
        case allow
        case deny(host: String?)
        case ask(host: String?)
    }

    /// Same ceiling Codex applies to a blocked request: deny list, then
    /// allowlist, then ask when expansion is still allowed.
    func decide(host: String?, networkAlreadyAllowed: Bool) -> Decision {
        if !enabled || networkAlreadyAllowed { return .allow }
        guard let host else {
            return hardDenyAllowlistMisses ? .deny(host: nil) : .ask(host: nil)
        }
        let normalized = Self.normalizeHost(host)
        if config.deniedDomains.map(Self.normalizeHost).contains(normalized) {
            return .deny(host: host)
        }
        let allowlist = config.allowedDomains.map(Self.normalizeHost)
        if allowlist.isEmpty {
            return .ask(host: host)
        }
        if allowlist.contains(where: { domainMatches($0, host: normalized) }) {
            return .allow
        }
        if hardDenyAllowlistMisses || constraints.allowlistExpansionEnabled == false {
            return .deny(host: host)
        }
        return .ask(host: host)
    }

    func decide(output: String, networkAlreadyAllowed: Bool) -> Decision {
        decide(host: Self.extractedHost(output), networkAlreadyAllowed: networkAlreadyAllowed)
    }

    static func extractedHost(_ output: String) -> String? {
        let pattern = #"(?:https?://|to )([A-Za-z0-9.-]+\.[A-Za-z]{2,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let hostRange = Range(match.range(at: 1), in: output)
        else { return nil }
        return String(output[hostRange])
    }

    static func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func domainMatches(_ domain: String, host: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}

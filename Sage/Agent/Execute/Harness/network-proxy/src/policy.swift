//
//  policy.swift
//  CodexNetworkProxy
//
//  Port of codex-rs/network-proxy/src/policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  globset compilation is replaced with Foundation wildcard matching. Host
//  normalization and public/private IP classification stay faithful.
//

import Foundation

public struct Host: Hashable, Sendable {
    public let value: String

    public init(parse input: String) throws {
        let normalized = normalizeHost(input)
        if normalized.isEmpty {
            throw NetworkPolicyError.hostEmpty
        }
        self.value = normalized
    }

    public func asString() -> String { value }
}

public enum NetworkPolicyError: Error, Equatable {
    case hostEmpty
    case unsupportedGlobalWildcard
}

public func isLoopbackHost(_ host: Host) -> Bool {
    let raw = unscopedIpLiteral(host.value) ?? host.value
    if raw == "localhost" { return true }
    if let ip = IPv4Address(raw) { return ip.isLoopback }
    if let ip = IPv6Address(raw) { return ip.isLoopback }
    return false
}

public func isDefaultProxyBypassHost(_ host: String) -> Bool {
    let host = normalizeHost(host)
    if let ip = IPv4Address(host) {
        return ip == IPv4Address.localhost || ip.isPrivate
    }
    if let ip = IPv6Address(host) {
        return ip == IPv6Address.localhost
    }
    return host == "localhost" || host.hasSuffix(".localhost")
}

public func isNonPublicIP(_ ip: String) -> Bool {
    if let v4 = IPv4Address(ip) { return isNonPublicIPv4(v4) }
    if let v6 = IPv6Address(ip) { return isNonPublicIPv6(v6) }
    return false
}

public func normalizeHost(_ host: String) -> String {
    let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("["), let end = trimmed.firstIndex(of: "]") {
        return normalizeDnsHostOrIPLiteral(String(trimmed[trimmed.index(after: trimmed.startIndex)..<end]))
    }
    if trimmed.utf8.filter({ $0 == UInt8(ascii: ":") }).count == 1 {
        return normalizeDnsHostOrIPLiteral(trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "")
    }
    return normalizeDnsHostOrIPLiteral(trimmed)
}

func normalizeDnsHostOrIPLiteral(_ host: String) -> String {
    let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if let ip = normalizeIPLiteral(lowered) { return ip }
    return lowered
}

func unscopedIpLiteral(_ host: String) -> String? {
    guard let index = host.firstIndex(of: "%") else { return nil }
    let ip = String(host[..<index])
    if IPv4Address(ip) != nil || IPv6Address(ip) != nil { return ip }
    return nil
}

func normalizeIPLiteral(_ host: String) -> String? {
    if IPv4Address(host) != nil || IPv6Address(host) != nil { return host }
    for delimiter in ["%25", "%"] {
        if let range = host.range(of: delimiter) {
            let ip = String(host[..<range.lowerBound])
            if IPv4Address(ip) != nil || IPv6Address(ip) != nil {
                return "\(ip)%\(host[range.upperBound...])"
            }
        }
    }
    return nil
}

func isNonPublicIPv4(_ ip: IPv4Address) -> Bool {
    ip.isLoopback
        || ip.isPrivate
        || ip.isLinkLocal
        || ip.isUnspecified
        || ip.isMulticast
        || ip.isBroadcast
        || ipv4InCIDR(ip, [0, 0, 0, 0], prefix: 8)
        || ipv4InCIDR(ip, [100, 64, 0, 0], prefix: 10)
        || ipv4InCIDR(ip, [192, 0, 0, 0], prefix: 24)
        || ipv4InCIDR(ip, [192, 0, 2, 0], prefix: 24)
        || ipv4InCIDR(ip, [198, 18, 0, 0], prefix: 15)
        || ipv4InCIDR(ip, [198, 51, 100, 0], prefix: 24)
        || ipv4InCIDR(ip, [203, 0, 113, 0], prefix: 24)
        || ipv4InCIDR(ip, [240, 0, 0, 0], prefix: 4)
}

func ipv4InCIDR(_ ip: IPv4Address, _ base: [UInt8], prefix: UInt8) -> Bool {
    let value = ip.rawValue
    let baseValue = UInt32(base[0]) << 24 | UInt32(base[1]) << 16 | UInt32(base[2]) << 8 | UInt32(base[3])
    let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
    return (value & mask) == (baseValue & mask)
}

func isNonPublicIPv6(_ ip: IPv6Address) -> Bool {
    if let v4 = ip.ipv4 { return isNonPublicIPv4(v4) || ip.isLoopback }
    return ip.isLoopback || ip.isUnspecified || ip.isMulticast || ip.isUniqueLocal || ip.isLinkLocal
}

public enum DomainPattern: Equatable, Sendable {
    case apexAndSubdomains(String)
    case subdomainsOnly(String)
    case exact(String)

    public static func parse(_ input: String) -> DomainPattern {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return .exact("") }
        if let domain = input.stripPrefix("**.") {
            return domain.isEmpty ? .exact("") : .apexAndSubdomains(domain)
        }
        if let domain = input.stripPrefix("*.") {
            return domain.isEmpty ? .exact("") : .subdomainsOnly(domain)
        }
        return .exact(input)
    }

    public func allows(_ candidate: DomainPattern) -> Bool {
        switch self {
        case .exact(let domain):
            if case .exact(let candidate) = candidate { return domainEq(candidate, domain) }
            return false
        case .subdomainsOnly(let domain):
            switch candidate {
            case .exact(let value): return isStrictSubdomain(value, of: domain)
            case .subdomainsOnly(let value): return isSubdomainOrEqual(value, of: domain)
            case .apexAndSubdomains(let value): return isStrictSubdomain(value, of: domain)
            }
        case .apexAndSubdomains(let domain):
            switch candidate {
            case .exact(let value), .subdomainsOnly(let value), .apexAndSubdomains(let value):
                return isSubdomainOrEqual(value, of: domain)
            }
        }
    }
}

func domainEq(_ lhs: String, _ rhs: String) -> Bool {
    normalizeDomain(lhs) == normalizeDomain(rhs)
}

func normalizeDomain(_ domain: String) -> String {
    domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
}

func isStrictSubdomain(_ candidate: String, of domain: String) -> Bool {
    let candidate = normalizeDomain(candidate)
    let domain = normalizeDomain(domain)
    return candidate.hasSuffix("." + domain) && candidate != domain
}

func isSubdomainOrEqual(_ candidate: String, of domain: String) -> Bool {
    let candidate = normalizeDomain(candidate)
    let domain = normalizeDomain(domain)
    return candidate == domain || candidate.hasSuffix("." + domain)
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

struct IPv4Address: Equatable {
    static let localhost = IPv4Address(rawValue: 0x7F00_0001)
    var rawValue: UInt32
    var isLoopback: Bool { (rawValue & 0xFF00_0000) == 0x7F00_0000 }
    var isPrivate: Bool {
        (rawValue & 0xFF00_0000) == 0x0A00_0000
            || (rawValue & 0xFFF0_0000) == 0xAC10_0000
            || (rawValue & 0xFFFF_0000) == 0xC0A8_0000
    }
    var isLinkLocal: Bool { (rawValue & 0xFFFF_0000) == 0xA9FE_0000 }
    var isUnspecified: Bool { rawValue == 0 }
    var isMulticast: Bool { (rawValue & 0xF000_0000) == 0xE000_0000 }
    var isBroadcast: Bool { rawValue == 0xFFFF_FFFF }

    init(rawValue: UInt32) { self.rawValue = rawValue }

    init?(_ string: String) {
        let parts = string.split(separator: ".")
        guard parts.count == 4,
              let a = UInt32(parts[0]), let b = UInt32(parts[1]),
              let c = UInt32(parts[2]), let d = UInt32(parts[3]),
              a < 256, b < 256, c < 256, d < 256 else { return nil }
        rawValue = (a << 24) | (b << 16) | (c << 8) | d
    }
}

struct IPv6Address: Equatable {
    static let localhost = IPv6Address(parts: [0, 0, 0, 0, 0, 0, 0, 1])
    var parts: [UInt16]
    var isLoopback: Bool { parts == [0, 0, 0, 0, 0, 0, 0, 1] }
    var isUnspecified: Bool { parts.allSatisfy { $0 == 0 } }
    var isMulticast: Bool { (parts.first ?? 0) & 0xFF00 == 0xFF00 }
    var isUniqueLocal: Bool { (parts.first ?? 0) & 0xFE00 == 0xFC00 }
    var isLinkLocal: Bool { (parts.first ?? 0) & 0xFFC0 == 0xFE80 }
    var ipv4: IPv4Address? {
        guard parts.prefix(6).allSatisfy({ $0 == 0 }) || (parts[0...4] == [0, 0, 0, 0, 0] && parts[5] == 0xFFFF) else {
            return nil
        }
        let hi = UInt32(parts[6])
        let lo = UInt32(parts[7])
        return IPv4Address(rawValue: (hi << 16) | lo)
    }

    init(parts: [UInt16]) { self.parts = parts }

    init?(_ string: String) {
        let unscoped = string.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? string
        var input = unscoped
        if input.hasPrefix("::ffff:") {
            if let v4 = IPv4Address(String(input.dropFirst(7))) {
                self.parts = [0, 0, 0, 0, 0, 0xFFFF, UInt16(v4.rawValue >> 16), UInt16(v4.rawValue & 0xFFFF)]
                return
            }
        }
        let halves = input.split(separator: "::", omittingEmptySubsequences: false)
        if halves.count > 2 { return nil }
        func parseHalf(_ text: Substring) -> [UInt16]? {
            if text.isEmpty { return [] }
            let parts = text.split(separator: ":")
            var values: [UInt16] = []
            for part in parts {
                if part.contains(".") {
                    guard let v4 = IPv4Address(String(part)) else { return nil }
                    values.append(UInt16(v4.rawValue >> 16))
                    values.append(UInt16(v4.rawValue & 0xFFFF))
                } else if let value = UInt16(part, radix: 16) {
                    values.append(value)
                } else {
                    return nil
                }
            }
            return values
        }
        if halves.count == 1 {
            guard let values = parseHalf(halves[0]), values.count == 8 else { return nil }
            parts = values
        } else {
            guard let left = parseHalf(halves[0]), let right = parseHalf(halves[1]) else { return nil }
            let missing = 8 - left.count - right.count
            if missing < 0 { return nil }
            parts = left + Array(repeating: 0, count: missing) + right
        }
    }
}

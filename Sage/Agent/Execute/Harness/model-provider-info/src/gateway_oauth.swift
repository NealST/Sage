//
//  gateway_oauth.swift
//  CodexModelProviderInfo
//
//  Port of codex-rs/model-provider-info/src/gateway_oauth.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Secondary OAuth credentials delivered alongside the provider's primary
//  authentication. `url::Url` maps to Foundation `URL` (relative strings
//  without a scheme fail as "invalid … URL"; host / userinfo / fragment /
//  scheme policy matches upstream). `http::HeaderName` maps to the local
//  tchar / reserved-name checks below. `schemars` is omitted.
//

import Foundation

// Reserve authentication, routing/framing, and internal protocol headers.
private let reservedGatewayOauthHeaders: [String] = [
    "authorization",
    "proxy-authorization",
    "cookie",
    "host",
    "content-length",
    "transfer-encoding",
    "connection",
    "upgrade",
    "chatgpt-account-id",
]
private let reservedGatewayOauthHeaderPrefixes: [String] = [
    "x-codex-",
    "x-openai-",
    "sec-websocket-",
]

public struct GatewayOAuthConfig: Equatable, Sendable {
    public var authorizationUrl: String
    public var tokenUrl: String
    public var clientId: String
    public var resource: String?
    public var scopes: [String]
    public var redirectPort: UInt16?
    public var delivery: GatewayOAuthDelivery

    public init(
        authorizationUrl: String,
        tokenUrl: String,
        clientId: String,
        resource: String? = nil,
        scopes: [String] = [],
        redirectPort: UInt16? = nil,
        delivery: GatewayOAuthDelivery
    ) {
        self.authorizationUrl = authorizationUrl
        self.tokenUrl = tokenUrl
        self.clientId = clientId
        self.resource = resource
        self.scopes = scopes
        self.redirectPort = redirectPort
        self.delivery = delivery
    }
}

extension GatewayOAuthConfig: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case authorizationUrl = "authorization_url"
        case tokenUrl = "token_url"
        case clientId = "client_id"
        case resource
        case scopes
        case redirectPort = "redirect_port"
        case delivery
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "GatewayOAuthConfig")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationUrl = try container.decode(String.self, forKey: .authorizationUrl)
        tokenUrl = try container.decode(String.self, forKey: .tokenUrl)
        clientId = try container.decode(String.self, forKey: .clientId)
        resource = try container.decodeIfPresent(String.self, forKey: .resource)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes) ?? []
        redirectPort = try container.decodeIfPresent(UInt16.self, forKey: .redirectPort)
        delivery = try container.decode(GatewayOAuthDelivery.self, forKey: .delivery)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(authorizationUrl, forKey: .authorizationUrl)
        try container.encode(tokenUrl, forKey: .tokenUrl)
        try container.encode(clientId, forKey: .clientId)
        try container.encodeIfPresent(resource, forKey: .resource)
        try container.encode(scopes, forKey: .scopes)
        try container.encodeIfPresent(redirectPort, forKey: .redirectPort)
        try container.encode(delivery, forKey: .delivery)
    }
}

extension GatewayOAuthConfig: CustomDebugStringConvertible {
    public var debugDescription: String {
        "GatewayOAuthConfig(delivery: \(String(reflecting: delivery)), …)"
    }
}

public enum GatewayOAuthDelivery: Equatable, Sendable {
    case header(name: String, scheme: String)
    case cookie(name: String)
}

extension GatewayOAuthDelivery: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case scheme
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "header":
            try rejectUnknownFields(
                in: decoder, allowedNames: ["kind", "name", "scheme"], type: "GatewayOAuthDelivery")
            let name = try container.decode(String.self, forKey: .name)
            let scheme = try container.decodeIfPresent(String.self, forKey: .scheme) ?? "Bearer"
            self = .header(name: name, scheme: scheme)
        case "cookie":
            try rejectUnknownFields(
                in: decoder, allowedNames: ["kind", "name"], type: "GatewayOAuthDelivery")
            let name = try container.decode(String.self, forKey: .name)
            self = .cookie(name: name)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "unknown variant `\(kind)`, expected `header` or `cookie`"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .header(let name, let scheme):
            try container.encode("header", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(scheme, forKey: .scheme)
        case .cookie(let name):
            try container.encode("cookie", forKey: .kind)
            try container.encode(name, forKey: .name)
        }
    }
}

extension GatewayOAuthConfig {
    func validate(_ provider: ModelProviderInfo) -> Result<Void, ModelProviderConfigError> {
        if provider.aws != nil || provider.isAmazonBedrock() {
            return .failure(
                ModelProviderConfigError(
                    "provider gateway_oauth cannot be combined with AWS authentication"))
        }
        if case .failure(let error) = validateUrl(
            authorizationUrl, field: "gateway_oauth.authorization_url")
        {
            return .failure(error)
        }
        if case .failure(let error) = validateUrl(tokenUrl, field: "gateway_oauth.token_url") {
            return .failure(error)
        }
        guard let baseUrl = provider.baseUrl else {
            return .failure(ModelProviderConfigError("gateway_oauth requires base_url"))
        }
        if case .failure(let error) = validateUrl(baseUrl, field: "base_url") {
            return .failure(error)
        }
        if clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || redirectPort == 0 {
            return .failure(
                ModelProviderConfigError(
                    "gateway_oauth requires a nonempty client_id and a nonzero redirect_port"))
        }
        let header: String
        switch delivery {
        case .header(let name, let scheme):
            guard let parsed = httpHeaderName(name) else {
                return .failure(ModelProviderConfigError("invalid gateway_oauth header name"))
            }
            if !isToken(scheme)
                || reservedGatewayOauthHeaders.contains(parsed)
                || reservedGatewayOauthHeaderPrefixes.contains(where: { parsed.hasPrefix($0) })
            {
                return .failure(
                    ModelProviderConfigError(
                        "invalid or reserved gateway_oauth delivery header or scheme"))
            }
            header = parsed
        case .cookie(let name):
            if !isToken(name) {
                return .failure(ModelProviderConfigError("invalid gateway_oauth cookie name"))
            }
            header = "cookie"
        }
        var configuredNames: [String] = []
        if let keys = provider.httpHeaders?.keys {
            configuredNames.append(contentsOf: keys)
        }
        if let keys = provider.envHttpHeaders?.keys {
            configuredNames.append(contentsOf: keys)
        }
        if configuredNames.contains(where: { $0.caseInsensitiveCompare(header) == .orderedSame }) {
            return .failure(
                ModelProviderConfigError(
                    "gateway_oauth delivery conflicts with a configured provider header"))
        }
        return .success(())
    }
}

func isToken(_ value: String) -> Bool {
    !value.isEmpty
        && value.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || "!#$%&'*+-.^_`|~".utf8.contains(byte)
        }
}

private func validateUrl(_ value: String, field: String) -> Result<Void, ModelProviderConfigError> {
    guard let url = URL(string: value), let scheme = url.scheme, !scheme.isEmpty else {
        return .failure(ModelProviderConfigError("invalid \(field) URL"))
    }
    let host = url.host
    let loopback: Bool
    if let host {
        if host.caseInsensitiveCompare("localhost") == .orderedSame {
            loopback = true
        } else if isIpv4Loopback(host) || isIpv6Loopback(host) {
            loopback = true
        } else {
            loopback = false
        }
    } else {
        loopback = false
    }
    let username = url.user ?? ""
    if host == nil
        || !username.isEmpty
        || url.password != nil
        || url.fragment != nil
        || !(scheme == "https" || (scheme == "http" && loopback))
    {
        return .failure(
            ModelProviderConfigError(
                "\(field) must use HTTPS (or loopback HTTP), without userinfo or a fragment"))
    }
    return .success(())
}

private func isIpv4Loopback(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4,
        let first = UInt8(parts[0]), first == 127,
        parts.dropFirst().allSatisfy({ UInt8($0) != nil })
    else {
        return false
    }
    return true
}

private func isIpv6Loopback(_ host: String) -> Bool {
    let normalized = host.lowercased()
    return normalized == "::1" || normalized == "0:0:0:0:0:0:0:1"
}

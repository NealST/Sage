//
//  lib.swift
//  CodexModelProviderInfo
//
//  Port of codex-rs/model-provider-info/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Registry of built-in and user-configured model providers. `RedactedString`
//  maps to `String` (Debug no longer redacts secrets). `http::HeaderMap` maps
//  to `[String: String]` with names lowercased on insert (http `HeaderName`
//  behavior). Process-wide residency uses `OSAllocatedUnfairLock` instead of
//  `RwLock` (no poison recovery). `env!("CARGO_PKG_VERSION")` reads
//  `CFBundleShortVersionString` with fallback `"0.0.0-sage"`. `codex_client::Provider`
//  is the local `ApiProvider` / `ApiRetryConfig` below. `schemars` is omitted.
//  Stored retry optionals are `requestMaxRetriesOverride` /
//  `streamMaxRetriesOverride` so they do not collide with `requestMaxRetries()` /
//  `streamMaxRetries()`. Rust `Result<T, String>` is `Result<T, ModelProviderConfigError>`
//  because Swift `Result.Failure` must be `Error`.
//

import CodexProtocol
import Foundation
import os

// MARK: - Local stand-ins for `codex_client::{Provider, RetryConfig}`

public struct ApiRetryConfig: Equatable, Sendable {
    public var maxAttempts: UInt64
    public var baseDelay: Duration
    public var retry429: Bool
    public var retry5xx: Bool
    public var retryTransport: Bool

    public init(
        maxAttempts: UInt64,
        baseDelay: Duration,
        retry429: Bool,
        retry5xx: Bool,
        retryTransport: Bool
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.retry429 = retry429
        self.retry5xx = retry5xx
        self.retryTransport = retryTransport
    }
}

public struct ApiProvider: Equatable, Sendable {
    public var name: String
    public var baseUrl: String
    public var queryParams: [String: String]?
    public var headers: [String: String]
    public var retry: ApiRetryConfig
    public var streamIdleTimeout: Duration

    public init(
        name: String,
        baseUrl: String,
        queryParams: [String: String]?,
        headers: [String: String],
        retry: ApiRetryConfig,
        streamIdleTimeout: Duration
    ) {
        self.name = name
        self.baseUrl = baseUrl
        self.queryParams = queryParams
        self.headers = headers
        self.retry = retry
        self.streamIdleTimeout = streamIdleTimeout
    }
}

// MARK: - Constants

public let RESIDENCY_HEADER_NAME = "x-openai-internal-codex-residency"

private let defaultStreamIdleTimeoutMs: UInt64 = 300_000
private let defaultStreamMaxRetries: UInt64 = 5
private let defaultRequestMaxRetries: UInt64 = 4
let defaultAwsCredentialExportTimeoutMs: UInt64 = 30_000
let defaultAwsAuthRefreshTimeoutMs: UInt64 = 300_000
public let DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS: UInt64 = 15_000
private let maxStreamMaxRetries: UInt64 = 100
private let maxRequestMaxRetries: UInt64 = 100

private let openaiProviderName = "OpenAI"
private let openaiActorAuthorizationHeader = "x-openai-actor-authorization"
public let OPENAI_PROVIDER_ID = "openai"
public let CHATGPT_CODEX_BASE_URL = "https://chatgpt.com/backend-api/codex"
private let amazonBedrockProviderName = "Amazon Bedrock"
public let AMAZON_BEDROCK_PROVIDER_ID = "amazon-bedrock"
private let amazonBedrockRuntimeProviderName = "Amazon Bedrock Runtime"
public let AMAZON_BEDROCK_RUNTIME_PROVIDER_ID = "amazon-bedrock-runtime"
public let AMAZON_BEDROCK_GPT_5_5_MODEL_ID = "openai.gpt-5.5"
public let AMAZON_BEDROCK_GPT_5_6_SOL_MODEL_ID = "openai.gpt-5.6-sol"
public let AMAZON_BEDROCK_GPT_6_SOL_MODEL_ID = "openai.gpt-6-sol"
public let AMAZON_BEDROCK_GPT_6_LUNA_MODEL_ID = "openai.gpt-6-luna"
public let AMAZON_BEDROCK_GPT_6_ASTRA_MODEL_ID = "openai.gpt-6-astra"
public let AMAZON_BEDROCK_GPT_5_6_TERRA_MODEL_ID = "openai.gpt-5.6-terra"
public let AMAZON_BEDROCK_GPT_5_6_LUNA_MODEL_ID = "openai.gpt-5.6-luna"
public let AMAZON_BEDROCK_RUNTIME_GLOBAL_GPT_5_6_TERRA_MODEL_ID = "global.openai.gpt-5.6-terra"
public let AMAZON_BEDROCK_RUNTIME_GLOBAL_GPT_5_6_LUNA_MODEL_ID = "global.openai.gpt-5.6-luna"
public let AMAZON_BEDROCK_DEFAULT_BASE_URL = "https://bedrock-mantle.us-east-1.api.aws/openai/v1"
private let amazonBedrockMantleClientAgentHeader = "x-amzn-mantle-client-agent"
private let amazonBedrockMantleClientAgentValue = "codex"
let chatWireApiRemovedError =
    "`wire_api = \"chat\"` is no longer supported.\nHow to fix: set `wire_api = \"responses\"` in your provider config.\nMore info: https://github.com/openai/codex/discussions/7782"
public let LEGACY_OLLAMA_CHAT_PROVIDER_ID = "ollama-chat"
public let OLLAMA_CHAT_PROVIDER_REMOVED_ERROR =
    "`ollama-chat` is no longer supported.\nHow to fix: replace `ollama-chat` with `ollama` in `model_provider`, `oss_provider`, or `--local-provider`.\nMore info: https://github.com/openai/codex/discussions/7782"

public let DEFAULT_LMSTUDIO_PORT: UInt16 = 1234
public let DEFAULT_OLLAMA_PORT: UInt16 = 11434

public let LMSTUDIO_OSS_PROVIDER_ID = "lmstudio"
public let OLLAMA_OSS_PROVIDER_ID = "ollama"

/// Swift `Result` requires `Failure: Error`; stands in for Rust `Result<T, String>`.
public struct ModelProviderConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

// MARK: - Residency

public enum ResidencyRequirement: String, Codable, Equatable, Sendable {
    case us
}

private let requirementsResidency = OSAllocatedUnfairLock<ResidencyRequirement?>(initialState: nil)

/// Sets the process-wide residency requirement loaded from managed configuration.
public func setManagedResidencyRequirement(_ enforceResidency: ResidencyRequirement?) {
    requirementsResidency.withLock { state in
        state = enforceResidency
    }
}

/// Returns the current process-wide managed residency requirement.
public func readManagedResidencyRequirement() -> ResidencyRequirement? {
    requirementsResidency.withLock { $0 }
}

// MARK: - Wire API

/// Wire protocol that the provider speaks.
public enum WireApi: Equatable, Sendable, CustomStringConvertible {
    case responses

    public static let `default`: WireApi = .responses

    public var description: String { "responses" }
}

extension WireApi: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "responses":
            self = .responses
        case "chat":
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: chatWireApiRemovedError
            )
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unknown variant `\(value)`, expected `responses`"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("responses")
    }
}

// MARK: - ModelProviderInfo

/// Serializable representation of a provider definition.
public struct ModelProviderInfo: Equatable, Sendable {
    public var name: String
    public var baseUrl: String?
    public var modelCatalogUrl: String?
    public var envKey: String?
    public var envKeyInstructions: String?
    public var experimentalBearerToken: String?
    public var auth: ModelProviderAuthInfo?
    public var gatewayOauth: GatewayOAuthConfig?
    public var aws: ModelProviderAwsAuthInfo?
    public var wireApi: WireApi
    public var queryParams: [String: String]?
    public var httpHeaders: [String: String]?
    public var envHttpHeaders: [String: String]?
    /// Configured `request_max_retries`. Stored separately from
    /// `requestMaxRetries()` because Swift cannot overload a property and method.
    public var requestMaxRetriesOverride: UInt64?
    /// Configured `stream_max_retries`.
    public var streamMaxRetriesOverride: UInt64?
    public var streamIdleTimeoutMs: UInt64?
    public var websocketConnectTimeoutMs: UInt64?
    public var requiresOpenaiAuth: Bool
    public var supportsWebsockets: Bool
    public var supportsStandaloneWebSearch: Bool

    public init(
        name: String = "",
        baseUrl: String? = nil,
        modelCatalogUrl: String? = nil,
        envKey: String? = nil,
        envKeyInstructions: String? = nil,
        experimentalBearerToken: String? = nil,
        auth: ModelProviderAuthInfo? = nil,
        gatewayOauth: GatewayOAuthConfig? = nil,
        aws: ModelProviderAwsAuthInfo? = nil,
        wireApi: WireApi = .responses,
        queryParams: [String: String]? = nil,
        httpHeaders: [String: String]? = nil,
        envHttpHeaders: [String: String]? = nil,
        requestMaxRetriesOverride: UInt64? = nil,
        streamMaxRetriesOverride: UInt64? = nil,
        streamIdleTimeoutMs: UInt64? = nil,
        websocketConnectTimeoutMs: UInt64? = nil,
        requiresOpenaiAuth: Bool = false,
        supportsWebsockets: Bool = false,
        supportsStandaloneWebSearch: Bool = false
    ) {
        self.name = name
        self.baseUrl = baseUrl
        self.modelCatalogUrl = modelCatalogUrl
        self.envKey = envKey
        self.envKeyInstructions = envKeyInstructions
        self.experimentalBearerToken = experimentalBearerToken
        self.auth = auth
        self.gatewayOauth = gatewayOauth
        self.aws = aws
        self.wireApi = wireApi
        self.queryParams = queryParams
        self.httpHeaders = httpHeaders
        self.envHttpHeaders = envHttpHeaders
        self.requestMaxRetriesOverride = requestMaxRetriesOverride
        self.streamMaxRetriesOverride = streamMaxRetriesOverride
        self.streamIdleTimeoutMs = streamIdleTimeoutMs
        self.websocketConnectTimeoutMs = websocketConnectTimeoutMs
        self.requiresOpenaiAuth = requiresOpenaiAuth
        self.supportsWebsockets = supportsWebsockets
        self.supportsStandaloneWebSearch = supportsStandaloneWebSearch
    }
}

extension ModelProviderInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case name
        case baseUrl = "base_url"
        case modelCatalogUrl = "model_catalog_url"
        case envKey = "env_key"
        case envKeyInstructions = "env_key_instructions"
        case experimentalBearerToken = "experimental_bearer_token"
        case auth
        case gatewayOauth = "gateway_oauth"
        case aws
        case wireApi = "wire_api"
        case queryParams = "query_params"
        case httpHeaders = "http_headers"
        case envHttpHeaders = "env_http_headers"
        case requestMaxRetriesOverride = "request_max_retries"
        case streamMaxRetriesOverride = "stream_max_retries"
        case streamIdleTimeoutMs = "stream_idle_timeout_ms"
        case websocketConnectTimeoutMs = "websocket_connect_timeout_ms"
        case requiresOpenaiAuth = "requires_openai_auth"
        case supportsWebsockets = "supports_websockets"
        case supportsStandaloneWebSearch = "supports_standalone_web_search"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
        modelCatalogUrl = try container.decodeIfPresent(String.self, forKey: .modelCatalogUrl)
        envKey = try container.decodeIfPresent(String.self, forKey: .envKey)
        envKeyInstructions = try container.decodeIfPresent(String.self, forKey: .envKeyInstructions)
        experimentalBearerToken = try container.decodeIfPresent(
            String.self, forKey: .experimentalBearerToken)
        auth = try container.decodeIfPresent(ModelProviderAuthInfo.self, forKey: .auth)
        gatewayOauth = try container.decodeIfPresent(GatewayOAuthConfig.self, forKey: .gatewayOauth)
        aws = try container.decodeIfPresent(ModelProviderAwsAuthInfo.self, forKey: .aws)
        wireApi = try container.decodeIfPresent(WireApi.self, forKey: .wireApi) ?? .responses
        queryParams = try container.decodeIfPresent([String: String].self, forKey: .queryParams)
        httpHeaders = try container.decodeIfPresent([String: String].self, forKey: .httpHeaders)
        envHttpHeaders = try container.decodeIfPresent(
            [String: String].self, forKey: .envHttpHeaders)
        requestMaxRetriesOverride = try container.decodeIfPresent(
            UInt64.self, forKey: .requestMaxRetriesOverride)
        streamMaxRetriesOverride = try container.decodeIfPresent(
            UInt64.self, forKey: .streamMaxRetriesOverride)
        streamIdleTimeoutMs = try container.decodeIfPresent(
            UInt64.self, forKey: .streamIdleTimeoutMs)
        websocketConnectTimeoutMs = try container.decodeIfPresent(
            UInt64.self, forKey: .websocketConnectTimeoutMs)
        requiresOpenaiAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresOpenaiAuth) ?? false
        supportsWebsockets =
            try container.decodeIfPresent(Bool.self, forKey: .supportsWebsockets) ?? false
        supportsStandaloneWebSearch =
            try container.decodeIfPresent(Bool.self, forKey: .supportsStandaloneWebSearch) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
        try container.encodeIfPresent(modelCatalogUrl, forKey: .modelCatalogUrl)
        try container.encodeIfPresent(envKey, forKey: .envKey)
        try container.encodeIfPresent(envKeyInstructions, forKey: .envKeyInstructions)
        try container.encodeIfPresent(experimentalBearerToken, forKey: .experimentalBearerToken)
        try container.encodeIfPresent(auth, forKey: .auth)
        try container.encodeIfPresent(gatewayOauth, forKey: .gatewayOauth)
        try container.encodeIfPresent(aws, forKey: .aws)
        try container.encode(wireApi, forKey: .wireApi)
        try container.encodeIfPresent(queryParams, forKey: .queryParams)
        try container.encodeIfPresent(httpHeaders, forKey: .httpHeaders)
        try container.encodeIfPresent(envHttpHeaders, forKey: .envHttpHeaders)
        try container.encodeIfPresent(requestMaxRetriesOverride, forKey: .requestMaxRetriesOverride)
        try container.encodeIfPresent(streamMaxRetriesOverride, forKey: .streamMaxRetriesOverride)
        try container.encodeIfPresent(streamIdleTimeoutMs, forKey: .streamIdleTimeoutMs)
        try container.encodeIfPresent(websocketConnectTimeoutMs, forKey: .websocketConnectTimeoutMs)
        try container.encode(requiresOpenaiAuth, forKey: .requiresOpenaiAuth)
        try container.encode(supportsWebsockets, forKey: .supportsWebsockets)
        try container.encode(supportsStandaloneWebSearch, forKey: .supportsStandaloneWebSearch)
    }
}

// MARK: - AWS auth

public struct ModelProviderAwsAuthInfo: Equatable, Sendable {
    public var profile: String?
    public var region: String?
    public var credentialExport: AwsCredentialExportConfig?
    public var authRefresh: AwsAuthRefreshConfig?

    public init(
        profile: String? = nil,
        region: String? = nil,
        credentialExport: AwsCredentialExportConfig? = nil,
        authRefresh: AwsAuthRefreshConfig? = nil
    ) {
        self.profile = profile
        self.region = region
        self.credentialExport = credentialExport
        self.authRefresh = authRefresh
    }
}

extension ModelProviderAwsAuthInfo: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case profile
        case region
        case credentialExport = "credential_export"
        case authRefresh = "auth_refresh"
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(
            in: decoder, keys: CodingKeys.self, type: "ModelProviderAwsAuthInfo")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        credentialExport = try container.decodeIfPresent(
            AwsCredentialExportConfig.self, forKey: .credentialExport)
        authRefresh = try container.decodeIfPresent(
            AwsAuthRefreshConfig.self, forKey: .authRefresh)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(credentialExport, forKey: .credentialExport)
        try container.encodeIfPresent(authRefresh, forKey: .authRefresh)
    }
}

public struct AwsCredentialExportConfig: Equatable, Sendable {
    public var command: String
    public var args: [String]
    public var timeoutMs: UInt64

    public init(
        command: String,
        args: [String] = [],
        timeoutMs: UInt64 = 30_000
    ) {
        self.command = command
        self.args = args
        self.timeoutMs = timeoutMs
    }

    public func timeout() -> Duration {
        durationFromMilliseconds(timeoutMs)
    }
}

extension AwsCredentialExportConfig: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case command
        case args
        case timeoutMs = "timeout_ms"
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(
            in: decoder, keys: CodingKeys.self, type: "AwsCredentialExportConfig")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        let decodedTimeout = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMs)
            ?? defaultAwsCredentialExportTimeoutMs
        timeoutMs = try decodeNonZeroU64(
            decodedTimeout, field: "timeout_ms", codingPath: decoder.codingPath)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encode(timeoutMs, forKey: .timeoutMs)
    }
}

public struct AwsAuthRefreshConfig: Equatable, Sendable {
    public var command: String
    public var args: [String]
    public var timeoutMs: UInt64

    public init(
        command: String,
        args: [String] = [],
        timeoutMs: UInt64 = 300_000
    ) {
        self.command = command
        self.args = args
        self.timeoutMs = timeoutMs
    }

    public func timeout() -> Duration {
        durationFromMilliseconds(timeoutMs)
    }
}

extension AwsAuthRefreshConfig: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case command
        case args
        case timeoutMs = "timeout_ms"
    }

    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "AwsAuthRefreshConfig")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        let decodedTimeout = try container.decodeIfPresent(UInt64.self, forKey: .timeoutMs)
            ?? defaultAwsAuthRefreshTimeoutMs
        timeoutMs = try decodeNonZeroU64(
            decodedTimeout, field: "timeout_ms", codingPath: decoder.codingPath)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encode(timeoutMs, forKey: .timeoutMs)
    }
}

// MARK: - ModelProviderInfo methods

extension ModelProviderInfo {
    /// Checks that a configured Bedrock entry only customizes supported fields.
    /// Call this on the override before merging it with the built-in provider.
    public func validateBedrockOverride() -> Result<Void, ModelProviderConfigError> {
        let unsupportedFields = ModelProviderInfo(
            name: name,
            baseUrl: nil,
            modelCatalogUrl: modelCatalogUrl,
            envKey: envKey,
            envKeyInstructions: envKeyInstructions,
            experimentalBearerToken: experimentalBearerToken,
            auth: nil,
            gatewayOauth: gatewayOauth,
            aws: nil,
            wireApi: wireApi,
            queryParams: queryParams,
            httpHeaders: nil,
            envHttpHeaders: envHttpHeaders,
            requestMaxRetriesOverride: requestMaxRetriesOverride,
            streamMaxRetriesOverride: streamMaxRetriesOverride,
            streamIdleTimeoutMs: streamIdleTimeoutMs,
            websocketConnectTimeoutMs: websocketConnectTimeoutMs,
            requiresOpenaiAuth: requiresOpenaiAuth,
            supportsWebsockets: supportsWebsockets,
            supportsStandaloneWebSearch: supportsStandaloneWebSearch
        )
        if unsupportedFields != ModelProviderInfo() {
            return .failure(
                ModelProviderConfigError(
                    "only supports changing "
                        + "`base_url`, `auth`, `http_headers`, `aws.profile`, `aws.region`, `aws.credential_export`, "
                        + "and `aws.auth_refresh`; "
                        + "other non-default provider fields are not supported"))
        }
        return .success(())
    }

    public func validate() -> Result<Void, ModelProviderConfigError> {
        if let gateway = gatewayOauth {
            switch gateway.validate(self) {
            case .failure(let error):
                return .failure(error)
            case .success:
                break
            }
        }
        if let aws {
            if supportsWebsockets {
                return .failure(
                    ModelProviderConfigError("provider aws cannot be combined with supports_websockets"))
            }

            var conflicts: [String] = []
            if envKey != nil { conflicts.append("env_key") }
            if experimentalBearerToken != nil { conflicts.append("experimental_bearer_token") }
            if auth != nil { conflicts.append("auth") }
            if requiresOpenaiAuth { conflicts.append("requires_openai_auth") }

            if !conflicts.isEmpty {
                return .failure(
                    ModelProviderConfigError(
                        "provider aws cannot be combined with \(conflicts.joined(separator: ", "))"))
            }

            if let credentialExport = aws.credentialExport {
                if aws.profile != nil {
                    return .failure(
                        ModelProviderConfigError(
                            "provider aws.credential_export cannot be combined with aws.profile"))
                }
                if credentialExport.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .failure(
                        ModelProviderConfigError(
                            "provider aws.credential_export.command must not be empty"))
                }
                if !isAbsoluteFilesystemPath(credentialExport.command)
                    && !isBareExecutableName(credentialExport.command)
                {
                    return .failure(
                        ModelProviderConfigError(
                            "provider aws.credential_export.command must be an absolute path or a bare executable name"
                        ))
                }
            }

            if let authRefresh = aws.authRefresh {
                if authRefresh.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .failure(
                        ModelProviderConfigError("provider aws.auth_refresh.command must not be empty"))
                }
                if authRefresh.command != "aws" {
                    return .failure(
                        ModelProviderConfigError("provider aws.auth_refresh.command must be `aws`"))
                }
            }
        }

        guard let auth else {
            return .success(())
        }

        if auth.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(ModelProviderConfigError("provider auth.command must not be empty"))
        }

        var conflicts: [String] = []
        if envKey != nil { conflicts.append("env_key") }
        if experimentalBearerToken != nil { conflicts.append("experimental_bearer_token") }
        if requiresOpenaiAuth { conflicts.append("requires_openai_auth") }

        if conflicts.isEmpty {
            return .success(())
        }
        return .failure(
            ModelProviderConfigError(
                "provider auth cannot be combined with \(conflicts.joined(separator: ", "))"))
    }

    private func buildHeaderMap() -> [String: String] {
        var headers: [String: String] = [:]
        if let extra = httpHeaders {
            for (key, value) in extra {
                if let name = httpHeaderName(key), isHttpHeaderValue(value) {
                    headers[name] = value
                }
            }
        }
        if let envHeaders = envHttpHeaders {
            let environment = ProcessInfo.processInfo.environment
            for (header, envVar) in envHeaders {
                guard let value = environment[envVar],
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    let name = httpHeaderName(header),
                    isHttpHeaderValue(value)
                else {
                    continue
                }
                headers[name] = value
            }
        }
        return headers
    }

    /// Builds an API provider with managed residency taking precedence over configured headers.
    public func toApiProvider(authMode: AuthMode?) throws -> ApiProvider {
        let defaultBaseUrl: String
        switch authMode {
        case .chatgpt, .chatgptAuthTokens, .headers, .agentIdentity, .personalAccessToken:
            defaultBaseUrl = CHATGPT_CODEX_BASE_URL
        case .apiKey, .bedrockApiKey, .bedrockAccessKeys, .none:
            defaultBaseUrl = "https://api.openai.com/v1"
        }
        let resolvedBaseUrl = baseUrl ?? defaultBaseUrl

        var headers = buildHeaderMap()
        if let requirement = readManagedResidencyRequirement() {
            let value: String
            switch requirement {
            case .us:
                value = "us"
            }
            headers[RESIDENCY_HEADER_NAME] = value
        }
        let retry = ApiRetryConfig(
            maxAttempts: requestMaxRetries(),
            baseDelay: .milliseconds(200),
            retry429: false,
            retry5xx: true,
            retryTransport: true
        )
        return ApiProvider(
            name: name,
            baseUrl: resolvedBaseUrl,
            queryParams: queryParams,
            headers: headers,
            retry: retry,
            streamIdleTimeout: streamIdleTimeout()
        )
    }

    /// If `envKey` is set, returns the API key for this provider if present
    /// (and non-empty) in the environment. If `envKey` is required but
    /// cannot be found, throws `CodexErr.envVar`.
    public func apiKey() throws -> String? {
        guard let envKey else { return nil }
        let apiKey = ProcessInfo.processInfo.environment[envKey]
            .flatMap { value -> String? in
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
        guard let apiKey else {
            throw CodexErr.envVar(
                EnvVarError(varName: envKey, instructions: envKeyInstructions))
        }
        return apiKey
    }

    /// Effective maximum number of request retries for this provider.
    public func requestMaxRetries() -> UInt64 {
        min(requestMaxRetriesOverride ?? defaultRequestMaxRetries, maxRequestMaxRetries)
    }

    /// Effective maximum number of stream reconnection attempts for this provider.
    public func streamMaxRetries() -> UInt64 {
        min(streamMaxRetriesOverride ?? defaultStreamMaxRetries, maxStreamMaxRetries)
    }

    /// Effective idle timeout for streaming responses.
    public func streamIdleTimeout() -> Duration {
        durationFromMilliseconds(streamIdleTimeoutMs ?? defaultStreamIdleTimeoutMs)
    }

    /// Effective timeout for websocket connect attempts.
    public func websocketConnectTimeout() -> Duration {
        durationFromMilliseconds(websocketConnectTimeoutMs ?? DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS)
    }

    public static func createOpenaiProvider(_ baseUrl: String?) -> ModelProviderInfo {
        ModelProviderInfo(
            name: openaiProviderName,
            baseUrl: baseUrl,
            httpHeaders: ["version": cargoPackageVersion()],
            envHttpHeaders: [
                "OpenAI-Organization": "OPENAI_ORGANIZATION",
                "OpenAI-Project": "OPENAI_PROJECT",
            ],
            requiresOpenaiAuth: true,
            supportsWebsockets: true,
            supportsStandaloneWebSearch: true
        )
    }

    public static func createAmazonBedrockProvider(
        _ aws: ModelProviderAwsAuthInfo?
    ) -> ModelProviderInfo {
        ModelProviderInfo(
            name: amazonBedrockProviderName,
            aws: aws ?? ModelProviderAwsAuthInfo(),
            httpHeaders: [
                amazonBedrockMantleClientAgentHeader: amazonBedrockMantleClientAgentValue
            ]
        )
    }

    public static func createAmazonBedrockRuntimeProvider(
        _ aws: ModelProviderAwsAuthInfo?
    ) -> ModelProviderInfo {
        var provider = createAmazonBedrockProvider(aws)
        provider.name = amazonBedrockRuntimeProviderName
        return provider
    }

    public func isOpenai() -> Bool {
        name == openaiProviderName
    }

    public func supportsCodexBackendRoutes() -> Bool {
        isOpenai()
            && (baseUrl.map { url in
                var trimmed = url
                while trimmed.hasSuffix("/") {
                    trimmed.removeLast()
                }
                return trimmed.hasSuffix("/backend-api/codex")
            } ?? true)
    }

    public func usesOpenaiActorAuthorization() -> Bool {
        !requiresOpenaiAuth
            && (httpHeaders?.contains { name, value in
                name.caseInsensitiveCompare(openaiActorAuthorizationHeader) == .orderedSame
                    && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false)
    }

    public func isAmazonBedrock() -> Bool {
        name == amazonBedrockProviderName || name == amazonBedrockRuntimeProviderName
    }

    public func isAmazonBedrockRuntime() -> Bool {
        name == amazonBedrockRuntimeProviderName
    }

    public func hasCommandAuth() -> Bool {
        auth != nil
    }
}

// MARK: - Built-in catalog

/// Built-in default provider list.
public func builtInModelProviders(
    _ openaiBaseUrl: String?
) -> [String: ModelProviderInfo] {
    [
        OPENAI_PROVIDER_ID: .createOpenaiProvider(openaiBaseUrl),
        AMAZON_BEDROCK_PROVIDER_ID: .createAmazonBedrockProvider(nil),
        AMAZON_BEDROCK_RUNTIME_PROVIDER_ID: .createAmazonBedrockRuntimeProvider(nil),
        OLLAMA_OSS_PROVIDER_ID: createOssProvider(DEFAULT_OLLAMA_PORT, .responses),
        LMSTUDIO_OSS_PROVIDER_ID: createOssProvider(DEFAULT_LMSTUDIO_PORT, .responses),
    ]
}

/// Merge configured providers into the built-in provider catalog.
///
/// Configured providers extend the built-in set. Built-in providers are not
/// generally overridable, but built-in Amazon Bedrock providers allow the user
/// to customize their endpoint, authentication, headers, and AWS settings.
public func mergeConfiguredModelProviders(
    _ modelProviders: [String: ModelProviderInfo],
    _ configuredModelProviders: [String: ModelProviderInfo]
) -> Result<[String: ModelProviderInfo], ModelProviderConfigError> {
    var modelProviders = modelProviders
    for (key, var provider) in configuredModelProviders {
        if key == AMAZON_BEDROCK_PROVIDER_ID || key == AMAZON_BEDROCK_RUNTIME_PROVIDER_ID {
            switch provider.validateBedrockOverride() {
            case .failure(let message):
                return .failure(ModelProviderConfigError("model_providers.\(key) \(message.message)"))
            case .success:
                break
            }
            let baseUrlOverride = provider.baseUrl
            provider.baseUrl = nil
            let authOverride = provider.auth
            provider.auth = nil
            let awsOverride = provider.aws
            provider.aws = nil
            let httpHeadersOverride = provider.httpHeaders
            provider.httpHeaders = nil
            if var builtIn = modelProviders[key] {
                builtIn.baseUrl = baseUrlOverride
                builtIn.auth = authOverride
                if let awsOverride {
                    builtIn.aws = awsOverride
                }
                if let httpHeadersOverride {
                    var headers = builtIn.httpHeaders ?? [:]
                    headers.merge(httpHeadersOverride) { _, new in new }
                    builtIn.httpHeaders = headers
                }
                modelProviders[key] = builtIn
            }
        } else if modelProviders[key] == nil {
            modelProviders[key] = provider
        }
    }
    return .success(modelProviders)
}

public func createOssProvider(
    _ defaultProviderPort: UInt16,
    _ wireApi: WireApi
) -> ModelProviderInfo {
    let environment = ProcessInfo.processInfo.environment
    let defaultCodexOssBaseUrl: String = {
        let port: UInt16
        if let raw = environment["CODEX_OSS_PORT"],
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let parsed = UInt16(raw)
        {
            port = parsed
        } else {
            port = defaultProviderPort
        }
        return "http://localhost:\(port)/v1"
    }()
    let codexOssBaseUrl: String = {
        if let raw = environment["CODEX_OSS_BASE_URL"],
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return raw
        }
        return defaultCodexOssBaseUrl
    }()
    return createOssProviderWithBaseUrl(codexOssBaseUrl, wireApi)
}

public func createOssProviderWithBaseUrl(
    _ baseUrl: String,
    _ wireApi: WireApi
) -> ModelProviderInfo {
    ModelProviderInfo(
        name: "gpt-oss",
        baseUrl: baseUrl,
        wireApi: wireApi
    )
}

// MARK: - Helpers

func durationFromMilliseconds(_ milliseconds: UInt64) -> Duration {
    if milliseconds > UInt64(Int64.max) {
        return .milliseconds(Int64.max)
    }
    return .milliseconds(Int64(milliseconds))
}

func cargoPackageVersion() -> String {
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        !version.isEmpty
    {
        return version
    }
    return "0.0.0-sage"
}

func httpHeaderName(_ raw: String) -> String? {
    guard isToken(raw) else { return nil }
    return raw.lowercased()
}

func isHttpHeaderValue(_ value: String) -> Bool {
    value.utf8.allSatisfy { byte in
        byte == 9 || (byte >= 32 && byte <= 126)
    }
}

func isAbsoluteFilesystemPath(_ command: String) -> Bool {
    (command as NSString).isAbsolutePath
}

func isBareExecutableName(_ command: String) -> Bool {
    let last = (command as NSString).lastPathComponent
    return last == command && last != "." && last != ".." && !last.isEmpty && !command.contains("/")
}

func decodeNonZeroU64(
    _ value: UInt64,
    field: String,
    codingPath: [any CodingKey]
) throws -> UInt64 {
    guard value > 0 else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "invalid value: integer `0`, expected a nonzero u64 for \(field)"
            )
        )
    }
    return value
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

func rejectUnknownFields<Keys: CodingKey & CaseIterable>(
    in decoder: any Decoder,
    keys: Keys.Type,
    type: String
) throws {
    try rejectUnknownFields(
        in: decoder, allowedNames: Set(Keys.allCases.map(\.stringValue)), type: type)
}

func rejectUnknownFields(
    in decoder: any Decoder,
    allowedNames: Set<String>,
    type: String
) throws {
    let raw = try decoder.container(keyedBy: DynamicCodingKey.self)
    for key in raw.allKeys where !allowedNames.contains(key.stringValue) {
        let expected = allowedNames.sorted().joined(separator: ", ")
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "unknown field `\(key.stringValue)` for \(type), expected \(expected)"
            )
        )
    }
}

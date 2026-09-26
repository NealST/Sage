//
//  provider.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/provider.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `codex_client::{Provider, RetryConfig}` type-alias to
//  `CodexModelProviderInfo.{ApiProvider, ApiRetryConfig}` (fields match).
//

import CodexModelProviderInfo
import Foundation

public typealias Provider = ApiProvider
public typealias RetryConfig = ApiRetryConfig

public func isAzureResponsesProvider(name: String, baseUrl: String?) -> Bool {
    if name.caseInsensitiveCompare("azure") == .orderedSame {
        return true
    }
    if let baseUrl {
        return matchesAzureResponsesBaseUrl(baseUrl)
    }
    return false
}

func matchesAzureResponsesBaseUrl(_ baseUrl: String) -> Bool {
    let baseUrl = baseUrl.lowercased()
    let azureMarkers = [
        "openai.azure.",
        "cognitiveservices.azure.",
        "aoai.azure.",
        "azure-api.",
        "azurefd.",
        "windows.net/openai",
    ]
    return azureMarkers.contains { baseUrl.contains($0) }
}

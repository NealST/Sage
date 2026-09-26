//
//  hosted_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/hosted_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol

let WEB_SEARCH_TEXT_AND_IMAGE_CONTENT_TYPES = ["text", "image"]

struct WebSearchToolOptions {
    var webSearchMode: WebSearchMode?
    var webSearchConfig: WebSearchConfig?
    var webSearchToolType: WebSearchToolType
}

func createWebSearchTool(_ options: WebSearchToolOptions) -> ToolSpec? {
    let externalWebAccess: Bool
    let indexedWebAccess: Bool?
    switch options.webSearchMode {
    case .cached:
        externalWebAccess = false
        indexedWebAccess = nil
    case .indexed:
        externalWebAccess = true
        indexedWebAccess = true
    case .live:
        externalWebAccess = true
        indexedWebAccess = nil
    case .disabled, nil:
        return nil
    }
    let searchContentTypes: [String]?
    switch options.webSearchToolType {
    case .text:
        searchContentTypes = nil
    case .textAndImage:
        searchContentTypes = WEB_SEARCH_TEXT_AND_IMAGE_CONTENT_TYPES
    }
    return .webSearch(
        externalWebAccess: externalWebAccess,
        indexedWebAccess: indexedWebAccess,
        filters: nil,
        userLocation: nil,
        searchContextSize: options.webSearchConfig?.searchContextSize?.rawValue,
        searchContentTypes: searchContentTypes
    )
}

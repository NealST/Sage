//
//  web_search.swift
//  CodexCore
//
//  Port of codex-rs/core/src/web_search.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol

func searchActionDetail(query: String?, queries: [String]?) -> String {
    if let query, !query.isEmpty {
        return query
    }
    let first = queries?.first ?? ""
    if let queries, queries.count > 1, !first.isEmpty {
        return "\(first) ..."
    }
    return first
}

public func webSearchActionDetail(_ action: WebSearchAction) -> String {
    switch action {
    case .search(let query, let queries):
        return searchActionDetail(query: query, queries: queries)
    case .openPage(let url):
        return url ?? ""
    case .findInPage(let url, let pattern):
        switch (pattern, url) {
        case (let pattern?, let url?):
            return "'\(pattern)' in \(url)"
        case (let pattern?, nil):
            return "'\(pattern)'"
        case (nil, let url?):
            return url
        case (nil, nil):
            return ""
        }
    case .other:
        return ""
    }
}

//
//  model_request.swift
//  CodexCore
//
//  Port of codex-rs/core/src/model_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Extension crate types are local protocols. Interceptors wrap an
//  AsyncStream of ResponseEvent. parent_response_id is reserved.
//

import CodexAPI
import Foundation

public enum ModelRequestKind: Equatable, Sendable {
    case generation
    case compaction
    case memory
}

public protocol ModelResponseInterceptor: Sendable {
    func intercept(_ stream: AsyncStream<Result<ResponseEvent, ApiError>>)
        -> AsyncStream<Result<ResponseEvent, ApiError>>
}

public protocol ModelRequestContributor: Sendable {
    func request(
        kind: ModelRequestKind,
        threadId: String,
        model: String,
        clientMetadata: inout [String: String]?
    ) -> (any ModelResponseInterceptor)?
}

func prepareModelRequest(
    contributors: [any ModelRequestContributor],
    threadId: String,
    model: String,
    kind: ModelRequestKind,
    metadata: inout [String: String]?
) -> [any ModelResponseInterceptor] {
    contributors.compactMap { contributor in
        var additions: [String: String]?
        let interceptor = contributor.request(
            kind: kind, threadId: threadId, model: model, clientMetadata: &additions)
        if let additions {
            for (key, value) in filterExtraMetadata(additions) where key != "parent_response_id" {
                if metadata == nil { metadata = [:] }
                if metadata?[key] == nil {
                    metadata?[key] = value
                }
            }
        }
        return interceptor
    }
}

func interceptStream(
    _ stream: AsyncStream<Result<ResponseEvent, ApiError>>,
    interceptors: [any ModelResponseInterceptor]
) -> AsyncStream<Result<ResponseEvent, ApiError>> {
    interceptors.reduce(stream) { current, interceptor in
        interceptor.intercept(current)
    }
}

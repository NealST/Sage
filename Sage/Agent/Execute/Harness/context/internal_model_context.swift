//
//  internal_model_context.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/internal_model_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public let contextStartMarker = "<codex_internal_context"
public let contextEndMarker = "</codex_internal_context>"
public let legacyGoalContextStartMarker = "<goal_context>"
public let legacyGoalContextEndMarker = "</goal_context>"

public struct InvalidInternalContextSource: Error, Equatable, CustomStringConvertible {
    public var source: String
    public var description: String {
        "invalid internal model context source \(source); expected [a-z][a-z0-9_]*"
    }
}

public struct InternalContextSource: Equatable, Sendable {
    public var value: String

    public init(_ source: String) throws {
        guard Self.isValid(source) else {
            throw InvalidInternalContextSource(source: source)
        }
        value = source
    }

    public static func fromStatic(_ source: String) -> InternalContextSource {
        (try? InternalContextSource(source)) ?? InternalContextSource(unchecked: source)
    }

    private init(unchecked source: String) {
        value = source
    }

    public static func isValid(_ source: String) -> Bool {
        guard let first = source.unicodeScalars.first,
              first.value >= 97 && first.value <= 122
        else { return false }
        return source.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57)
                || scalar.value == 95
        }
    }
}

public struct InternalModelContextFragment: ContextualUserFragment, Equatable, Sendable {
    public var source: InternalContextSource
    public var rawBody: String

    public init(source: InternalContextSource, body: String) {
        self.source = source
        self.rawBody = body
    }

    public var contentKind: ContentItemKind {
        ContentItemKind("internal.\(source.value)")
    }

    public var role: String { "user" }
    public var openMarker: String { "\(contextStartMarker) source=\"\(source.value)\">" }
    public var closeMarker: String { contextEndMarker }
    public var body: String { rawBody }
}

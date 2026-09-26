//
//  turn_aborted.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/turn_aborted.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct TurnAborted: ContextualUserFragment, Equatable, Sendable {
    public static let interruptedGuidance =
        "The user interrupted the previous turn on purpose. Any running unified exec processes may still be running in the background. If any tools/commands were aborted, they may have partially executed."
    public static let interruptedDeveloperGuidance =
        "The previous turn was interrupted on purpose. Any running unified exec processes may still be running in the background. If any tools/commands were aborted, they may have partially executed."

    public var guidance: String
    public init(guidance: String) {
        self.guidance = guidance
    }
    public var contentKind: ContentItemKind { ContentItemKind("generic.turn_aborted") }
    public var role: String { "user" }
    public var openMarker: String { "<turn_aborted>" }
    public var closeMarker: String { "</turn_aborted>" }
    public var body: String { "\n\(guidance)\n" }
}

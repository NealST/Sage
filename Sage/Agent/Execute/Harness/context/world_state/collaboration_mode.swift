//
//  collaboration_mode.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/collaboration_mode.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct CollaborationModeState: Equatable, Sendable {
    public var mode: CollaborationMode?

    public init(mode: CollaborationMode? = nil) {
        self.mode = mode
    }

    public func snapshot() -> String? {
        guard let mode else { return nil }
        return mode.mode.rawValue
    }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let snapshot = snapshot(), snapshot != previous else { return nil }
        return InternalModelContextFragment(
            source: InternalContextSource.fromStatic("collaboration_mode"),
            body: "Collaboration mode: \(snapshot)"
        )
    }
}

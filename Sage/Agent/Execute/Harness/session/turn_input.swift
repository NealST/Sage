//
//  turn_input.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn_input.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Turn-start injection helpers. Full rollout reconstruction waits for
//  the remaining session loop.
//

import CodexCore
import CodexProtocol
import Foundation

enum TurnInputBuilder {
    static func user(_ content: [UserInput], clientId: String? = nil) -> SessionTurnInput {
        .userInput(content: content, clientId: clientId, metadata: UserInputMetadata())
    }

    static func responseItem(_ item: ResponseItem) -> SessionTurnInput {
        .responseItem(item)
    }

    static func functionCallOutput(_ item: ResponseItem) -> SessionTurnInput {
        .functionCallOutput(item)
    }
}

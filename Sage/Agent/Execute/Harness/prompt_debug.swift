//
//  prompt_debug.swift
//  CodexCore
//
//  Port of codex-rs/core/src/prompt_debug.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ThreadManager / ExtensionRegistry / AuthManager / exec-server wait for
//  Phase 7. This file keeps the session-local prompt assembly helper.
//

import CodexProtocol
import Foundation

public func buildPromptInputFromItems(
    history: [ResponseItem],
    userInput: [UserInput],
    modelInfo: ModelInfo
) -> [ResponseItem] {
    var items = history
    if !userInput.isEmpty {
        items.append(responseItemFromUserInput(userInput))
    }
    return items
}

func responseItemFromUserInput(_ input: [UserInput]) -> ResponseItem {
    let content: [ContentItem] = input.compactMap { item in
        switch item {
        case .text(let text, _):
            return .inputText(text: text)
        case .image(let image, let detail):
            return .inputImage(image: image, detail: detail ?? defaultImageDetail)
        case .audio(let audioUrl):
            return .inputAudio(audioUrl: audioUrl)
        default:
            return nil
        }
    }
    return .message(
        id: nil,
        role: "user",
        content: content,
        phase: nil,
        internalChatMessageMetadataPassthrough: nil
    )
}

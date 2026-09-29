//
//  event_mapping.swift
//  CodexCore
//
//  Port of codex-rs/core/src/event_mapping.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `parseTurnItem` maps assistant/user/reasoning/webSearch/imageGen.
//  Hook-prompt and full user-media parsing still wait.
//

import CodexProtocol
import Foundation

public func isContextualUserMessageContent(_ item: ResponseItem) -> Bool {
    isGuardianContextMessage(item)
}

public func isContextualDevMessageContent(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = item, role == "developer" else {
        return false
    }
    return content.contains(where: isContextualUserFragment)
}

public func hasNonContextualDevMessageContent(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = item, role == "developer" else {
        return false
    }
    return content.contains { !isContextualUserFragment($0) }
}

public func parseTurnItem(_ item: ResponseItem) -> TurnItem? {
    switch item {
    case .message(let id, let role, let content, let phase, _):
        switch role {
        case "assistant":
            return .agentMessage(parseAgentMessage(id: id?.asStr, content: content, phase: phase))
        case "user":
            if isContextualUserMessageContent(item) { return nil }
            let inputs: [UserInput] = content.compactMap { part in
                if case .inputText(let text) = part {
                    return .text(text: text, textElements: [])
                }
                return nil
            }
            guard !inputs.isEmpty else { return nil }
            return .userMessage(UserMessageItem(id: id?.asStr ?? "", content: inputs))
        default:
            return nil
        }
    case .reasoning(let id, let summary, let content, _, _):
        let summaryText = summary.map { entry -> String in
            if case .summaryText(let text) = entry { return text }
            return ""
        }
        let rawContent = (content ?? []).map { entry -> String in
            switch entry {
            case .reasoningText(let text), .text(let text):
                return text
            }
        }
        return .reasoning(ReasoningItem(
            id: id?.asStr ?? "",
            summaryText: summaryText,
            rawContent: rawContent
        ))
    case .webSearchCall(let id, _, let action, _):
        let resolved = action ?? .other
        return .webSearch(WebSearchItem(
            id: id?.asStr ?? "",
            query: webSearchActionDetail(resolved),
            action: resolved
        ))
    case .imageGenerationCall(let id, let status, let revisedPrompt, let result, _):
        guard let itemId = id?.asStr else { return nil }
        return .imageGeneration(ImageGenerationItem(
            id: itemId,
            status: status,
            revisedPrompt: revisedPrompt,
            result: result
        ))
    default:
        return nil
    }
}

func parseAgentMessage(id: String?, content: [ContentItem], phase: MessagePhase?) -> AgentMessageItem {
    let texts: [AgentMessageContent] = content.compactMap { part in
        switch part {
        case .inputText(let text), .outputText(let text):
            return .text(text: text)
        default:
            return nil
        }
    }
    return AgentMessageItem(
        id: id ?? "assistant",
        content: texts,
        phase: phase
    )
}

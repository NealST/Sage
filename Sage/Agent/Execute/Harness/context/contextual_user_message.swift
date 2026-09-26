//
//  contextual_user_message.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/contextual_user_message.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Skill-prompt matchers from the skills crate are omitted until Phase 9.
//

import CodexProtocol
import Foundation

public func isGuardianContextMessage(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = item, role == "user" else {
        return false
    }
    return content.contains(where: isContextualUserFragment)
        && UserGoalUpdate.messageText(item) == nil
}

public func isUserAuthorizationMessage(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, let metadata) = item, role == "user" else {
        return false
    }
    guard let kinds = metadata?.contentItemKinds else { return true }
    if kinds.isEmpty || kinds.count != content.count { return true }
    return kinds.contains { kind in
        kind.value.hasPrefix("user.")
            || kind.value.isEmpty
            || kind.value == "unknown"
            || kind.value == "images.preparation_error"
            || kind.value == "images.unsupported"
            || kind.value == "audio.unsupported"
    }
}

public func isContextualUserFragment(_ contentItem: ContentItem) -> Bool {
    guard case .inputText(let text) = contentItem else { return false }
    return parseHookPromptFragment(text) != nil || isStandardContextualUserText(text)
}

public func parseVisibleHookPromptMessage(
    id: String?,
    content: [ContentItem]
) -> HookPromptItem? {
    var fragments: [HookPromptFragment] = []
    for contentItem in content {
        guard case .inputText(let text) = contentItem else { return nil }
        if let fragment = parseHookPromptFragment(text) {
            fragments.append(fragment)
            continue
        }
        if isStandardContextualUserText(text) {
            continue
        }
        return nil
    }
    guard !fragments.isEmpty else { return nil }
    return HookPromptItem.fromFragments(id: id, fragments: fragments)
}

public func isStandardContextualUserText(_ text: String) -> Bool {
    UserInstructions(directory: nil, text: "").matchesText(text)
        || AdditionalContextUserFragment(key: "", value: "").matchesText(text)
        || AgentMessageBoardNotification(
            AgentMessageBoardPostPreview(
                author: "", channelName: "", messageId: "", threadId: "", textPreview: ""
            )
        ).matchesText(text)
        || ContextUserShellCommand(command: "", exitCode: 0, duration: 0, output: "").matchesText(text)
        || TurnAborted(guidance: "").matchesText(text)
        || InternalModelContextFragment(
            source: InternalContextSource.fromStatic("internal"),
            body: ""
        ).matchesText(text)
        || LegacyUnifiedExecProcessLimitWarning().matchesText(text)
        || LegacyApplyPatchExecCommandWarning().matchesText(text)
        || LegacyModelMismatchWarning().matchesText(text)
}

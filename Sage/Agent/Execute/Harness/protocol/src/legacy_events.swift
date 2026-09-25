//
//  legacy_events.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/legacy_events.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

/// Converts canonical item lifecycle events back into the legacy raw event stream.
public protocol HasLegacyEvent {
    func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg]
}

extension ContextCompactionItem {
    public func asLegacyEvent() -> EventMsg {
        .contextCompacted(ContextCompactedEvent())
    }
}

extension UserMessageItem {
    public func asLegacyUserMessageEvent() -> UserMessageEvent {
        var fileIds: [String] = []
        var fileIdDetails: [ImageDetail?] = []
        var imageOrder: [UserMessageImageKind] = []
        for input in content {
            if case .image(let image, let detail) = input {
                switch image {
                case .inline:
                    imageOrder.append(.inline)
                case .file(let fileId):
                    imageOrder.append(.file)
                    fileIds.append(fileId)
                    fileIdDetails.append(detail)
                }
            }
        }
        return UserMessageEvent(
            clientId: clientId,
            message: message(),
            images: imageUrls(),
            imageDetails: imageDetails(),
            fileIds: fileIds.isEmpty ? nil : fileIds,
            fileIdDetails: trimTrailingDefaultImageDetails(fileIdDetails),
            imageOrder: imageOrder,
            localImages: localImagePaths(),
            localImageDetails: localImageDetails(),
            audio: audioUrls(),
            localAudio: localAudioPaths(),
            textElements: textElements())
    }

    public func asLegacyEvent() -> EventMsg {
        .userMessage(asLegacyUserMessageEvent())
    }
}

extension AgentMessageItem {
    public func asLegacyEvents() -> [EventMsg] {
        content.map { part in
            switch part {
            case .text(let text):
                return EventMsg.agentMessage(
                    AgentMessageEvent(
                        message: text,
                        phase: phase,
                        memoryCitation: memoryCitation,
                        delivery: delivery,
                        questions: questions))
            }
        }
    }
}

extension EnteredReviewModeItem {
    public func asLegacyEvent(turnId: String) -> EventMsg {
        .enteredReviewMode(
            EnteredReviewModeEvent(
                target: target,
                userFacingHint: userFacingHint,
                turnId: turnId,
                itemId: id))
    }
}

extension ExitedReviewModeItem {
    public func asLegacyEvent(turnId: String) -> EventMsg {
        .exitedReviewMode(
            ExitedReviewModeEvent(
                turnId: turnId,
                itemId: id,
                reviewOutput: reviewOutput))
    }
}

extension ReasoningItem {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] {
        var events: [EventMsg] = []
        for summary in summaryText {
            events.append(.agentReasoning(AgentReasoningEvent(text: summary)))
        }
        if showRawAgentReasoning {
            for entry in rawContent {
                events.append(.agentReasoningRawContent(AgentReasoningRawContentEvent(text: entry)))
            }
        }
        return events
    }
}

extension CommandExecutionItem {
    func asLegacyBeginEvent(turnId: String, startedAtMs: Int64) -> EventMsg {
        .execCommandBegin(
            ExecCommandBeginEvent(
                callId: id,
                pluginId: pluginId,
                scriptPath: scriptPath,
                processId: processId,
                turnId: turnId,
                startedAtMs: startedAtMs,
                command: command,
                cwd: cwd,
                parsedCmd: parsedCmd,
                source: source,
                interactionInput: interactionInput))
    }

    func asLegacyEndEvent(turnId: String, completedAtMs: Int64) -> EventMsg? {
        let status: ExecCommandStatus
        switch self.status {
        case .inProgress: return nil
        case .completed: status = .completed
        case .failed: status = .failed
        case .declined: status = .declined
        }
        return .execCommandEnd(
            ExecCommandEndEvent(
                callId: id,
                pluginId: pluginId,
                scriptPath: scriptPath,
                processId: processId,
                turnId: turnId,
                completedAtMs: completedAtMs,
                command: command,
                cwd: cwd,
                parsedCmd: parsedCmd,
                source: source,
                interactionInput: interactionInput,
                stdout: stdout ?? "",
                stderr: stderr ?? "",
                aggregatedOutput: aggregatedOutput ?? "",
                exitCode: exitCode ?? 0,
                duration: duration ?? .zero,
                formattedOutput: formattedOutput ?? "",
                status: status))
    }
}

extension DynamicToolCallItem {
    func asLegacyRequestEvent(turnId: String, startedAtMs: Int64) -> EventMsg {
        .dynamicToolCallRequest(
            DynamicToolCallRequest(
                callId: id,
                turnId: turnId,
                startedAtMs: startedAtMs,
                namespace: namespace,
                tool: tool,
                arguments: arguments))
    }

    func asLegacyResponseEvent(turnId: String, completedAtMs: Int64) -> EventMsg? {
        if status == .inProgress { return nil }
        return .dynamicToolCallResponse(
            DynamicToolCallResponseEvent(
                callId: id,
                turnId: turnId,
                completedAtMs: completedAtMs,
                namespace: namespace,
                tool: tool,
                arguments: arguments,
                contentItems: contentItems ?? [],
                success: success ?? false,
                error: error,
                duration: duration ?? .zero))
    }
}

extension CollabAgentToolCallItem {
    func asLegacyBeginEvent(startedAtMs: Int64) -> EventMsg? {
        let receiverThreadId = receiverThreadIds.first
        switch tool {
        case .sendMessage, .followupTask, .interruptAgent, .listAgents:
            return nil
        case .spawnAgent:
            return .collabAgentSpawnBegin(
                CollabAgentSpawnBeginEvent(
                    callId: id,
                    startedAtMs: startedAtMs,
                    senderThreadId: senderThreadId,
                    prompt: prompt ?? "",
                    model: model ?? "",
                    reasoningEffort: reasoningEffort ?? .medium))
        case .sendInput:
            guard let receiverThreadId else { return nil }
            return .collabAgentInteractionBegin(
                CollabAgentInteractionBeginEvent(
                    callId: id,
                    startedAtMs: startedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadId: receiverThreadId,
                    prompt: prompt ?? ""))
        case .resumeAgent:
            guard let receiverThreadId else { return nil }
            let identity = receiverAgentIdentity(receiverThreadId)
            return .collabResumeBegin(
                CollabResumeBeginEvent(
                    callId: id,
                    startedAtMs: startedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadId: receiverThreadId,
                    receiverAgentNickname: identity.0,
                    receiverAgentRole: identity.1))
        case .wait:
            return .collabWaitingBegin(
                CollabWaitingBeginEvent(
                    startedAtMs: startedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadIds: receiverThreadIds,
                    receiverAgents: receiverAgents,
                    callId: id))
        case .closeAgent:
            guard let receiverThreadId else { return nil }
            return .collabCloseBegin(
                CollabCloseBeginEvent(
                    callId: id,
                    startedAtMs: startedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadId: receiverThreadId))
        }
    }

    func asLegacyEndEvent(completedAtMs: Int64) -> EventMsg? {
        if status == .inProgress { return nil }
        let receiverThreadId = receiverThreadIds.first
        switch tool {
        case .sendMessage, .followupTask, .interruptAgent, .listAgents:
            return nil
        case .spawnAgent:
            let identity = receiverThreadId.map { receiverAgentIdentity($0) } ?? (nil, nil)
            return .collabAgentSpawnEnd(
                CollabAgentSpawnEndEvent(
                    callId: id,
                    completedAtMs: completedAtMs,
                    senderThreadId: senderThreadId,
                    newThreadId: receiverThreadId,
                    newAgentNickname: identity.0,
                    newAgentRole: identity.1,
                    prompt: prompt ?? "",
                    model: model ?? "",
                    reasoningEffort: reasoningEffort ?? .medium,
                    status: receiverThreadId.map { agentStatus($0) } ?? .notFound))
        case .sendInput:
            guard let receiverThreadId else { return nil }
            let identity = receiverAgentIdentity(receiverThreadId)
            return .collabAgentInteractionEnd(
                CollabAgentInteractionEndEvent(
                    callId: id,
                    completedAtMs: completedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadId: receiverThreadId,
                    receiverAgentNickname: identity.0,
                    receiverAgentRole: identity.1,
                    prompt: prompt ?? "",
                    status: agentStatus(receiverThreadId)))
        case .resumeAgent:
            guard let receiverThreadId else { return nil }
            let identity = receiverAgentIdentity(receiverThreadId)
            return .collabResumeEnd(
                CollabResumeEndEvent(
                    callId: id,
                    completedAtMs: completedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadId: receiverThreadId,
                    receiverAgentNickname: identity.0,
                    receiverAgentRole: identity.1,
                    status: agentStatus(receiverThreadId)))
        case .wait:
            var statuses: [String: AgentStatus] = [:]
            for (threadId, status) in agentsStates {
                statuses[threadId.description] = status
            }
            return .collabWaitingEnd(
                CollabWaitingEndEvent(
                    senderThreadId: senderThreadId,
                    callId: id,
                    completedAtMs: completedAtMs,
                    agentStatuses: receiverAgents.map { agent in
                        CollabAgentStatusEntry(
                            threadId: agent.threadId,
                            agentNickname: agent.agentNickname,
                            agentRole: agent.agentRole,
                            status: agentStatus(agent.threadId))
                    },
                    statuses: statuses))
        case .closeAgent:
            guard let receiverThreadId else { return nil }
            let identity = receiverAgentIdentity(receiverThreadId)
            return .collabCloseEnd(
                CollabCloseEndEvent(
                    callId: id,
                    completedAtMs: completedAtMs,
                    senderThreadId: senderThreadId,
                    receiverThreadId: receiverThreadId,
                    receiverAgentNickname: identity.0,
                    receiverAgentRole: identity.1,
                    status: agentStatus(receiverThreadId)))
        }
    }

    func receiverAgentIdentity(_ threadId: ThreadId) -> (String?, String?) {
        let receiver = receiverAgents.first { $0.threadId == threadId }
        return (receiver?.agentNickname, receiver?.agentRole)
    }

    func agentStatus(_ threadId: ThreadId) -> AgentStatus {
        agentsStates[threadId] ?? .notFound
    }
}

extension SubAgentActivityItem {
    func asLegacyEvent(occurredAtMs: Int64) -> EventMsg {
        .subAgentActivity(
            SubAgentActivityEvent(
                eventId: id,
                occurredAtMs: occurredAtMs,
                agentThreadId: agentThreadId,
                agentPath: agentPath,
                kind: kind))
    }
}

extension WebSearchItem {
    public func asLegacyEvent() -> EventMsg {
        .webSearchEnd(
            WebSearchEndEvent(callId: id, query: query, action: action, results: results))
    }
}

extension ImageGenerationItem {
    public func asLegacyEvent() -> EventMsg {
        .imageGenerationEnd(
            ImageGenerationEndEvent(
                callId: id,
                status: status,
                revisedPrompt: revisedPrompt,
                result: result,
                savedPath: savedPath))
    }
}

extension FileChangeItem {
    public func asLegacyBeginEvent(turnId: String) -> EventMsg {
        .patchApplyBegin(
            PatchApplyBeginEvent(
                callId: id,
                turnId: turnId,
                autoApproved: autoApproved ?? false,
                changes: changes))
    }

    public func asLegacyEndEvent(turnId: String) -> EventMsg? {
        guard let status else { return nil }
        return .patchApplyEnd(
            PatchApplyEndEvent(
                callId: id,
                turnId: turnId,
                stdout: stdout ?? "",
                stderr: stderr ?? "",
                success: status == .completed,
                changes: changes,
                status: status))
    }
}

extension McpToolCallItem {
    public func asLegacyBeginEvent(turnId: String) -> EventMsg {
        .mcpToolCallBegin(
            McpToolCallBeginEvent(
                callId: id,
                turnId: turnId,
                invocation: McpInvocation(
                    server: server,
                    tool: tool,
                    arguments: arguments == .null ? nil : arguments),
                connectorId: connectorId,
                mcpAppResourceUri: mcpAppResourceUri,
                mcpAppUi: mcpAppUi,
                linkId: linkId,
                appName: appName,
                actionName: actionName,
                pluginId: pluginId,
                readOnlyHint: readOnlyHint))
    }

    public func asLegacyEndEvent(turnId: String) -> EventMsg? {
        let result: SerdeResult<CallToolResult>
        if let value = self.result {
            result = .success(value)
        } else if let error {
            result = .failure(error.message)
        } else {
            return nil
        }
        guard let duration else { return nil }
        return .mcpToolCallEnd(
            McpToolCallEndEvent(
                callId: id,
                turnId: turnId,
                invocation: McpInvocation(
                    server: server,
                    tool: tool,
                    arguments: arguments == .null ? nil : arguments),
                connectorId: connectorId,
                mcpAppResourceUri: mcpAppResourceUri,
                mcpAppUi: mcpAppUi,
                linkId: linkId,
                appName: appName,
                actionName: actionName,
                pluginId: pluginId,
                readOnlyHint: readOnlyHint,
                duration: duration,
                result: result))
    }
}

extension TurnItem {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] {
        switch self {
        case .userMessage(let item): return [item.asLegacyEvent()]
        case .functionCallOutput, .hookPrompt, .plan: return []
        case .agentMessage(let item): return item.asLegacyEvents()
        case .commandExecution, .dynamicToolCall, .collabAgentToolCall, .subAgentActivity:
            return []
        case .webSearch(let item): return [item.asLegacyEvent()]
        case .imageView(let item):
            return [.viewImageToolCall(ViewImageToolCallEvent(callId: item.id, path: item.path))]
        case .extension: return []
        case .imageGeneration(let item): return [item.asLegacyEvent()]
        case .enteredReviewMode, .exitedReviewMode: return []
        case .fileChange(let item):
            return item.asLegacyEndEvent(turnId: "").map { [$0] } ?? []
        case .mcpToolCall(let item):
            return item.asLegacyEndEvent(turnId: "").map { [$0] } ?? []
        case .reasoning(let item):
            return item.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        case .contextCompaction(let item):
            return [item.asLegacyEvent()]
        }
    }
}

extension ItemStartedEvent: HasLegacyEvent {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] {
        switch item {
        case .webSearch(let item):
            return [.webSearchBegin(WebSearchBeginEvent(callId: item.id))]
        case .imageView:
            return []
        case .imageGeneration(let item):
            return [.imageGenerationBegin(ImageGenerationBeginEvent(callId: item.id))]
        case .fileChange(let item):
            return [item.asLegacyBeginEvent(turnId: turnId)]
        case .mcpToolCall(let item):
            return [item.asLegacyBeginEvent(turnId: turnId)]
        case .commandExecution(let item):
            return [item.asLegacyBeginEvent(turnId: turnId, startedAtMs: startedAtMs)]
        case .dynamicToolCall(let item):
            return [item.asLegacyRequestEvent(turnId: turnId, startedAtMs: startedAtMs)]
        case .collabAgentToolCall(let item):
            return item.asLegacyBeginEvent(startedAtMs: startedAtMs).map { [$0] } ?? []
        default:
            return []
        }
    }
}

extension ItemCompletedEvent: HasLegacyEvent {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] {
        switch item {
        case .mcpToolCall(let item):
            return item.asLegacyEndEvent(turnId: turnId).map { [$0] } ?? []
        case .fileChange(let item):
            return item.asLegacyEndEvent(turnId: turnId).map { [$0] } ?? []
        case .commandExecution(let item):
            return item.asLegacyEndEvent(turnId: turnId, completedAtMs: completedAtMs).map { [$0] } ?? []
        case .dynamicToolCall(let item):
            return item.asLegacyResponseEvent(turnId: turnId, completedAtMs: completedAtMs).map { [$0] } ?? []
        case .collabAgentToolCall(let item):
            return item.asLegacyEndEvent(completedAtMs: completedAtMs).map { [$0] } ?? []
        case .subAgentActivity(let item):
            return [item.asLegacyEvent(occurredAtMs: completedAtMs)]
        case .enteredReviewMode(let item):
            return [item.asLegacyEvent(turnId: turnId)]
        case .exitedReviewMode(let item):
            return [item.asLegacyEvent(turnId: turnId)]
        default:
            return item.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        }
    }
}

extension AgentMessageContentDeltaEvent: HasLegacyEvent {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] { [] }
}

extension ReasoningContentDeltaEvent: HasLegacyEvent {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] { [] }
}

extension ReasoningRawContentDeltaEvent: HasLegacyEvent {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] { [] }
}

extension EventMsg: HasLegacyEvent {
    public func asLegacyEvents(showRawAgentReasoning: Bool) -> [EventMsg] {
        switch self {
        case .itemStarted(let event):
            return event.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        case .itemCompleted(let event):
            return event.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        case .agentMessageContentDelta(let event):
            return event.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        case .reasoningContentDelta(let event):
            return event.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        case .reasoningRawContentDelta(let event):
            return event.asLegacyEvents(showRawAgentReasoning: showRawAgentReasoning)
        default:
            return []
        }
    }
}

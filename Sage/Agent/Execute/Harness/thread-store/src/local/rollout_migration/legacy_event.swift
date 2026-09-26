//
//  legacy_event.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/legacy_event.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Frozen event → TurnItem mapping. ImageGeneration writes `TurnItem.imageGeneration`
//  (Swift items crate) rather than `ExtensionItem::ImageGeneration`. EventMsg
//  cases that are still unported fall through to `nil`.
//

import CodexProtocol
import Foundation

func userMessageItem(
    _ event: UserMessageEvent,
    nextItemId: () throws -> String
) throws -> TurnItem {
    var content: [UserInput] = []
    let hasImageOrder = event.hasCompleteImageOrder()
    if !event.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        content.append(.text(text: event.message, textElements: event.textElements))
    }
    if hasImageOrder {
        var inlineIndex = 0
        var fileIndex = 0
        for imageKind in event.imageOrder {
            switch imageKind {
            case .inline:
                guard let images = event.images, inlineIndex < images.count else { continue }
                let detail = event.imageDetails.indices.contains(inlineIndex)
                    ? event.imageDetails[inlineIndex] : nil
                content.append(.image(image: .inline(imageUrl: images[inlineIndex]), detail: detail))
                inlineIndex += 1
            case .file:
                guard let fileIds = event.fileIds, fileIndex < fileIds.count else { continue }
                let detail = event.fileIdDetails.indices.contains(fileIndex)
                    ? event.fileIdDetails[fileIndex] : nil
                content.append(.image(image: .file(fileId: fileIds[fileIndex]), detail: detail))
                fileIndex += 1
            }
        }
    } else if let images = event.images {
        for (index, imageUrl) in images.enumerated() {
            let detail = event.imageDetails.indices.contains(index)
                ? event.imageDetails[index] : nil
            content.append(.image(image: .inline(imageUrl: imageUrl), detail: detail))
        }
    }
    if !hasImageOrder, let fileIds = event.fileIds {
        for (index, fileId) in fileIds.enumerated() {
            let detail = event.fileIdDetails.indices.contains(index)
                ? event.fileIdDetails[index] : nil
            content.append(.image(image: .file(fileId: fileId), detail: detail))
        }
    }
    for (index, path) in event.localImages.enumerated() {
        let detail = event.localImageDetails.indices.contains(index)
            ? event.localImageDetails[index] : nil
        content.append(.localImage(path: path, detail: detail))
    }
    if let audio = event.audio {
        content.append(contentsOf: audio.map { UserInput.audio(audioUrl: $0) })
    }
    content.append(contentsOf: event.localAudio.map { UserInput.localAudio(path: $0) })
    return .userMessage(UserMessageItem(id: try nextItemId(), clientId: event.clientId, content: content))
}

func completedItem(
    _ event: EventMsg,
    nextItemId: () throws -> String
) throws -> (TurnItem, String?)? {
    switch event {
    case .agentMessage(let event) where !event.message.isEmpty:
        return (
            .agentMessage(AgentMessageItem(
                id: try nextItemId(),
                content: [.text(text: event.message)],
                phase: event.phase,
                memoryCitation: event.memoryCitation,
                delivery: event.delivery,
                questions: event.questions
            )),
            nil
        )
    case .patchApplyEnd(let event):
        return (
            .fileChange(FileChangeItem(
                id: event.callId,
                changes: event.changes,
                status: event.status,
                autoApproved: nil,
                stdout: event.stdout.isEmpty ? nil : event.stdout,
                stderr: event.stderr.isEmpty ? nil : event.stderr
            )),
            event.turnId.isEmpty ? nil : event.turnId
        )
    case .mcpToolCallEnd(let event):
        let result: CallToolResult?
        let error: McpToolCallError?
        switch event.result {
        case .success(let value):
            result = value
            error = nil
        case .failure(let message):
            result = nil
            error = McpToolCallError(message: message)
        }
        return (
            .mcpToolCall(McpToolCallItem(
                id: event.callId,
                server: event.invocation.server,
                tool: event.invocation.tool,
                arguments: event.invocation.arguments ?? .null,
                connectorId: event.connectorId,
                mcpAppResourceUri: event.mcpAppResourceUri,
                mcpAppUi: event.mcpAppUi,
                linkId: event.linkId,
                appName: event.appName,
                actionName: event.actionName,
                pluginId: event.pluginId,
                readOnlyHint: event.readOnlyHint,
                status: event.isSuccess ? .completed : .failed,
                result: result,
                error: error,
                duration: event.duration
            )),
            event.turnId.isEmpty ? nil : event.turnId
        )
    case .webSearchEnd(let event):
        return (
            .webSearch(WebSearchItem(
                id: event.callId,
                query: event.query,
                action: event.action,
                results: event.results
            )),
            nil
        )
    case .imageGenerationEnd(let event):
        return (
            .imageGeneration(ImageGenerationItem(
                id: event.callId,
                status: event.status,
                revisedPrompt: event.revisedPrompt,
                result: event.result,
                savedPath: event.savedPath
            )),
            nil
        )
    case .contextCompacted:
        return (.contextCompaction(ContextCompactionItem(id: try nextItemId())), nil)
    case .enteredReviewMode(let event):
        let enteredId: String
        if let itemId = event.itemId {
            enteredId = itemId
        } else {
            enteredId = try nextItemId()
        }
        return (
            .enteredReviewMode(EnteredReviewModeItem(
                id: enteredId,
                target: event.target,
                userFacingHint: event.userFacingHint ?? "Review requested."
            )),
            event.turnId
        )
    case .exitedReviewMode(let event):
        let exitedId: String
        if let itemId = event.itemId {
            exitedId = itemId
        } else {
            exitedId = try nextItemId()
        }
        return (
            .exitedReviewMode(ExitedReviewModeItem(
                id: exitedId,
                reviewOutput: event.reviewOutput
            )),
            event.turnId
        )
    case .subAgentActivity(let event):
        return (
            .subAgentActivity(SubAgentActivityItem(
                id: event.eventId,
                kind: event.kind,
                agentThreadId: event.agentThreadId,
                agentPath: event.agentPath
            )),
            nil
        )
    case .execCommandEnd(let event):
        return (
            .commandExecution(CommandExecutionItem(
                sandboxType: nil,
                modelContext: nil,
                id: event.callId,
                pluginId: event.pluginId,
                scriptPath: event.scriptPath,
                processId: event.processId,
                command: event.command,
                cwd: event.cwd,
                parsedCmd: event.parsedCmd,
                source: event.source,
                interactionInput: event.interactionInput,
                status: CommandExecutionStatus(event.status),
                stdout: event.stdout.isEmpty ? nil : event.stdout,
                stderr: event.stderr.isEmpty ? nil : event.stderr,
                aggregatedOutput: event.aggregatedOutput.isEmpty ? nil : event.aggregatedOutput,
                exitCode: event.exitCode,
                duration: event.duration,
                formattedOutput: event.formattedOutput.isEmpty ? nil : event.formattedOutput
            )),
            event.turnId
        )
    case .dynamicToolCallResponse(let event):
        return (
            .dynamicToolCall(DynamicToolCallItem(
                id: event.callId,
                namespace: event.namespace,
                tool: event.tool,
                arguments: event.arguments,
                status: event.success ? .completed : .failed,
                contentItems: event.contentItems,
                success: event.success,
                error: event.error,
                duration: event.duration
            )),
            event.turnId
        )
    default:
        return nil
    }
}

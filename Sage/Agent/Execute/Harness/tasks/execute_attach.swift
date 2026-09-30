//
//  execute_attach.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  Maps AgentSessionState events onto a harness Session so RegularTask
//  can attach rust RegularTask → runTurn without switching the live
//  ExecuteTurnLoop until `useHarnessRunTurn` is set.
//

import CodexCore
import CodexProtocol
import Foundation

enum ExecuteHarnessAttach {
    struct Snapshot: Equatable, Sendable {
        var history: [ResponseItem]
        var input: [SessionTurnInput]
        var cwd: String
        var model: String
        var allowsMutation: Bool
    }

    static func snapshot(
        events: [AgentEvent],
        cwd: String,
        model: String,
        allowsMutation: Bool = false
    ) -> Snapshot {
        let lastUserIndex = events.lastIndex(where: { $0.kind == .userInput })
        let prior: ArraySlice<AgentEvent>
        let turnEvent: AgentEvent?
        if let lastUserIndex {
            prior = events[..<lastUserIndex]
            turnEvent = events[lastUserIndex]
        } else {
            prior = events[...]
            turnEvent = nil
        }
        return Snapshot(
            history: prior.flatMap(responseItems(from:)),
            input: turnEvent.map { [TurnInputBuilder.user(userContents(from: $0))] } ?? [],
            cwd: cwd,
            model: model,
            allowsMutation: allowsMutation
        )
    }

    static func makeSession(history: [ResponseItem]) -> Session {
        let session = Session()
        if !history.isEmpty {
            session.state.recordItems(history)
        }
        return session
    }

    static func makeTurnContext(cwd: String, model: String, allowsMutation: Bool) -> TurnContext {
        TurnContext(
            cwd: cwd,
            model: model,
            sandboxPolicy: allowsMutation
                ? .workspaceWrite(
                    writableRoots: [],
                    networkAccess: true,
                    excludeTmpdirEnvVar: false,
                    excludeSlashTmp: false
                )
                : .readOnly(networkAccess: false),
            permissionProfile: allowsMutation ? .workspaceWrite() : .readOnly(),
            environment: TurnEnvironment(cwd: cwd)
        )
    }

    static func samplingResult(from turn: ModelTurn) throws -> SamplingRequestResult {
        if !turn.toolCalls.isEmpty {
            throw CodexErr.fatal("use responseStream(from:) so runTurn can dispatch tools")
        }
        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: text)
    }

    static func responseStream(from turn: ModelTurn) -> ResponseStream {
        var events: [CodexResult<ResponseEvent>] = []
        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            events.append(
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: text)],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                )))
            )
        }
        for call in turn.toolCalls {
            events.append(
                .success(.outputItemDone(.functionCall(
                    id: nil,
                    name: call.name,
                    namespace: nil,
                    arguments: call.argumentsJSON,
                    encryptedFunctionArgs: nil,
                    callId: call.id,
                    internalChatMessageMetadataPassthrough: nil
                )))
            )
        }
        events.append(
            .success(.completed(
                responseId: "sage-execute",
                tokenUsage: nil,
                usageMetadata: nil,
                endTurn: true
            ))
        )
        return makeResponseStream(events)
    }

    static func responseItems(from event: AgentEvent) -> [ResponseItem] {
        switch event.kind {
        case .systemInstruction:
            return []
        case .userInput:
            return [
                .message(
                    id: nil,
                    role: "user",
                    content: userContents(from: event).map(contentItem(from:)),
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ),
            ]
        case .assistantResponse:
            var items: [ResponseItem] = []
            let text = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                items.append(
                    .message(
                        id: nil,
                        role: "assistant",
                        content: [.outputText(text: text)],
                        phase: nil,
                        internalChatMessageMetadataPassthrough: nil
                    )
                )
            }
            for call in event.toolCalls ?? [] {
                items.append(
                    .functionCall(
                        id: nil,
                        name: call.name,
                        namespace: nil,
                        arguments: call.argumentsJSON,
                        encryptedFunctionArgs: nil,
                        callId: call.id,
                        internalChatMessageMetadataPassthrough: nil
                    )
                )
            }
            return items
        case .toolResult:
            return [
                .functionCallOutput(
                    id: nil,
                    callId: event.toolCallID,
                    name: nil,
                    namespace: nil,
                    output: .fromText(event.content),
                    internalChatMessageMetadataPassthrough: nil
                ),
            ]
        }
    }

    static func userContents(from event: AgentEvent) -> [UserInput] {
        var contents: [UserInput] = []
        let text = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            contents.append(.text(text: event.content, textElements: []))
        }
        for attachment in event.attachments {
            switch attachment.kind {
            case .image:
                contents.append(.localImage(path: attachment.path, detail: nil))
            case .file, .folder:
                contents.append(.text(text: attachment.promptLine, textElements: []))
            }
        }
        if contents.isEmpty {
            contents.append(.text(text: event.content, textElements: []))
        }
        return contents
    }

    private static func contentItem(from input: UserInput) -> ContentItem {
        switch input {
        case .text(let text, _):
            return .inputText(text: text)
        case .localImage(let path, _):
            return .inputText(text: path)
        default:
            return .inputText(text: String(describing: input))
        }
    }
}

//
//  RecallTaskTranscriptTool.swift
//  Sage
//
//  Reloads folded transcript events for the current task.
//

import Foundation

/// Current-task context for recall. Set around tool dispatch.
enum ActiveTaskContext {
    @TaskLocal
    static var repository: (any TaskRepository)?
    @TaskLocal
    static var taskID: UUID?
}

/// Loads exact prior turns that working memory only summarized.
nonisolated enum RecallTaskTranscriptTool {
    static let name = "recall_task_transcript"
    static let maxOutputCharacters = 12_000
    static let maxEventCharacters = 2_000

    static let definition = ToolDefinition(
        name: name,
        description: """
        Reload exact prior turns from the current task when working memory only has a summary. \
        Use this for original tool output, code, or error text. \
        from_event_id and through_event_id are UUIDs from the working-memory appendix \
        (inclusive). Only the active task is readable. Output is capped — narrow the range if truncated.
        """,
        parameters: .schemaObject(
            properties: [
                "from_event_id": .stringProperty("UUID of the first event to reload (inclusive)."),
                "through_event_id": .stringProperty("UUID of the last event to reload (inclusive)."),
            ],
            required: ["from_event_id", "through_event_id"]
        )
    )

    private struct Args: Decodable {
        var fromEventID: String
        var throughEventID: String
    }

    static func execute(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        guard let fromID = UUID(uuidString: args.fromEventID.trimmingCharacters(in: .whitespacesAndNewlines)),
              let throughID = UUID(uuidString: args.throughEventID.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw ToolError.invalidArguments(
                "from_event_id and through_event_id must be UUIDs from the working-memory appendix."
            )
        }
        guard let repository = ActiveTaskContext.repository,
              let taskID = ActiveTaskContext.taskID
        else {
            throw ToolError.operationFailed(
                "Transcript recall is unavailable in this context. Stay on the current task and retry."
            )
        }

        guard let task = try await repository.loadTask(id: taskID) else {
            throw ToolError.operationFailed("The current task is gone. Continue without the recalled turns.")
        }

        var fromIndex = task.events.firstIndex(where: { $0.id == fromID })
        var throughIndex = task.events.firstIndex(where: { $0.id == throughID })
        if fromIndex == nil || throughIndex == nil {
            throw ToolError.operationFailed(
                "Those event IDs are not on the current task. Use the IDs printed in working memory."
            )
        }
        if let start = fromIndex, let end = throughIndex, start > end {
            swap(&fromIndex, &throughIndex)
        }
        let slice = Array(task.events[fromIndex!...throughIndex!])
        guard !slice.isEmpty else {
            return "(no events in that range)"
        }

        var lines: [String] = []
        for event in slice {
            let line = format(event)
            guard !line.isEmpty else { continue }
            lines.append(line)
        }
        var output = lines.joined(separator: "\n\n")
        if output.utf8.count > maxOutputCharacters {
            output = ContextBudget.middleOut(output, maxUTF8Bytes: maxOutputCharacters)
                + "\n\n… (recall truncated — request a narrower from_event_id/through_event_id range)"
        }
        return output
    }

    private static func format(_ event: AgentEvent) -> String {
        let body: String
        switch event.kind {
        case .systemInstruction:
            return ""
        case .userInput:
            body = event.content
            return "[\(event.id.uuidString)] user:\n\(clip(body))"
        case .assistantResponse:
            var text = event.content
            if let calls = event.toolCalls, !calls.isEmpty {
                let names = calls.map(\.name).joined(separator: ", ")
                if !text.isEmpty { text += "\n" }
                text += "tool_calls: \(names)"
            }
            return "[\(event.id.uuidString)] assistant:\n\(clip(text))"
        case .toolResult:
            let name = event.toolCallID.map { " tool_call_id=\($0)" } ?? ""
            let content = WriteFileResultCodec.modelFacing(event.content)
            return "[\(event.id.uuidString)] tool\(name):\n\(clip(content))"
        }
    }

    private static func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count > maxEventCharacters else { return trimmed }
        return ContextBudget.middleOut(trimmed, maxUTF8Bytes: maxEventCharacters)
    }
}

//
//  SkillExtractionService+Compose.swift
//  Sage
//

import Foundation

extension SkillExtractionService {
    // MARK: - Composition Helpers

    func requireTranscript(from task: TaskRecord) throws -> String {
        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else {
            throw SkillCompositionError.emptyTranscript
        }
        return transcript
    }

    func completeCompose(
        systemPrompt: String,
        userPrompt: String,
        settings: ModelSettingsSnapshot
    ) async throws -> SkillDraft {
        let events: [AgentEvent] = [
            AgentEvent(kind: .systemInstruction, content: systemPrompt),
            AgentEvent(kind: .userInput, content: userPrompt),
        ]

        do {
            let turn = try await modelClient.complete(
                events: events,
                tools: [],
                settings: settings,
                retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1.0, maxDelay: 10.0)
            )
            guard let content = turn.content else {
                throw SkillCompositionError.invalidResponse
            }
            return try parseComposeResponse(content)
        } catch let error as SkillCompositionError {
            throw error
        } catch {
            throw SkillCompositionError.modelFailed(error.localizedDescription)
        }
    }

    // MARK: - Transcript Building

    /// Extracts a concise transcript from task events, focusing on key interactions.
    func buildTranscript(from task: TaskRecord) -> String {
        var lines: [String] = []
        var totalLength = 0
        let maxLength = 6_000
        let separatorLength = 1 // "\n"

        for event in task.events {
            let prefix: String
            switch event.kind {
            case .userInput:
                prefix = "User"

            case .assistantResponse:
                prefix = "Assistant"

            case .toolResult:
                prefix = "Tool Result"

            case .systemInstruction:
                continue
            }

            let contentPreview: String
            if event.kind == .toolResult && event.content.count > 500 {
                contentPreview = String(event.content.prefix(500)) + "…[truncated]"
            } else {
                contentPreview = event.content
            }

            let line: String
            if let toolCalls = event.toolCalls, !toolCalls.isEmpty {
                let callSummaries = toolCalls.map { "[\($0.name)]" }.joined(separator: ", ")
                line = "\(prefix) (calls: \(callSummaries)): \(contentPreview)"
            } else {
                line = "\(prefix): \(contentPreview)"
            }

            if !lines.isEmpty {
                totalLength += separatorLength
            }
            lines.append(line)
            totalLength += line.count

            if totalLength > maxLength {
                let keep = max(lines.count / 2, 1)
                let dropped = lines.prefix(lines.count - keep)
                let droppedLength = dropped.reduce(0) { $0 + $1.count } + dropped.count * separatorLength
                lines = Array(lines.suffix(keep))
                let marker = "[...earlier conversation truncated...]"
                lines.insert(marker, at: 0)
                totalLength = totalLength - droppedLength + marker.count + separatorLength
            }
        }

        return lines.joined(separator: "\n")
    }

    func parseResponse(_ content: String) -> SkillExtractionResult {
        SkillExtractionParsing.parseResponse(content)
    }

    func parseComposeResponse(_ content: String) throws -> SkillDraft {
        try SkillExtractionParsing.parseComposeResponse(content)
    }
}

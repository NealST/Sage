//
//  TurnChangeSet.swift
//  Sage
//
//  In-memory book for the current execute→review cycle.
//

import Foundation

@MainActor
final class TurnChangeSet {
    private var book = WorkspaceChangeBook()
    private var started = false

    func beginIfNeeded(replaying events: [AgentEvent] = []) {
        guard !started else { return }
        started = true
        let start = events.lastIndex { $0.kind == .userInput } ?? events.startIndex
        for event in events[start...] where event.kind == .toolResult {
            guard !event.content.hasPrefix("ERROR:") else { continue }
            if let payload = WriteFileResultCodec.payload(in: event.content) {
                book.applyWrite(
                    path: payload.path,
                    before: payload.before,
                    after: payload.after,
                    created: payload.created
                )
            }
        }
    }

    func reset() {
        book.reset()
        started = false
    }

    func record(
        toolName: String,
        argumentsJSON: String,
        result: String,
        succeeded: Bool = true
    ) {
        if !started {
            started = true
        }
        TurnChangeSetRecording.apply(
            toolName: toolName,
            argumentsJSON: argumentsJSON,
            result: result,
            succeeded: succeeded,
            to: &book
        )
    }

    func snapshot() -> WorkspaceChangeSet {
        book.snapshot()
    }

    func reviewBrief(maxChars: Int = 12_000) -> String {
        book.snapshot().reviewBrief(maxChars: maxChars)
    }
}

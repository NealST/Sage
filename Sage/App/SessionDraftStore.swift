//
//  SessionDraftStore.swift
//  Sage
//
//  Composer draft + queued mid-turn inputs persisted per session scope so an
//  unsent message survives a quit or a project-window close. Plain JSON files
//  (payloads are tiny); debounced scheduling lives in `AgentSession`.
//

import Foundation

nonisolated struct PersistedQueuedTurn: Codable, Sendable, Equatable {
    var text: String
    var attachments: [MessageAttachment]
}

nonisolated struct PersistedTurnInput: Codable, Sendable, Equatable {
    var queuedItems: [PersistedQueuedTurn] = []

    var isEmpty: Bool { queuedItems.isEmpty }
}

nonisolated struct SessionDraftPayload: Codable, Sendable, Equatable {
    var draft: String = ""
    var draftAttachments: [MessageAttachment] = []
    /// Queued turn input keyed by task UUID string — the active thread's queue
    /// plus queues parked on other threads.
    var turnInputByTask: [String: PersistedTurnInput] = [:]

    var isEmpty: Bool {
        draft.isEmpty
            && draftAttachments.isEmpty
            && turnInputByTask.values.allSatisfy(\.isEmpty)
    }
}

@MainActor
final class SessionDraftStore {
    private let fileURL: URL

    init(scopeKey: String) {
        fileURL = AppSupportPaths.sessionDraftsDirectory()
            .appendingPathComponent("\(scopeKey).json")
    }

    func load() -> SessionDraftPayload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SessionDraftPayload.self, from: data)
    }

    func save(_ payload: SessionDraftPayload) {
        // An empty payload is indistinguishable from no draft at all.
        guard !payload.isEmpty else {
            discard()
            return
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func discard() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

//
//  ChatSession.swift
//  Sage
//

import Foundation

struct ChatSession: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var pendingPlan: AgentPlan?
    var updatedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        pendingPlan: AgentPlan? = nil,
        updatedAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.pendingPlan = pendingPlan
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    var preview: String {
        messages.last(where: { $0.role == .user || $0.role == .assistant })?.content
            ?? "Empty chat"
    }
}

struct SessionLibrarySnapshot: Codable, Sendable {
    var sessions: [ChatSession]
    var activeSessionID: UUID?
}

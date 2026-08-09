//
//  ProjectRecord.swift
//  Sage
//

import Foundation

/// A code project: isolation boundary for tasks, tools, and routing.
/// Distinct from `TaskWorkspaceSnapshot` / `AgentWorkspaceView` naming.
nonisolated struct ProjectRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    /// Standardized absolute path (symlink-resolved at open/create time).
    var rootPath: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
    var lastActiveTaskID: UUID?

    var rootURL: URL {
        URL(fileURLWithPath: rootPath)
    }

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date = .now,
        lastActiveTaskID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastActiveTaskID = lastActiveTaskID
    }
}

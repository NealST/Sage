//
//  GRDBTaskRepository+Writes.swift
//  Sage
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    // MARK: - Writes

    func updateTopic(
        taskID: UUID,
        topic: String,
        abstract: String,
        topicUpdatedAt: Date
    ) throws {
        let pool = try database()
        try pool.write { database in
            try database.execute(
                sql: """
                UPDATE tasks
                SET topic = ?,
                    abstract = ?,
                    topic_updated_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    topic,
                    abstract,
                    topicUpdatedAt.timeIntervalSince1970,
                    topicUpdatedAt.timeIntervalSince1970,
                    taskID.uuidString,
                ]
            )
        }
    }

    func updateWorkingMemory(taskID: UUID, memory: TaskWorkingMemory?) throws {
        let pool = try database()
        let json: String?
        if let memory, memory.hasContent {
            json = (try? JSONEncoder().encode(memory))
                .flatMap { String(data: $0, encoding: .utf8) }
        } else {
            json = nil
        }
        try pool.write { database in
            try database.execute(
                sql: """
                UPDATE tasks
                SET working_memory_json = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    json,
                    Date.now.timeIntervalSince1970,
                    taskID.uuidString,
                ]
            )
        }
    }

    func updateTodoList(taskID: UUID, items: [AgentTodoItem]) throws {
        let pool = try database()
        let json: String? = items.isEmpty
            ? nil
            : (try? JSONEncoder().encode(items))
                .flatMap { String(data: $0, encoding: .utf8) }
        try pool.write { database in
            try database.execute(
                sql: """
                UPDATE tasks
                SET todo_list_json = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    json,
                    Date.now.timeIntervalSince1970,
                    taskID.uuidString,
                ]
            )
        }
    }

    func updateUnlockedMCPServers(taskID: UUID, names: Set<String>) throws {
        let pool = try database()
        let json: String? = names.isEmpty
            ? nil
            : (try? JSONEncoder().encode(names.sorted()))
                .flatMap { String(data: $0, encoding: .utf8) }
        try pool.write { database in
            try database.execute(
                sql: """
                UPDATE tasks
                SET unlocked_mcp_servers_json = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    json,
                    Date.now.timeIntervalSince1970,
                    taskID.uuidString,
                ]
            )
        }
    }

    func deleteTask(id: UUID) throws {
        let pool = try database()
        try pool.write { database in
            try database.execute(
                sql: "DELETE FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func pruneManagedAttachmentCopies(_ candidates: [MessageAttachment]) async throws {
        let managed = candidates.filter { attachment in
            attachment.isEphemeralCopy && MessageAttachment.isManagedCopyURL(attachment.fileURL)
        }
        guard !managed.isEmpty else { return }
        let pool = try database()
        let referencedPaths = try await pool.read { database in
            var paths = Set<String>()
            for path in Set(managed.map(\.path)) {
                let count = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM event_attachments WHERE path = ?",
                    arguments: [path]
                ) ?? 0
                if count > 0 { paths.insert(path) }
            }
            return paths
        }
        MessageAttachment.deleteManagedCopies(
            managed.filter { !referencedPaths.contains($0.path) }
        )
    }
}

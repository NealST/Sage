//
//  ManageTodoListTool.swift
//  Sage
//
//  Task-scoped checklist the execute agent updates as it works.
//

import Foundation

nonisolated struct AgentTodoItem: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable {
        case notStarted = "not-started"
        case inProgress = "in-progress"
        case completed
    }

    var id: Int
    var title: String
    var status: Status
}

nonisolated enum ManageTodoListTool {
    static let name = "manage_todo_list"

    static let definition = ToolDefinition(
        name: name,
        description: """
        Replace the current task's todo list. Always send the complete list (existing + new). \
        Track remaining execute steps against the confirmed work plan — do not restate the plan. \
        Use only for multi-step act work. At most one item may be in-progress. \
        Send an empty list to clear the todos. Titles should be 3–7 words. \
        Returns the list as one line per item: status<TAB>id<TAB>title.
        """,
        parameters: .schemaObject(
            properties: [
                "todo_list": .object([
                    "type": .string("array"),
                    "description": .string("Complete array of all todo items."),
                    "items": .schemaObject(
                        properties: [
                            "id": .intProperty("Unique sequential id starting at 1."),
                            "title": .stringProperty("Concise action-oriented label (3–7 words)."),
                            "status": .object([
                                "type": .string("string"),
                                "enum": .array([
                                    .string("not-started"),
                                    .string("in-progress"),
                                    .string("completed"),
                                ]),
                                "description": .string(
                                    "not-started: not begun | in-progress: currently working (max 1) | completed: finished"
                                ),
                            ]),
                        ],
                        required: ["id", "title", "status"]
                    ),
                ]),
            ],
            required: ["todo_list"]
        ),
        requiresConfirmation: false
    )

    private struct Args: Decodable {
        var todoList: [Item]

        struct Item: Decodable {
            var id: Int
            var title: String
            var status: AgentTodoItem.Status
        }
    }

    static func execute(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let items = try normalized(args.todoList.map {
            AgentTodoItem(id: $0.id, title: $0.title, status: $0.status)
        })

        guard let repository = ActiveTaskContext.repository,
              let taskID = ActiveTaskContext.taskID
        else {
            throw ToolError.operationFailed("Todo list is unavailable in this context.")
        }
        try await repository.updateTodoList(taskID: taskID, items: items)
        await ActiveTaskContext.applyTodoList?(items)
        return render(items)
    }

    static func normalized(_ items: [AgentTodoItem]) throws -> [AgentTodoItem] {
        var seen = Set<Int>()
        var inProgress = 0
        var cleaned: [AgentTodoItem] = []
        for item in items {
            guard seen.insert(item.id).inserted else {
                throw ToolError.invalidArguments("Duplicate todo id \(item.id). Ids must be unique.")
            }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw ToolError.invalidArguments("Todo \(item.id) needs a non-empty title.")
            }
            if item.status == .inProgress { inProgress += 1 }
            cleaned.append(AgentTodoItem(id: item.id, title: title, status: item.status))
        }
        guard inProgress <= 1 else {
            throw ToolError.invalidArguments("At most one todo may be in-progress.")
        }
        return cleaned.sorted { $0.id < $1.id }
    }

    static func render(_ items: [AgentTodoItem]) -> String {
        guard !items.isEmpty else { return "(no todos)" }
        return items.map { "\($0.status.rawValue)\t\($0.id)\t\($0.title)" }.joined(separator: "\n")
    }

    static func promptAppendix(_ items: [AgentTodoItem]) -> String {
        guard !items.isEmpty else { return "" }
        return """

        ## Todo list
        \(render(items))
        Update with manage_todo_list. Always resend the full list.
        """
    }
}

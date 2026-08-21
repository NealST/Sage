//
//  ExecuteCapabilityReminder.swift
//  Sage
//
//  Live execute-prompt overlay: plan kind, skills, MCP, todos.
//  Sandbox and tool-gate prose live on SessionLifecycle / WorkPlan.
//

import Foundation

nonisolated enum ExecuteCapabilityReminder {
    static func make(
        planKind: WorkPlan.Kind?,
        activatedSkillNames: Set<String>,
        mcpServerNames: [String],
        todos: [AgentTodoItem]
    ) -> String {
        var lines = ["", "## Runtime"]

        switch planKind {
        case .act:
            lines.append("Work plan kind: act.")

        case .observe:
            lines.append("Work plan kind: observe (read/list/search only).")

        case .answer:
            lines.append("Work plan kind: answer (no Mac changes).")

        case nil:
            lines.append("Work plan kind: none yet. Do not change the Mac.")
        }

        if !activatedSkillNames.isEmpty {
            lines.append(
                """
                Activated skills: \(activatedSkillNames.sorted().joined(separator: ", ")). \
                Use load_skill_resource / run_skill_script as allowed.
                """
            )
        }

        if !mcpServerNames.isEmpty {
            lines.append("MCP servers: \(mcpServerNames.joined(separator: ", ")).")
        }

        if !todos.isEmpty {
            let open = todos.filter { $0.status != .completed }.count
            lines.append("Todo list: \(open) open / \(todos.count) total.")
        }

        return lines.joined(separator: "\n")
    }

    static func mcpServerNames(from tools: [ToolDefinition]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for tool in tools {
            let server = MCPToolGroupTool.serverName(fromQualifiedTool: tool.name)
                ?? MCPToolGroupTool.serverName(fromGroupTool: tool.name)
            guard let server else { continue }
            if seen.insert(server).inserted {
                names.append(server)
            }
        }
        return names
    }
}

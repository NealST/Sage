//
//  approval_request.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/approval_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Live HUD kinds (exec / stdin / patch / MCP / network / permissions).
//  Assessment JSON + analytics stay out.
//

import Foundation

enum GuardianApprovalRequest: Sendable, Equatable {
    case execCommand(id: String, command: String, cwd: URL, permissionBits: SandboxPermissionBits)
    case writeStdin(id: String, processID: Int, input: String, cwd: URL)
    case applyPatch(id: String, cwd: URL, files: [URL], patch: String)
    case mcpToolCall(id: String, server: String, toolName: String, argumentsJSON: String)
    case networkAccess(id: String, host: String, target: String? = nil, port: UInt16? = nil)
    case requestPermissions(id: String, reason: String?, permissionsJSON: String)

    static func from(_ action: ApprovalAction) -> Self {
        switch action {
        case .execCommand(let id, let command, let cwd, let bits):
            return .execCommand(id: id, command: command, cwd: cwd, permissionBits: bits)

        case .writeStdin(let id, let processID, let input, let cwd):
            return .writeStdin(id: id, processID: processID, input: input, cwd: cwd)

        case .applyPatch(let id, let cwd, let files, let patch):
            return .applyPatch(id: id, cwd: cwd, files: files, patch: patch)

        case .mcpToolCall(let id, let server, let toolName, let argumentsJSON):
            return .mcpToolCall(
                id: id,
                server: server,
                toolName: toolName,
                argumentsJSON: argumentsJSON
            )

        case .networkAccess(let id, let host, let target, let port):
            return .networkAccess(id: id, host: host, target: target, port: port)

        case .requestPermissions(let id, let reason, let permissionsJSON):
            return .requestPermissions(
                id: id,
                reason: reason,
                permissionsJSON: permissionsJSON
            )
        }
    }

    func pretty() -> String {
        switch self {
        case .execCommand(_, let command, let cwd, let bits):
            return """
            exec_command
            cwd: \(cwd.path)
            permissions: \(bits.rawValue)
            command:
            \(command)
            """

        case .writeStdin(_, let processID, let input, let cwd):
            return """
            write_stdin
            cwd: \(cwd.path)
            process_id: \(processID)
            input:
            \(input)
            """

        case .applyPatch(_, let cwd, let files, let patch):
            let list = files.map(\.path).joined(separator: "\n")
            return """
            apply_patch
            cwd: \(cwd.path)
            files:
            \(list)
            patch:
            \(patch)
            """

        case .mcpToolCall(_, let server, let toolName, let argumentsJSON):
            return """
            mcp_tool_call
            server: \(server)
            tool_name: \(toolName)
            arguments:
            \(argumentsJSON)
            """

        case .networkAccess(_, let host, let target, let port):
            var lines = [
                "network_access",
                "host: \(host)",
            ]
            if let target, !target.isEmpty {
                lines.append("target: \(target)")
            }
            if let port {
                lines.append("port: \(port)")
            }
            return lines.joined(separator: "\n")

        case .requestPermissions(_, let reason, let permissionsJSON):
            var lines = ["request_permissions"]
            if let reason, !reason.isEmpty {
                lines.append("reason: \(reason)")
            }
            lines.append("permissions:")
            lines.append(permissionsJSON)
            return lines.joined(separator: "\n")
        }
    }
}

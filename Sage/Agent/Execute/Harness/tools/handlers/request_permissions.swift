//
//  request_permissions.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/request_permissions.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Path resolution against TurnEnvironment waits for Phase 5. The handler
//  validates the profile and invokes onRequestPermissions.
//

import CodexCore
import CodexProtocol
import Foundation

struct RequestPermissionsHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "request_permissions") }
    func spec() -> ToolSpec { createRequestPermissionsTool(requestPermissionsToolDescription()) }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "request_permissions handler received unsupported payload"
            )
        }
        let args: RequestPermissionsArgs = try parseArguments(arguments)
        if args.permissions.isEmpty {
            throw FunctionCallError.respondToModel(
                "request_permissions requires at least one permission"
            )
        }
        guard let onRequest = invocation.onRequestPermissions else {
            throw FunctionCallError.respondToModel(
                "request_permissions is not wired (Phase 5 Session)"
            )
        }
        guard let response = await onRequest(args) else {
            throw FunctionCallError.respondToModel(
                "request_permissions was cancelled before receiving a response"
            )
        }
        let data = try JSONEncoder().encode(response)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return boxedToolOutput(FunctionToolOutput.fromText(content, success: true))
    }
}

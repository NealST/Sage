//
//  extension_tools.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/extension_tools.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Extension host / plugin dispatch waits for Phase 9. This adapter keeps
//  the registration surface Session-free.
//

import CodexCore
import CodexProtocol

struct ExtensionToolAdapter: CoreToolRuntime {
    var name: ToolName
    var toolSpec: ToolSpec
    var toolExposure: ToolExposure
    var onCall: (@Sendable (ToolInvocation) async throws -> String)?

    init(
        name: ToolName,
        spec: ToolSpec,
        exposure: ToolExposure = .direct,
        onCall: (@Sendable (ToolInvocation) async throws -> String)? = nil
    ) {
        self.name = name
        self.toolSpec = spec
        self.toolExposure = exposure
        self.onCall = onCall
    }

    func toolName() -> ToolName { name }
    func spec() -> ToolSpec { toolSpec }
    func exposure() -> ToolExposure { toolExposure }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard let onCall else {
            throw FunctionCallError.respondToModel(
                "extension tool \(flatToolName(name)) is not wired (Phase 9)"
            )
        }
        let output = try await onCall(invocation)
        return boxedToolOutput(FunctionToolOutput.fromText(output, success: true))
    }
}

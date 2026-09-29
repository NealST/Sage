//
//  wait_handler.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/wait_handler.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Argument parsing is faithful. Wait loops wait on CodeModeSession.
//

import CodexCore
import CodexProtocol
import Foundation

struct ExecWaitArgs: Decodable, Equatable, Sendable {
    var cellId: String
    var yieldTimeMs: UInt64
    var maxTokens: Int?
    var terminate: Bool

    enum CodingKeys: String, CodingKey {
        case cellId = "cell_id"
        case yieldTimeMs = "yield_time_ms"
        case maxTokens = "max_tokens"
        case terminate
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cellId = try container.decode(String.self, forKey: .cellId)
        yieldTimeMs = try container.decodeIfPresent(UInt64.self, forKey: .yieldTimeMs)
            ?? DEFAULT_WAIT_YIELD_TIME_MS
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        terminate = try container.decodeIfPresent(Bool.self, forKey: .terminate) ?? false
    }
}

func parseWaitArguments(_ arguments: String) throws -> ExecWaitArgs {
    do {
        return try parseArguments(arguments)
    } catch {
        throw FunctionCallError.respondToModel(
            "failed to parse function arguments: \(error)"
        )
    }
}

struct CodeModeWaitHandler: CoreToolRuntime {
    var descriptionOverride: String?
    var parametersOverride: String?

    init(descriptionOverride: String? = nil, parametersOverride: String? = nil) {
        self.descriptionOverride = descriptionOverride
        self.parametersOverride = parametersOverride
    }

    func toolName() -> ToolName { ToolName(plain: WAIT_TOOL_NAME) }
    func spec() -> ToolSpec {
        createWaitTool(
            descriptionOverride: descriptionOverride,
            parametersOverride: parametersOverride
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        _ = try parseWaitArguments(arguments)
        throw FunctionCallError.respondToModel("wait waits on CodeModeSession / Session")
    }
}

//
//  sleep.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/sleep.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Input-queue interruption waits for Phase 5. CancellationToken ends the
//  sleep early.
//

import CodexAsyncUtils
import CodexCore
import CodexProtocol
import Foundation

let SLEEP_TOOL_NAME = "sleep"
let MAX_SLEEP_DURATION_MS: UInt64 = 12 * 60 * 60 * 1000

struct SleepArgs: Decodable {
    var durationMs: UInt64

    enum CodingKeys: String, CodingKey { case durationMs = "duration_ms" }
}

struct SleepHandler: CoreToolRuntime {
    func toolName() -> ToolName {
        ToolName(namespaced: CLOCK_NAMESPACE, name: SLEEP_TOOL_NAME)
    }

    func spec() -> ToolSpec {
        .namespace(
            ResponsesApiNamespace(
                name: CLOCK_NAMESPACE,
                description: "Tools for reading and waiting on time.",
                tools: [
                    ResponsesApiNamespaceTool(
                        function: ResponsesApiTool(
                            name: SLEEP_TOOL_NAME,
                            description: "Pause execution for a specified duration. The sleep ends early when new input arrives for the active turn. Returns the elapsed wall-clock time.",
                            strict: false,
                            parameters: .object(
                                [
                                    "duration_ms": .number(
                                        "How long to sleep in milliseconds. Must be between 1 and \(MAX_SLEEP_DURATION_MS)."
                                    )
                                ],
                                required: ["duration_ms"],
                                additionalProperties: false
                            )
                        )
                    )
                ]
            )
        )
    }

    func exposure() -> ToolExposure { .directModelOnly }
    func isBuiltinControlTool() -> Bool { true }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "\(SLEEP_TOOL_NAME) handler received unsupported payload"
            )
        }
        let args: SleepArgs = try parseArguments(arguments)
        guard (1...MAX_SLEEP_DURATION_MS).contains(args.durationMs) else {
            throw FunctionCallError.respondToModel(
                "duration_ms must be between 1 and \(MAX_SLEEP_DURATION_MS)"
            )
        }
        let started = invocation.clock()
        let interrupted = await sleepUntil(
            milliseconds: args.durationMs,
            cancellation: invocation.cancellationToken
        )
        let elapsed = invocation.clock().timeIntervalSince(started)
        let message = interrupted ? "Sleep interrupted by new input." : "Sleep completed."
        return boxedToolOutput(
            FunctionToolOutput.fromText(
                String(format: "Wall time: %.4f seconds\n%@", elapsed, message),
                success: true
            )
        )
    }

    private func sleepUntil(milliseconds: UInt64, cancellation: CancellationToken) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int64(milliseconds)))
                return false
            }
            group.addTask {
                await cancellation.waitForCancellation()
                return true
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}

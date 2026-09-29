//
//  command_runner.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/hooks/src/engine/command_runner_tests.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexHooks
import CodexProtocol
import CodexUtils
import XCTest

final class HooksCommandRunnerTests: XCTestCase {
    func testBuildCommandReplaysSnapshotBeforeOverridesAndScrubbing() {
        let spec = buildCommand(
            shell: CommandShell(program: "configured-shell", args: ["-c"]),
            commandLine: "echo hook-ran",
            environment: [
                ("CODEX_HOOK_SNAPSHOT", "captured"),
                ("CODEX_HOOK_OVERRIDE", "captured"),
                (codexExecServerNoiseAuthTokenEnvVar, "captured-noise-token"),
            ],
            env: [
                "CODEX_HOOK_OVERRIDE": "configured",
                "CODEX_HOOK_SAFE_ENV": "visible",
                codexExecServerNoiseAuthTokenEnvVar: "configured-noise-token",
            ]
        )
        XCTAssertEqual(spec.program, "configured-shell")
        XCTAssertEqual(spec.arguments, ["-c", "echo hook-ran"])
        XCTAssertEqual(spec.environment["CODEX_HOOK_SNAPSHOT"], "captured")
        XCTAssertEqual(spec.environment["CODEX_HOOK_OVERRIDE"], "configured")
        XCTAssertEqual(spec.environment["CODEX_HOOK_SAFE_ENV"], "visible")
        XCTAssertNil(spec.environment[codexExecServerNoiseAuthTokenEnvVar])
        XCTAssertNil(spec.environment[codexExecServerNoiseAuthTokenEnvVar.lowercased()])
    }

    func testFallbackShellUsesSnapshot() {
        let spec = buildCommand(
            shell: CommandShell(program: "", args: []),
            commandLine: "echo hook-ran",
            environment: [("SHELL", "/captured/shell")],
            env: [:]
        )
        XCTAssertEqual(spec.program, "/captured/shell")
        XCTAssertEqual(spec.arguments, ["-lc", "echo hook-ran"])
    }

    func testFastExitingHookPreservesStdoutWhenStdinIsNotConsumed() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let runtime = CommandHookRuntime(
            shell: CommandShell(program: "/bin/sh", args: ["-c"]),
            environment: ProcessInfo.processInfo.environment.map { ($0.key, $0.value) }
        )
        let handler = try commandHandler("echo hook-ran")
        let inputJSON = #"{"padding":"\#(String(repeating: "x", count: 4096))"}"#
        let result = await runCommand(
            runtime: runtime,
            handler: handler,
            command: "echo hook-ran",
            env: [:],
            inputJSON: inputJSON,
            cwd: temp.path
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hook-ran")
        XCTAssertNil(result.error)
    }

    func testCommandHookDoesNotExposeConfiguredNoiseAuthToken() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let runtime = CommandHookRuntime(
            shell: CommandShell(program: "/bin/sh", args: ["-c"]),
            environment: ProcessInfo.processInfo.environment.map { ($0.key, $0.value) }
        )
        let env = [
            codexExecServerNoiseAuthTokenEnvVar.lowercased(): "configured-noise-token",
            "CODEX_HOOK_SAFE_ENV": "visible",
        ]
        let result = await runCommand(
            runtime: runtime,
            handler: try commandHandler("env", env: env),
            command: "env",
            env: env,
            inputJSON: "{}",
            cwd: temp.path
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("CODEX_HOOK_SAFE_ENV=visible"), result.stdout)
        XCTAssertFalse(result.stdout.split(separator: "\n").contains { line in
            line.split(separator: "=").first.map {
                $0.caseInsensitiveCompare(codexExecServerNoiseAuthTokenEnvVar) == .orderedSame
            } ?? false
        })
    }

    func testHookTimesOut() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let runtime = CommandHookRuntime(
            shell: CommandShell(program: "/bin/sh", args: ["-c"])
        )
        let result = await runCommand(
            runtime: runtime,
            handler: try commandHandler("sleep 30", timeout: 1),
            command: "sleep 30",
            env: [:],
            inputJSON: "{}",
            cwd: temp.path
        )
        XCTAssertNil(result.exitCode)
        XCTAssertEqual(result.error, "hook timed out after 1s")
    }

    func testExpandMcpArgumentTemplateResolvesCompletePlaceholder() throws {
        let expanded = try expandMcpArgumentTemplate(
            ["count": .string("${tool_input.count}")],
            hookEvent: .object(["tool_input": .object(["count": .int(3)])])
        )
        XCTAssertEqual(expanded["count"], .int(3))
    }

    func testExecuteHandlersRunsSyncCommand() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let handler = try commandHandler("printf hook-ran")
        let engine = ClaudeHooksEngine(
            handlers: [handler],
            commandRuntime: CommandHookRuntime(
                shell: CommandShell(program: "/bin/sh", args: ["-c"])
            ),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        let parsed = await executeHandlers(
            engine: engine,
            handlers: [handler],
            inputJSON: "{}",
            cwd: temp.path,
            turnId: "turn-1"
        ) { handler, result, turnId in
            ParsedHandler(
                completed: HookCompletedEvent(
                    turnId: turnId,
                    run: completedSummary(handler, runResult: result, status: .completed, entries: [])
                ),
                data: result.stdout,
                completionOrder: 0
            )
        }
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.data.trimmingCharacters(in: .whitespacesAndNewlines), "hook-ran")
    }
}

private struct RejectingHookMcpExecutor: HookMcpExecutor {
    func execute(_ call: HookMcpCall) async throws -> String {
        throw CodexErr.unsupportedOperation("unused mcp executor")
    }
}

private func commandHandler(
    _ command: String,
    env: [String: String] = [:],
    timeout: UInt64 = 10
) throws -> ConfiguredHandler {
    ConfiguredHandler(
        eventName: .sessionStart,
        timeoutSec: timeout,
        sourcePath: .local(try AbsolutePathBuf.fromAbsolutePath("/tmp/hooks.json")),
        displayOrder: 0,
        kind: .command(command: command, env: env, isAsync: false)
    )
}

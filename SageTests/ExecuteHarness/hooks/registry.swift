//
//  registry.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/hooks/src/legacy_notify.rs and registry construction
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexHooks
import CodexProtocol
import CodexUtils
import XCTest

final class HooksRegistryTests: XCTestCase {
    func testListHooksDisabledReturnsEmpty() {
        let outcome = listHooks(HooksConfig(featureEnabled: false, pluginHookLoadWarnings: ["ignored"]))
        XCTAssertEqual(outcome, HookListOutcome())
    }

    func testListHooksEnabledKeepsPluginLoadWarnings() {
        let outcome = listHooks(
            HooksConfig(featureEnabled: true, pluginHookLoadWarnings: ["plugin missing hooks.json"])
        )
        XCTAssertEqual(outcome.hooks, [])
        XCTAssertEqual(outcome.warnings, ["plugin missing hooks.json"])
    }

    func testHooksNewDisabledHasNoHandlers() throws {
        let (hooks, mailbox) = try Hooks.new(
            config: HooksConfig(featureEnabled: false),
            threadId: ThreadId(),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        XCTAssertTrue(hooks.engine.handlers.isEmpty)
        XCTAssertTrue(hooks.afterAgent.isEmpty)
        XCTAssertFalse(mailbox.isClosed)
        XCTAssertEqual(hooks.maxPermissionRequestTimeout(), 0)
    }

    func testHooksNewInstallsLegacyNotify() throws {
        let (hooks, _) = try Hooks.new(
            config: HooksConfig(
                legacyNotifyArgv: ["true"],
                featureEnabled: false
            ),
            threadId: ThreadId(),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        XCTAssertEqual(hooks.afterAgent.map(\.name), ["legacy_notify"])
    }

    func testCommandFromArgvScrubsNoiseAuthToken() {
        let spec = commandFromArgv(
            ["notify-command"],
            environment: [
                ("CODEX_LEGACY_NOTIFY_SNAPSHOT", "captured"),
                (codexExecServerNoiseAuthTokenEnvVar, "restricted-token"),
            ]
        )
        XCTAssertEqual(spec?.program, "notify-command")
        XCTAssertEqual(spec?.arguments, [])
        XCTAssertEqual(spec?.environment["CODEX_LEGACY_NOTIFY_SNAPSHOT"], "captured")
        XCTAssertNil(spec?.environment[codexExecServerNoiseAuthTokenEnvVar])
    }

    func testNotifyHookEmptyArgvSucceeds() async throws {
        let hook = notifyHook(argv: [])
        let payload = HookPayload(
            sessionId: ThreadId(),
            cwd: try AbsolutePathBuf.fromAbsolutePath("/tmp"),
            triggeredAt: Date(),
            hookEvent: .afterAgent(
                HookEventAfterAgent(
                    threadId: ThreadId(),
                    turnId: "1",
                    inputMessages: []
                )
            )
        )
        let response = await hook.execute(payload)
        XCTAssertEqual(response.hookName, "legacy_notify")
        if case .success = response.result {
        } else {
            XCTFail("expected success")
        }
    }

    func testEnginePreviewInterruptEmpty() {
        let engine = ClaudeHooksEngine.new(
            enabled: false,
            commandRuntime: CommandHookRuntime(shell: CommandShell(program: "/bin/sh", args: ["-c"])),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        XCTAssertEqual(engine.previewInterrupt(), [])
    }

    func testHooksReconfiguredKeepsMailbox() throws {
        let (hooks, mailbox) = try Hooks.new(
            config: HooksConfig(featureEnabled: false, shellProgram: "/bin/sh", shellArgs: ["-c"]),
            threadId: ThreadId(),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        let next = hooks.reconfigured(HooksConfig(featureEnabled: false, shellProgram: "/bin/zsh"))
        XCTAssertTrue(next.engine.commandRuntime.resultSender === mailbox)
        XCTAssertEqual(next.engine.commandRuntime.shell.program, "/bin/zsh")
    }
}

private struct RejectingHookMcpExecutor: HookMcpExecutor {
    func execute(_ call: HookMcpCall) async throws -> String {
        throw CodexErr.unsupportedOperation("unused mcp executor")
    }
}

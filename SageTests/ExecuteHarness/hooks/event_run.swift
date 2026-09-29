//
//  event_run.swift
//  SageTests
//
//  Port of selected cases from
//  codex-rs/hooks/src/events/{user_prompt_submit,session_start,compact,stop,
//  pre_tool_use,post_tool_use,permission_request}.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

@testable import CodexHooks
import CodexProtocol
import CodexUtils
import XCTest

final class HooksEventRunTests: XCTestCase {
    func testUserPromptSubmitContinueFalsePreservesContext() {
        let parsed = parseUserPromptSubmitCompleted(
            handler(.userPromptSubmit),
            runResult(
                0,
                #"{"continue":false,"stopReason":"pause","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"do not inject"}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            UserPromptSubmitHandlerData(
                shouldStop: true,
                stopReason: "pause",
                additionalContextsForModel: [AdditionalContext(text: "do not inject")]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(kind: .context, text: "do not inject"),
                HookOutputEntry(kind: .stop, text: "pause"),
            ]
        )
    }

    func testUserPromptSubmitClaudeBlockDecisionBlocksProcessing() {
        let parsed = parseUserPromptSubmitCompleted(
            handler(.userPromptSubmit),
            runResult(
                0,
                #"{"decision":"block","reason":"slow down","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"do not inject"}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            UserPromptSubmitHandlerData(
                shouldStop: true,
                stopReason: "slow down",
                additionalContextsForModel: [AdditionalContext(text: "do not inject")]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(kind: .context, text: "do not inject"),
                HookOutputEntry(kind: .feedback, text: "slow down"),
            ]
        )
    }

    func testUserPromptSubmitClaudeBlockDecisionRequiresReason() {
        let stdout = #"{"decision":"block","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"do not inject"}}"#
        let parsed = parseUserPromptSubmitCompleted(
            handler(.userPromptSubmit),
            runResult(0, stdout),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            UserPromptSubmitHandlerData(
                shouldStop: false,
                stopReason: nil,
                additionalContextsForModel: []
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(
                    kind: .error,
                    text: "UserPromptSubmit hook returned decision:block without a non-empty reason"
                ),
            ]
        )

        let asyncParsed = parseUserPromptSubmitCompleted(
            handler(.userPromptSubmit, isAsync: true),
            runResult(0, stdout),
            "turn-1"
        )
        XCTAssertEqual(asyncParsed.completed.run.status, .completed)
        XCTAssertEqual(
            asyncParsed.completed.run.entries,
            [HookOutputEntry(kind: .context, text: "do not inject")]
        )
    }

    func testUserPromptSubmitExitCodeTwoBlocksProcessing() {
        let parsed = parseUserPromptSubmitCompleted(
            handler(.userPromptSubmit),
            runResult(2, "", "blocked by policy\n"),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            UserPromptSubmitHandlerData(
                shouldStop: true,
                stopReason: "blocked by policy",
                additionalContextsForModel: []
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .feedback, text: "blocked by policy")]
        )

        let asyncParsed = parseUserPromptSubmitCompleted(
            handler(.userPromptSubmit, isAsync: true),
            runResult(2, "", "blocked by policy\n"),
            "turn-1"
        )
        XCTAssertEqual(asyncParsed.completed.run.status, .failed)
        XCTAssertFalse(asyncParsed.data.shouldStop)
    }

    func testSessionStartPlainStdoutBecomesModelContext() {
        var configured = handler(.sessionStart)
        configured.additionalContextLimit = .fromConfig(7)
        let parsed = parseSessionStartCompleted(
            configured,
            runResult(0, "hello from hook\n"),
            nil
        )
        XCTAssertEqual(
            parsed.data,
            SessionStartHandlerData(
                shouldStop: false,
                stopReason: nil,
                additionalContextsForModel: [
                    AdditionalContext(text: "hello from hook", limit: .fromConfig(7)),
                ]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .context, text: "hello from hook")]
        )
    }

    func testSessionStartContinueFalsePreservesContext() {
        let parsed = parseSessionStartCompleted(
            handler(.sessionStart),
            runResult(
                0,
                #"{"continue":false,"stopReason":"pause","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"do not inject"}}"#
            ),
            nil
        )
        XCTAssertEqual(
            parsed.data,
            SessionStartHandlerData(
                shouldStop: true,
                stopReason: "pause",
                additionalContextsForModel: [AdditionalContext(text: "do not inject")]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(kind: .context, text: "do not inject"),
                HookOutputEntry(kind: .stop, text: "pause"),
            ]
        )
    }

    func testSessionStartInvalidJSONLikeStdoutFails() {
        let parsed = parseSessionStartCompleted(
            handler(.sessionStart),
            runResult(0, #"{"hookSpecificOutput":{"hookEventName":"SessionStart""#),
            nil
        )
        XCTAssertEqual(parsed.data.additionalContextsForModel, [])
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .error, text: "hook returned invalid session start JSON output")]
        )
    }

    func testSubagentStartContinueFalseIsIgnored() {
        let parsed = parseSessionStartCompleted(
            handler(.subagentStart),
            runResult(
                0,
                #"{"continue":false,"stopReason":"skip child","hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"child context"}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            SessionStartHandlerData(
                shouldStop: false,
                stopReason: nil,
                additionalContextsForModel: [AdditionalContext(text: "child context")]
            )
        )
        XCTAssertEqual(parsed.completed.turnId, "turn-1")
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .context, text: "child context")]
        )
    }

    func testPreCompactBlockDecisionIsNotSupported() {
        let parsed = parsePreCompactCompleted(
            handler(.preCompact),
            runResult(0, #"{"decision":"block","reason":"policy blocked compaction"}"#),
            "turn-1"
        )
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .error, text: "hook returned invalid PreCompact hook JSON output")]
        )
    }

    func testPreCompactContinueFalseStopsBeforeCompaction() {
        let parsed = parsePreCompactCompleted(
            handler(.preCompact),
            runResult(0, #"{"continue":false,"stopReason":"nope"}"#),
            "turn-1"
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertTrue(parsed.data.shouldStop)
        XCTAssertEqual(parsed.data.stopReason, "nope")
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .stop, text: "nope")]
        )
    }

    func testPostCompactContinueFalseStopsAfterCompaction() {
        let parsed = parsePostCompactCompleted(
            handler(.postCompact),
            runResult(0, #"{"continue":false,"stopReason":"pause after compact"}"#),
            "turn-1"
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertTrue(parsed.data.shouldStop)
        XCTAssertEqual(parsed.data.stopReason, "pause after compact")
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .stop, text: "pause after compact")]
        )
    }

    func testCompactIgnoresPlainStdout() {
        let pre = parsePreCompactCompleted(
            handler(.preCompact),
            runResult(0, "checking compact policy\n"),
            "turn-1"
        )
        XCTAssertEqual(pre.completed.run.status, .completed)
        XCTAssertEqual(pre.completed.run.entries, [])

        let post = parsePostCompactCompleted(
            handler(.postCompact),
            runResult(0, "logged compact summary\n"),
            "turn-1"
        )
        XCTAssertEqual(post.completed.run.status, .completed)
        XCTAssertEqual(post.completed.run.entries, [])
    }

    func testStopBlockDecisionWithReasonSetsContinuationPrompt() {
        let parsed = parseStopCompleted(
            handler(.stop),
            runResult(0, #"{"decision":"block","reason":"retry with tests"}"#),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            StopHandlerData(
                shouldStop: false,
                stopReason: nil,
                shouldBlock: true,
                blockReason: "retry with tests",
                continuationFragments: [
                    HookPromptFragment.fromSingleHook(
                        text: "retry with tests",
                        hookRunId: parsed.completed.run.id
                    ),
                ]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testStopBlockDecisionWithoutReasonIsInvalid() {
        let parsed = parseStopCompleted(
            handler(.stop),
            runResult(0, #"{"decision":"block"}"#),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, StopHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(
                    kind: .error,
                    text: "Stop hook returned decision:block without a non-empty reason"
                ),
            ]
        )

        let asyncParsed = parseStopCompleted(
            handler(.stop, isAsync: true),
            runResult(0, #"{"decision":"block"}"#),
            "turn-1"
        )
        XCTAssertEqual(asyncParsed.completed.run.status, .completed)
        XCTAssertEqual(asyncParsed.completed.run.entries, [])
    }

    func testStopContinueFalseOverridesBlockDecision() {
        let parsed = parseStopCompleted(
            handler(.stop),
            runResult(
                0,
                #"{"continue":false,"stopReason":"done","decision":"block","reason":"keep going"}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            StopHandlerData(
                shouldStop: true,
                stopReason: "done",
                shouldBlock: false,
                blockReason: nil,
                continuationFragments: []
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
    }

    func testStopExitCodeTwoUsesStderrFeedbackOnly() {
        let parsed = parseStopCompleted(
            handler(.stop),
            runResult(2, "ignored stdout", "retry with tests"),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            StopHandlerData(
                shouldStop: false,
                stopReason: nil,
                shouldBlock: true,
                blockReason: "retry with tests",
                continuationFragments: [
                    HookPromptFragment.fromSingleHook(
                        text: "retry with tests",
                        hookRunId: parsed.completed.run.id
                    ),
                ]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testStopInvalidStdoutFailsInsteadOfNooping() {
        let parsed = parseStopCompleted(
            handler(.stop),
            runResult(0, "not json"),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, StopHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .error, text: "hook returned invalid stop hook JSON output")]
        )

        let asyncParsed = parseStopCompleted(
            handler(.stop, isAsync: true),
            runResult(0, "not json"),
            "turn-1"
        )
        XCTAssertEqual(asyncParsed.completed.run.status, .completed)
        XCTAssertEqual(asyncParsed.completed.run.entries, [])
    }

    func testAggregateStopResultsConcatenatesBlockingReasons() {
        let aggregate = aggregateStopResults([
            StopHandlerData(
                shouldBlock: true,
                blockReason: "first",
                continuationFragments: [
                    HookPromptFragment.fromSingleHook(text: "first", hookRunId: "run-1"),
                ]
            ),
            StopHandlerData(
                shouldBlock: true,
                blockReason: "second",
                continuationFragments: [
                    HookPromptFragment.fromSingleHook(text: "second", hookRunId: "run-2"),
                ]
            ),
        ])
        XCTAssertEqual(
            aggregate,
            StopHandlerData(
                shouldBlock: true,
                blockReason: "first\n\nsecond",
                continuationFragments: [
                    HookPromptFragment.fromSingleHook(text: "first", hookRunId: "run-1"),
                    HookPromptFragment.fromSingleHook(text: "second", hookRunId: "run-2"),
                ]
            )
        )
    }

    func testInterruptRunCompletesEmptyStdout() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let configured = handler(.interrupt, command: "true")
        let engine = ClaudeHooksEngine(
            handlers: [configured],
            commandRuntime: CommandHookRuntime(
                shell: CommandShell(program: "/bin/sh", args: ["-c"])
            ),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        let outcome = await runInterrupt(
            engine,
            request: InterruptRequest(
                sessionId: ThreadId(),
                turnId: "turn-1",
                cwd: try AbsolutePathBuf.fromAbsolutePath(temp.path),
                model: "gpt-test",
                permissionMode: "default"
            )
        )
        XCTAssertEqual(outcome.hookEvents.count, 1)
        XCTAssertEqual(outcome.hookEvents.first?.run.status, .completed)
        XCTAssertEqual(outcome.hookEvents.first?.turnId, "turn-1")
    }

    func testUserPromptSubmitRunInjectsPlainStdout() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let configured = handler(.userPromptSubmit, command: "printf 'hello from hook'")
        let engine = ClaudeHooksEngine(
            handlers: [configured],
            commandRuntime: CommandHookRuntime(
                shell: CommandShell(program: "/bin/sh", args: ["-c"])
            ),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        let outcome = await runUserPromptSubmit(
            engine,
            request: UserPromptSubmitRequest(
                sessionId: ThreadId(),
                turnId: "turn-1",
                cwd: try AbsolutePathBuf.fromAbsolutePath(temp.path),
                model: "gpt-test",
                permissionMode: "default",
                prompt: "hi"
            )
        )
        XCTAssertEqual(outcome.additionalContexts, ["hello from hook"])
        XCTAssertFalse(outcome.shouldStop)
        XCTAssertEqual(outcome.hookEvents.first?.run.status, .completed)
    }

    func testPreToolUsePermissionDecisionDenyBlocks() {
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(
                0,
                #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"do not run that"}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PreToolUseHandlerData(
                shouldBlock: true,
                blockReason: "do not run that"
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .feedback, text: "do not run that")]
        )
    }

    func testPreToolUsePermissionDecisionAllowCanUpdateInput() {
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(
                0,
                #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"echo rewritten"}}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PreToolUseHandlerData(
                updatedInput: .object(["command": .string("echo rewritten")])
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [])
    }

    func testPreToolUseLastCompletedUpdatedInputWins() {
        var laterConfigured = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(
                0,
                #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"echo configured later"}}}"#
            ),
            "turn-1"
        )
        laterConfigured.completionOrder = 0
        var earlierConfigured = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(
                0,
                #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"echo finished later"}}}"#
            ),
            "turn-1"
        )
        earlierConfigured.completionOrder = 1
        XCTAssertEqual(
            latestUpdatedInput([laterConfigured, earlierConfigured]),
            .object(["command": .string("echo finished later")])
        )
    }

    func testPreToolUseAllowWithoutUpdatedInputFailsOpen() {
        let stdout = #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"preserved"}}"#
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(0, stdout),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, PreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(
                    kind: .error,
                    text: "PreToolUse hook returned unsupported permissionDecision:allow"
                ),
            ]
        )

        let asyncParsed = parsePreToolUseCompleted(
            handler(.preToolUse, isAsync: true),
            runResult(0, stdout),
            "turn-1"
        )
        XCTAssertEqual(asyncParsed.completed.run.status, .completed)
        XCTAssertEqual(
            asyncParsed.completed.run.entries,
            [HookOutputEntry(kind: .context, text: "preserved")]
        )
    }

    func testPreToolUseDeprecatedBlockDecisionBlocks() {
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(0, #"{"decision":"block","reason":"do not run that"}"#),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PreToolUseHandlerData(shouldBlock: true, blockReason: "do not run that")
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testPreToolUseUnsupportedAskFailsOpen() {
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(
                0,
                #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"please confirm"}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, PreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(
                    kind: .error,
                    text: "PreToolUse hook returned unsupported permissionDecision:ask"
                ),
            ]
        )
    }

    func testPreToolUsePlainStdoutIsIgnored() {
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(0, "hook ran successfully\n"),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, PreToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [])
    }

    func testPreToolUseExitCodeTwoBlocks() {
        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(2, "", "blocked by policy\n"),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PreToolUseHandlerData(shouldBlock: true, blockReason: "blocked by policy")
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testPreToolUsePreviewAndCompletedRunIdsIncludeToolUseId() {
        let request = PreToolUseRequest(
            sessionId: ThreadId(),
            turnId: "turn-1",
            cwd: (try? AbsolutePathBuf.fromAbsolutePath("/tmp"))!,
            model: "gpt-test",
            permissionMode: "default",
            toolName: "Bash",
            toolUseId: "tool-call-123",
            toolInput: .object(["command": .string("echo hello")])
        )
        let runs = previewPreToolUse(handlers: [handler(.preToolUse)], request: request)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.id, "pre-tool-use:0:/tmp/hooks.json:tool-call-123")

        let parsed = parsePreToolUseCompleted(
            handler(.preToolUse),
            runResult(0, ""),
            "turn-1"
        )
        let completed = hookCompletedForToolUse(parsed.completed, toolUseId: request.toolUseId)
        XCTAssertEqual(completed.run.id, runs.first?.id)
    }

    func testPostToolUseBlockDecisionStopsProcessing() {
        let parsed = parsePostToolUseCompleted(
            handler(.postToolUse),
            runResult(0, #"{"decision":"block","reason":"bash output looked sketchy"}"#),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PostToolUseHandlerData(
                shouldBlock: true,
                feedbackMessagesForModel: ["bash output looked sketchy"]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testPostToolUseAdditionalContextIsRecorded() {
        var configured = handler(.postToolUse)
        configured.additionalContextLimit = .fromConfig(17)
        let parsed = parsePostToolUseCompleted(
            configured,
            runResult(
                0,
                #"{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Remember the bash cleanup note."}}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PostToolUseHandlerData(
                additionalContextsForModel: [
                    AdditionalContext(text: "Remember the bash cleanup note.", limit: .fromConfig(17)),
                ]
            )
        )
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .context, text: "Remember the bash cleanup note.")]
        )
    }

    func testPostToolUseUnsupportedUpdatedMcpOutputFailsOpen() {
        let stdout = #"{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedMCPToolOutput":{"ok":true},"additionalContext":"preserved"}}"#
        let parsed = parsePostToolUseCompleted(
            handler(.postToolUse),
            runResult(0, stdout),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, PostToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .failed)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [
                HookOutputEntry(
                    kind: .error,
                    text: "PostToolUse hook returned unsupported updatedMCPToolOutput"
                ),
            ]
        )

        let asyncParsed = parsePostToolUseCompleted(
            handler(.postToolUse, isAsync: true),
            runResult(0, stdout),
            "turn-1"
        )
        XCTAssertEqual(asyncParsed.completed.run.status, .completed)
        XCTAssertEqual(
            asyncParsed.completed.run.entries,
            [HookOutputEntry(kind: .context, text: "preserved")]
        )
    }

    func testPostToolUseContinueFalseStopsWithReason() {
        let parsed = parsePostToolUseCompleted(
            handler(.postToolUse),
            runResult(
                0,
                #"{"continue":false,"stopReason":"halt after bash output","reason":"post-tool hook says stop"}"#
            ),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PostToolUseHandlerData(feedbackMessagesForModel: ["post-tool hook says stop"])
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
        XCTAssertEqual(
            parsed.completed.run.entries,
            [HookOutputEntry(kind: .stop, text: "halt after bash output")]
        )
    }

    func testPostToolUseContinueFalseWithoutReasonSynthesizesFeedback() {
        let parsed = parsePostToolUseCompleted(
            handler(.postToolUse),
            runResult(0, #"{"continue":false}"#),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PostToolUseHandlerData(feedbackMessagesForModel: ["PostToolUse hook stopped execution"])
        )
        XCTAssertEqual(parsed.completed.run.status, .stopped)
    }

    func testPostToolUsePlainStdoutIsIgnored() {
        let parsed = parsePostToolUseCompleted(
            handler(.postToolUse),
            runResult(0, "plain text only"),
            "turn-1"
        )
        XCTAssertEqual(parsed.data, PostToolUseHandlerData())
        XCTAssertEqual(parsed.completed.run.status, .completed)
        XCTAssertEqual(parsed.completed.run.entries, [])
    }

    func testPostToolUseExitTwoBlocksWithFeedback() {
        let parsed = parsePostToolUseCompleted(
            handler(.postToolUse),
            runResult(2, "", "post hook says pause"),
            "turn-1"
        )
        XCTAssertEqual(
            parsed.data,
            PostToolUseHandlerData(
                shouldBlock: true,
                feedbackMessagesForModel: ["post hook says pause"]
            )
        )
        XCTAssertEqual(parsed.completed.run.status, .blocked)
    }

    func testPermissionRequestDenyOverridesEarlierAllow() {
        XCTAssertEqual(
            resolvePermissionRequestDecision([
                .allow,
                .deny(message: "repo deny"),
            ]),
            .deny(message: "repo deny")
        )
    }

    func testPermissionRequestReturnsAllowWhenNoHandlerDenies() {
        XCTAssertEqual(
            resolvePermissionRequestDecision([.allow, .allow]),
            .allow
        )
    }

    func testPermissionRequestReturnsNoneWhenNoHandlerDecides() {
        XCTAssertNil(resolvePermissionRequestDecision([]))
    }

    func testPreToolUseRunBlocksFromCommand() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let configured = handler(
            .preToolUse,
            command: #"printf '{"decision":"block","reason":"blocked by hook"}'"#
        )
        let engine = ClaudeHooksEngine(
            handlers: [configured],
            commandRuntime: CommandHookRuntime(
                shell: CommandShell(program: "/bin/sh", args: ["-c"])
            ),
            mcpExecutor: RejectingHookMcpExecutor()
        )
        let outcome = await runPreToolUse(
            engine,
            request: PreToolUseRequest(
                sessionId: ThreadId(),
                turnId: "turn-1",
                cwd: try AbsolutePathBuf.fromAbsolutePath(temp.path),
                model: "gpt-test",
                permissionMode: "default",
                toolName: "Bash",
                toolUseId: "call-1",
                toolInput: .object(["command": .string("echo hello")])
            )
        )
        XCTAssertTrue(outcome.shouldBlock)
        XCTAssertEqual(outcome.blockReason, "blocked by hook")
        XCTAssertEqual(outcome.hookEvents.first?.run.status, .blocked)
        XCTAssertEqual(outcome.hookEvents.first?.run.id.hasSuffix(":call-1"), true)
    }
}

private struct RejectingHookMcpExecutor: HookMcpExecutor {
    func execute(_ call: HookMcpCall) async throws -> String {
        throw CodexErr.unsupportedOperation("unused mcp executor")
    }
}

private func handler(
    _ eventName: HookEventName,
    isAsync: Bool = false,
    command: String = "echo hook"
) -> ConfiguredHandler {
    ConfiguredHandler(
        eventName: eventName,
        timeoutSec: 5,
        sourcePath: .local((try? AbsolutePathBuf.fromAbsolutePath("/tmp/hooks.json"))!),
        source: .user,
        displayOrder: 0,
        kind: .command(command: command, env: [:], isAsync: isAsync)
    )
}

private func runResult(_ exitCode: Int32?, _ stdout: String, _ stderr: String = "") -> HandlerRunResult {
    HandlerRunResult(
        startedAt: 1,
        completedAt: 2,
        durationMs: 1,
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr
    )
}

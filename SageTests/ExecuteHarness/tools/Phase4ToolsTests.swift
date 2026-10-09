import CodexCore
import CodexProtocol
import CodexShellCommand
import XCTest
@testable import Sage

final class Phase4ToolsTests: XCTestCase {
    func testFinalizeToolRouterRegistersCoreHandlers() {
        let router = finalizeToolRouter()
        let names = Set(router.registry.registeredEntries().map { flatToolName($0.runtime.toolName()) })
        XCTAssertTrue(names.contains("clockcurr_time") || names.contains("curr_time"))
        XCTAssertTrue(names.contains("update_plan"))
        XCTAssertTrue(names.contains("new_context"))
        XCTAssertTrue(names.contains("get_context_remaining"))
        XCTAssertTrue(names.contains("request_permissions"))
    }

    func testCurrentTimeHandlerReturnsUTC() async throws {
        let handler = CurrentTimeHandler()
        let fixed = Date(timeIntervalSince1970: 0)
        let invocation = ToolInvocation(
            callId: "t1",
            toolName: handler.toolName(),
            payload: .function(arguments: "{}"),
            clock: { fixed }
        )
        let output = try await handler.handle(invocation)
        XCTAssertEqual(output.logOutput(), "1970-01-01 00:00:00 UTC")
        XCTAssertTrue(output.successForLogging())
    }

    func testPlanHandlerInvokesCallback() async throws {
        let handler = PlanHandler()
        var received: UpdatePlanArgs?
        let args = #"{"plan":[{"step":"one","status":"pending"}]}"#
        let invocation = ToolInvocation(
            callId: "p1",
            toolName: handler.toolName(),
            payload: .function(arguments: args),
            onPlanUpdate: { received = $0 }
        )
        let output = try await handler.handle(invocation)
        XCTAssertEqual(output.logOutput(), PLAN_UPDATED_MESSAGE)
        XCTAssertEqual(received?.plan.count, 1)
        XCTAssertEqual(received?.plan.first?.step, "one")
    }

    func testPlanHandlerRejectsPlanMode() async {
        let handler = PlanHandler()
        let invocation = ToolInvocation(
            callId: "p2",
            toolName: handler.toolName(),
            payload: .function(arguments: #"{"plan":[]}"#),
            modeKind: .plan
        )
        do {
            _ = try await handler.handle(invocation)
            XCTFail("expected plan-mode rejection")
        } catch let error as FunctionCallError {
            XCTAssertTrue(error.description.contains("not allowed in Plan mode"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSleepHandlerRejectsZeroDuration() async {
        let handler = SleepHandler()
        let invocation = ToolInvocation(
            callId: "s1",
            toolName: handler.toolName(),
            payload: .function(arguments: #"{"duration_ms":0}"#)
        )
        do {
            _ = try await handler.handle(invocation)
            XCTFail("expected invalid duration")
        } catch let error as FunctionCallError {
            XCTAssertTrue(error.description.contains("duration_ms"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRequestUserInputUnavailableOutsidePlan() {
        let message = requestUserInputUnavailableMessage(mode: .default, availableModes: [.plan])
        XCTAssertEqual(message, "request_user_input is unavailable in Default mode")
        XCTAssertNil(requestUserInputUnavailableMessage(mode: .plan, availableModes: [.plan]))
    }

    func testGetCommandDirectUsesSessionShell() throws {
        let args = try JSONDecoder().decode(
            ExecCommandArgs.self,
            from: Data(#"{"cmd":"echo hi"}"#.utf8)
        )
        let shell = Shell(shellType: .zsh, shellPath: "/bin/zsh")
        let resolved = try getCommand(
            args: args,
            sessionShell: shell,
            shellMode: .direct,
            allowLoginShell: true
        )
        XCTAssertEqual(resolved.command, ["/bin/zsh", "-lc", "echo hi"])
        XCTAssertEqual(resolved.shellType, .zsh)
    }

    func testGetCommandZshForkRejectsShellOverride() throws {
        let args = try JSONDecoder().decode(
            ExecCommandArgs.self,
            from: Data(#"{"cmd":"echo hi","shell":"/bin/bash"}"#.utf8)
        )
        XCTAssertThrowsError(
            try getCommand(
                args: args,
                sessionShell: Shell(shellType: .zsh, shellPath: "/bin/zsh"),
                shellMode: .zshFork,
                allowLoginShell: true
            )
        )
    }

    func testToolSearchSpecIncludesSources() {
        let spec = createToolSearchTool(
            searchableSources: [
                ToolSearchSourceInfo(
                    name: "Google Drive",
                    description: "Use Google Drive as the single entrypoint for Drive, Docs, Sheets, and Slides work."
                ),
                ToolSearchSourceInfo(name: "Google Drive", description: nil),
                ToolSearchSourceInfo(name: "docs", description: nil),
            ],
            defaultLimit: 8,
            sourceListing: .include
        )
        guard case .toolSearch(_, let description, _) = spec else {
            return XCTFail("expected tool search spec")
        }
        XCTAssertTrue(description.contains("Google Drive: Use Google Drive"))
        XCTAssertTrue(description.contains("- docs"))
        XCTAssertTrue(description.contains("`tool_search`"))
    }

    func testExecutedToolCallsRecordsCompletion() {
        let recorder = ExecutedToolCalls()
        let call = ToolCall(
            toolName: ToolName(plain: "update_plan"),
            callId: "c1",
            payload: .function(arguments: #"{"plan":[]}"#)
        )
        XCTAssertTrue(recorder.prepare(call: call, source: .direct))
        recorder.complete(callId: "c1", output: FunctionToolOutput.fromText("ok", success: true))
        XCTAssertEqual(recorder.retainedCalls().first?.toolName, "update_plan")
        XCTAssertEqual(recorder.retainedCalls().first?.output, "ok")
    }

    func testRegistryDispatchUnknownTool() async {
        let registry = HarnessToolRegistry()
        do {
            _ = try await registry.dispatch(
                ToolInvocation(
                    callId: "x",
                    toolName: ToolName(plain: "missing"),
                    payload: .function(arguments: "{}")
                )
            )
            XCTFail("expected unsupported tool")
        } catch let error as FunctionCallError {
            XCTAssertTrue(error.description.contains("unsupported tool"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testPlannedRouterOmitsUngatedUtilities() {
        let names = plannedToolNames()
        XCTAssertFalse(names.contains("clockcurr_time"))
        XCTAssertFalse(names.contains("clocksleep"))
        XCTAssertFalse(names.contains("update_plan"))
        XCTAssertFalse(names.contains("new_context"))
        XCTAssertFalse(names.contains("get_context_remaining"))
        XCTAssertFalse(names.contains("request_permissions"))
        XCTAssertTrue(names.contains("request_user_input"))
    }

    func testPlannedRouterIncludesClockFromReminderOrExperimentalTool() {
        var reminder = Config(features: Features([.currentTimeReminder]))
        XCTAssertTrue(plannedToolNames(config: reminder).contains("clockcurr_time"))
        XCTAssertFalse(plannedToolNames(config: reminder).contains("clocksleep"))

        reminder.currentTimeReminder = CurrentTimeReminderConfig(sleepTool: true)
        reminder.features.enable(.sleepTool)
        reminder.sleepToolMode = .modelDriven
        XCTAssertTrue(plannedToolNames(config: reminder).contains("clocksleep"))

        var clock = minimalModelInfo()
        clock.experimentalSupportedTools = ["clock"]
        var sleepOn = Config(features: Features([.sleepTool]))
        sleepOn.experimentalRequestUserInputEnabled = false
        let names = plannedToolNames(config: sleepOn, model: clock)
        XCTAssertTrue(names.contains("clockcurr_time"))
        XCTAssertTrue(names.contains("clocksleep"))
    }

    func testPlannedRouterIncludesTokenBudgetAndUnifiedExec() {
        let budget = plannedToolNames(config: Config(features: Features([.tokenBudget])))
        XCTAssertTrue(budget.contains("new_context"))
        XCTAssertTrue(budget.contains("get_context_remaining"))
        let router = plannedRouter(config: Config(features: Features([.tokenBudget])))
        XCTAssertEqual(
            router.registry.entry(for: ToolName(plain: "new_context"))?.exposure,
            .directModelOnly
        )
        XCTAssertTrue(router.modelVisibleSpecs.contains { $0.name() == "new_context" })

        let exec = plannedToolNames(config: Config(features: Features([.unifiedExec])))
        XCTAssertTrue(exec.contains("exec_command"))
        XCTAssertTrue(exec.contains("write_stdin"))

        var disabled = minimalModelInfo()
        disabled.shellType = .disabled
        let blocked = plannedToolNames(
            config: Config(features: Features([.unifiedExec])),
            model: disabled
        )
        XCTAssertFalse(blocked.contains("exec_command"))
        XCTAssertFalse(blocked.contains("write_stdin"))
    }

    func testDeferredToolStaysRegisteredAndOutOfModelSpecs() {
        var options = ToolRouterPlanOptions()
        options.includeCurrentTime = false
        options.includeSleep = false
        options.includePlan = false
        options.includeNewContextWindow = false
        options.includeGetContextRemaining = false
        options.includeRequestPermissions = false
        var router = finalizeToolRouter(options)
        registerMcpTools(
            [McpToolRegistration(tool: McpVisibleTool(name: "deferred.tool"), exposure: .deferred)],
            on: &router
        )
        XCTAssertNotNil(router.registry.entry(for: ToolName(plain: "deferred.tool")))
        XCTAssertFalse(router.modelVisibleSpecs.contains { $0.name() == "deferred.tool" })
    }

    func testRegistryParallelFollowsRuntimeAndKeepsFirstRegistration() {
        var registry = HarnessToolRegistry()
        registry.register(TestSyncHandler())
        XCTAssertEqual(registry.supportsParallelToolCalls(ToolName(plain: "test_sync_tool")), true)
        registry.register(TestSyncHandler())
        XCTAssertEqual(registry.firstCollision, "test_sync_tool")
        XCTAssertEqual(registry.registeredEntries().count, 1)

        var hidden = HarnessToolRegistry()
        hidden.register(TestSyncHandler(), exposure: .hidden)
        XCTAssertEqual(hidden.supportsParallelToolCalls(ToolName(plain: "test_sync_tool")), false)

        var model = minimalModelInfo()
        model.experimentalSupportedTools = ["test_sync_tool"]
        var config = Config()
        config.experimentalRequestUserInputEnabled = false
        let router = plannedRouter(config: config, model: model)
        XCTAssertTrue(
            router.toolSupportsParallel(
                ToolCall(
                    toolName: ToolName(plain: "test_sync_tool"),
                    callId: "s1",
                    payload: .function(arguments: "{}"),
                    encryptedFunctionArgs: nil
                )
            )
        )
    }

    func testMcpToolCallParsesSkipsAndSanitizes() async {
        let invalid = await handleMcpToolCall(
            server: "linear",
            toolName: "search",
            arguments: "{",
            prepared: PreparedMcpToolCall(serverName: "linear", toolName: "search"),
            transport: { _ in
                XCTFail("invalid arguments must not reach transport")
                return mcpTextResult("unused")
            }
        )
        XCTAssertTrue(mcpToolResultText(invalid.result).hasPrefix("err:"))
        XCTAssertEqual(invalid.result.isError, true)

        let missing = await handleMcpToolCall(
            server: "linear",
            toolName: "search",
            arguments: "{}",
            prepared: nil,
            transport: { _ in mcpTextResult("unused") }
        )
        XCTAssertEqual(
            mcpToolResultText(missing.result),
            "MCP tool `linear/search` is not available to the model"
        )

        let blocked = await handleMcpToolCall(
            server: "codex_apps",
            toolName: "list",
            arguments: "",
            prepared: PreparedMcpToolCall(serverName: "codex_apps", toolName: "list", enabled: false),
            transport: { _ in mcpTextResult("unused") }
        )
        XCTAssertEqual(mcpToolResultText(blocked.result), "MCP tool call blocked by app configuration")
        XCTAssertEqual(blocked.toolInputJSON, "{}")

        let failed = await handleMcpToolCall(
            server: "linear",
            toolName: "search",
            arguments: #"{"query":"a"}"#,
            prepared: PreparedMcpToolCall(serverName: "linear", toolName: "search"),
            transport: { _ in throw McpToolCallFailure("not running") }
        )
        XCTAssertEqual(mcpToolResultText(failed.result), "tool call error: not running")

        let image = CallToolResult(
            content: [
                .object(["type": .string("image"), "data": .string("abc")]),
                .object(["type": .string("text"), "text": .string("caption")]),
            ],
            structuredContent: nil,
            isError: nil,
            meta: nil
        )
        let sanitized = await handleMcpToolCall(
            server: "linear",
            toolName: "search",
            arguments: "{}",
            prepared: PreparedMcpToolCall(serverName: "linear", toolName: "search"),
            inputModalities: [.text],
            transport: { request in
                XCTAssertEqual(request.argumentsJSON, "{}")
                return image
            }
        )
        XCTAssertEqual(
            mcpToolResultText(sanitized.result),
            "<image content omitted because you do not support image input>\ncaption"
        )
    }

    func testSessionMcpListsConnectsAndCallsTransport() async throws {
        let sess = Session()
        sess.services.mcpVisibleTools = [
            McpVisibleTool(name: "search", serverName: "srv"),
        ]
        var connected = false
        sess.services.ensureMcpConnected = {
            connected = true
        }
        sess.services.mcpToolTransport = { request in
            XCTAssertEqual(request.serverName, "srv")
            XCTAssertEqual(request.toolName, "search")
            return mcpTextResult("found")
        }
        XCTAssertEqual(sess.listMcpTools(), ["search"])
        await sess.ensureMcpConnected()
        XCTAssertTrue(connected)
        let handled = await sess.callMcpTool(server: "srv", toolName: "search", arguments: #"{"q":1}"#)
        XCTAssertEqual(mcpToolResultText(handled.result), "found")

        let handler = McpHandler(
            name: ToolName(plain: "search"),
            spec: .function(
                ResponsesApiTool(
                    name: "search",
                    description: "Search",
                    strict: false,
                    parameters: .object([:], additionalProperties: true)
                )
            ),
            serverName: "srv"
        )
        let output = try await handler.handle(
            ToolInvocation(
                callId: "c1",
                toolName: handler.toolName(),
                payload: .function(arguments: #"{"q":1}"#),
                mcpToolTransport: { _ in mcpTextResult("from-handler") }
            )
        )
        XCTAssertEqual(output.logOutput(), "from-handler")
        XCTAssertTrue(output.successForLogging())
    }
}

private func plannedRouter(config: Config = Config(), model: ModelInfo? = nil) -> ToolRouter {
    let turn = TurnContext(config: config, catalogModelInfo: model)
    return finalizeToolRouter(toolRouterPlanOptions(sess: nil, turnContext: turn))
}

private func plannedToolNames(config: Config = Config(), model: ModelInfo? = nil) -> Set<String> {
    Set(plannedRouter(config: config, model: model).registry.registeredEntries().map {
        flatToolName($0.runtime.toolName())
    })
}

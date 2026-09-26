import CodexCore
import CodexProtocol
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
}

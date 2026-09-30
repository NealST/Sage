@testable import Sage
import CodexCore
import CodexProtocol
import XCTest

final class ExecuteHarnessAttachTests: XCTestCase {
    func testSnapshotSplitsLastUserInputFromHistory() {
        let events = [
            AgentEvent(kind: .userInput, content: "first"),
            AgentEvent(kind: .assistantResponse, content: "ok"),
            AgentEvent(kind: .userInput, content: "second"),
        ]
        let snapshot = ExecuteHarnessAttach.snapshot(
            events: events,
            cwd: "/tmp/project",
            model: "gpt-5.1"
        )
        XCTAssertEqual(snapshot.cwd, "/tmp/project")
        XCTAssertEqual(snapshot.model, "gpt-5.1")
        XCTAssertEqual(snapshot.history.count, 2)
        XCTAssertEqual(snapshot.input.count, 1)
        XCTAssertEqual(assistantText(snapshot.history[1]), "ok")
        XCTAssertEqual(userText(snapshot.input[0]), "second")
        XCTAssertFalse(snapshot.history.contains { item in
            if case .message(_, let role, let content, _, _) = item, role == "user" {
                return content.contains { part in
                    if case .inputText(let text) = part { return text == "second" }
                    return false
                }
            }
            return false
        })
    }

    func testSnapshotMapsToolCallsAndResults() {
        let events = [
            AgentEvent(
                kind: .assistantResponse,
                content: "reading",
                toolCalls: [ToolCallRecord(id: "c1", name: "read_text_file", argumentsJSON: "{}")]
            ),
            AgentEvent(kind: .toolResult, content: "file body", toolCallID: "c1"),
        ]
        let snapshot = ExecuteHarnessAttach.snapshot(
            events: events,
            cwd: "/tmp",
            model: "gpt-5"
        )
        XCTAssertEqual(snapshot.input.count, 0)
        XCTAssertEqual(snapshot.history.count, 3)
        if case .functionCall(_, let name, _, _, _, let callId, _) = snapshot.history[1] {
            XCTAssertEqual(name, "read_text_file")
            XCTAssertEqual(callId, "c1")
        } else {
            XCTFail("expected function call")
        }
        if case .functionCallOutput(_, let callId, _, _, let payload, _) = snapshot.history[2] {
            XCTAssertEqual(callId, "c1")
            XCTAssertEqual(payload.body.toText(), "file body")
        } else {
            XCTFail("expected function call output")
        }
    }

    func testActTurnOpensWorkspaceWrite() {
        let context = ExecuteHarnessAttach.makeTurnContext(
            cwd: "/tmp/repo",
            model: "gpt-5",
            allowsMutation: true
        )
        XCTAssertEqual(context.cwd, "/tmp/repo")
        XCTAssertEqual(context.environment.cwd, "/tmp/repo")
        if case .workspaceWrite = context.sandboxPolicy {
        } else {
            XCTFail("expected workspace write sandbox")
        }
        if case .managed = context.permissionProfile {
        } else {
            XCTFail("expected managed workspace profile")
        }
    }

    func testResponseStreamEmitsFunctionCallsThenCompleted() {
        let stream = ExecuteHarnessAttach.responseStream(
            from: ModelTurn(
                content: "reading",
                toolCalls: [ToolCallProposal(id: "c1", name: "list_directory", argumentsJSON: "{}")]
            )
        )
        var events: [ResponseEvent] = []
        let done = expectation(description: "stream")
        Task {
            for await event in stream.events {
                if case .success(let value) = event {
                    events.append(value)
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(events.count, 3)
        if case .outputItemDone(.message(_, let role, _, _, _)) = events[0] {
            XCTAssertEqual(role, "assistant")
        } else {
            XCTFail("expected assistant message")
        }
        if case .outputItemDone(.functionCall(_, let name, _, _, _, let callId, _)) = events[1] {
            XCTAssertEqual(name, "list_directory")
            XCTAssertEqual(callId, "c1")
        } else {
            XCTFail("expected function call")
        }
        if case .completed(_, _, _, let endTurn) = events[2] {
            XCTAssertEqual(endTurn, true)
        } else {
            XCTFail("expected completed")
        }
    }

    func testSamplingResultRejectsToolCalls() {
        XCTAssertThrowsError(
            try ExecuteHarnessAttach.samplingResult(
                from: ModelTurn(
                    content: "x",
                    toolCalls: [ToolCallProposal(id: "t", name: "shell", argumentsJSON: "{}")]
                )
            )
        )
        let result = try? ExecuteHarnessAttach.samplingResult(
            from: ModelTurn(content: "  done  ", toolCalls: [])
        )
        XCTAssertEqual(result?.lastAgentMessage, "done")
        XCTAssertEqual(result?.needsFollowUp, false)
    }

    private func assistantText(_ item: ResponseItem) -> String? {
        if case .message(_, let role, let content, _, _) = item, role == "assistant" {
            for part in content {
                if case .outputText(let text) = part { return text }
            }
        }
        return nil
    }

    private func userText(_ input: SessionTurnInput) -> String? {
        if case .userInput(let content, _, _) = input {
            for part in content {
                if case .text(let text, _) = part { return text }
            }
        }
        return nil
    }
}

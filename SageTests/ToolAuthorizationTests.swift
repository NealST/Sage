@testable import Sage
import XCTest

final class SessionToolAllowlistTests: XCTestCase {
    func testCombinationKeyIsStableAfterKeyReorder() {
        let firstKey = SessionToolAllowlist.combinationKey(
            name: "run_shell_command",
            argumentsJSON: #"{"command":"ls","cwd":"~"}"#
        )
        let reorderedKey = SessionToolAllowlist.combinationKey(
            name: "run_shell_command",
            argumentsJSON: #"{"cwd":"~","command":"ls"}"#
        )
        XCTAssertEqual(firstKey, reorderedKey)
        XCTAssertEqual(firstKey.count, 64)
    }

    func testOnlyProtectedReadsAndMutationsNeedAGate() {
        XCTAssertFalse(
            SessionToolAllowlist.needsGate(
                name: "run_shell_command",
                argumentsJSON: #"{"command":"ls"}"#,
                policy: .home
            )
        )
        XCTAssertTrue(
            SessionToolAllowlist.needsGate(
                name: "run_shell_command",
                argumentsJSON: #"{"command":"touch file","allow_writes":true}"#,
                policy: .home
            )
        )
        XCTAssertTrue(
            SessionToolAllowlist.needsGate(
                name: "write_text_file",
                argumentsJSON: #"{"path":"~/note.txt","content":"hello"}"#,
                policy: .home
            )
        )
        XCTAssertFalse(
            SessionToolAllowlist.needsGate(
                name: "mcp__demo__search",
                argumentsJSON: "{}",
                policy: .home
            )
        )
    }

    func testMCPOnlyGatesDeclaredLocalWrites() {
        let readTool = mcpTool(name: "read", readOnly: true, localWrite: false)
        let writeTool = mcpTool(name: "write", readOnly: false, localWrite: true)

        XCTAssertFalse(
            SessionToolAllowlist.needsGate(
                name: readTool.qualifiedName,
                argumentsJSON: #"{"path":"~/note.txt"}"#,
                policy: .home,
                mcpTools: [readTool, writeTool]
            )
        )
        XCTAssertTrue(
            SessionToolAllowlist.needsGate(
                name: writeTool.qualifiedName,
                argumentsJSON: #"{"path":"~/note.txt"}"#,
                policy: .home,
                mcpTools: [readTool, writeTool]
            )
        )
    }

    private func mcpTool(name: String, readOnly: Bool, localWrite: Bool) -> MCPToolInfo {
        MCPToolInfo(
            serverID: "server",
            serverName: "files",
            name: name,
            description: name,
            inputSchema: .object([:]),
            readOnlyHint: readOnly,
            localWriteHint: localWrite
        )
    }
}

final class SessionToolAllowlistActorTests: XCTestCase {
    func testTaskGrantCoversTheSameWriteDirectory() async {
        await MainActor.run {
            let list = makeAllowlist()
            let args = #"{"path":"~/Documents/note.txt","content":"hello"}"#
            XCTAssertFalse(list.contains(
                name: "write_text_file",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            ))
            list.allowThisTask(
                name: "write_text_file",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            )
            XCTAssertTrue(list.contains(
                name: "write_text_file",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            ))
        }
    }

    func testAllowOnceIsConsumedExactlyOnce() async {
        await MainActor.run {
            let list = makeAllowlist()
            let args = #"{"command":"curl example.com","allow_network":true}"#
            list.allowOnce(name: "run_shell_command", argumentsJSON: args)
            XCTAssertTrue(list.consumeApproval(
                name: "run_shell_command",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            ))
            XCTAssertFalse(list.consumeApproval(
                name: "run_shell_command",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            ))
        }
    }

    @MainActor
    private func makeAllowlist() -> SessionToolAllowlist {
        let suite = "SessionToolAllowlistTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SessionToolAllowlist(grantStore: ToolAuthorizationGrantStore(defaults: defaults))
    }
}

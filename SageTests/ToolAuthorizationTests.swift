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

    func testSensitiveCopySeparatesReadSourceFromWriteDestination() {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "copy_file",
            argumentsJSON: """
            {"source":"~/.ssh/id_ed25519","destination":"~/Documents/key.backup"}
            """,
            policy: .home
        )

        XCTAssertEqual(
            requirement?.roots(for: .sensitiveRead),
            [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh").path]
        )
        XCTAssertEqual(
            requirement?.roots(for: .localWrite),
            [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path]
        )
    }

    func testRecursiveSearchFromHomeRequiresProtectedDescendantAuthorization() {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "search_files",
            argumentsJSON: #"{"path":"~","name_pattern":"*"}"#,
            policy: .home
        )

        let protectedRoots = Set(SensitiveResourcePolicy.roots.map { root in
            root.standardizedFileURL.resolvingSymlinksInPath().path
        })
        XCTAssertEqual(Set(requirement?.roots(for: .sensitiveRead) ?? []), protectedRoots)
    }

    func testRenameRejectsPathComponentsBeforeApproval() {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "rename_file",
            argumentsJSON: #"{"path":"~/Documents/note.txt","new_name":"../escaped.txt"}"#,
            policy: .home
        )

        XCTAssertNotNil(requirement?.validationError)
        XCTAssertEqual(requirement?.roots(for: .localWrite), [])
    }

    func testMoveAuthorizesResolvedSourceAndDestinationDirectories() {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "move_file",
            argumentsJSON: #"{"source":"~/.ssh/id_ed25519","destination":"~/Documents/key"}"#,
            policy: .home
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expectedWrites = [
            home.appendingPathComponent(".ssh").path,
            home.appendingPathComponent("Documents").path,
        ].sorted()

        XCTAssertEqual(requirement?.roots(for: .localWrite), expectedWrites)
        XCTAssertEqual(
            requirement?.roots(for: .sensitiveRead),
            [home.appendingPathComponent(".ssh").path]
        )
    }

    func testInvalidShellWorkingDirectoryDoesNotCreateBroadGrant() {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "run_shell_command",
            argumentsJSON: #"{"command":"touch x","working_directory":"/tmp","allow_writes":true}"#,
            policy: .home
        )

        XCTAssertNotNil(requirement?.validationError)
        XCTAssertEqual(requirement?.roots(for: .localWrite), [])
    }

    func testNestedMetadataIsProtected() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/App")
        let nestedGit = root.appendingPathComponent("Vendor/Package/.git/config").path

        XCTAssertTrue(
            PathGuard.isProtectedWritePath(nestedGit, policy: .project(root: root))
        )
    }

    func testMCPDirectoryGrantDoesNotWidenToParent() {
        let tool = mcpTool(name: "write", readOnly: false, localWrite: true)
        let requirement = ToolAuthorizationPolicy.requirement(
            name: tool.qualifiedName,
            argumentsJSON: #"{"options":{"directory":"~/Documents/Exports"}}"#,
            policy: .home,
            mcpTools: [tool]
        )

        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Exports").path
        XCTAssertEqual(requirement?.roots(for: .localWrite), [expected])
    }

    func testMCPInfersLocalWriteWithoutCustomHint() {
        let tool = mcpTool(name: "write", readOnly: false, localWrite: false)
        let requirement = ToolAuthorizationPolicy.requirement(
            name: tool.qualifiedName,
            argumentsJSON: #"{"path":"~/Documents/note.txt"}"#,
            policy: .home,
            mcpTools: [tool]
        )

        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents").path
        XCTAssertEqual(requirement?.roots(for: .localWrite), [expected])
    }

    func testRelocatingProtectedRootFailsClosed() {
        let requirement = ToolAuthorizationPolicy.requirement(
            name: "move_file",
            argumentsJSON: #"{"source":"~/.ssh","destination":"~/Documents/stolen-ssh"}"#,
            policy: .home
        )

        XCTAssertNotNil(requirement?.validationError)
        XCTAssertEqual(requirement?.roots(for: .localWrite), [])
    }

    func testUnknownMCPWriteScopeDoesNotFallBackToHome() {
        let tool = mcpTool(name: "write", readOnly: false, localWrite: true)
        let requirement = ToolAuthorizationPolicy.requirement(
            name: tool.qualifiedName,
            argumentsJSON: #"{"content":"hello"}"#,
            policy: .home,
            mcpTools: [tool]
        )

        XCTAssertEqual(requirement?.roots(for: .localWrite), [])
    }

    func testSaveSkillRequiresLocalWriteAuthorization() {
        XCTAssertTrue(
            SessionToolAllowlist.needsGate(
                name: "save_skill",
                argumentsJSON: """
                {"action":"create","name":"demo","description":"Demo","body":"Body"}
                """,
                policy: .home
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

    func testDirectoryGrantSurvivesTaskSwitch() async {
        await MainActor.run {
            let list = makeAllowlist()
            let args = #"{"path":"~/Documents/note.txt","content":"hello"}"#
            list.allowThisTask(
                name: "write_text_file",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            )
            list.reset()
            XCTAssertTrue(list.contains(
                name: "write_text_file",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-b"
            ))
        }
    }

    func testAllowOnceIsConsumedExactlyOnce() async {
        await MainActor.run {
            let list = makeAllowlist()
            let args = #"{"command":"curl example.com","allow_network":true}"#
            list.allowCapabilityOnce(
                name: "run_shell_command",
                argumentsJSON: args,
                policy: .home
            )
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

    func testHookApprovalIsIndependentFromCapabilityApproval() async {
        await MainActor.run {
            let list = makeAllowlist()
            let args = #"{"path":"~/Documents"}"#

            XCTAssertTrue(list.contains(
                name: "list_directory",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            ))
            XCTAssertFalse(list.containsHookApproval(
                name: "list_directory",
                argumentsJSON: args,
                hookIdentity: "hook-a",
                scopeID: "task-a"
            ))

            list.allowHookOnce(
                name: "list_directory",
                argumentsJSON: args,
                hookIdentity: "hook-a"
            )
            XCTAssertTrue(list.consumeHookApproval(
                name: "list_directory",
                argumentsJSON: args,
                hookIdentity: "hook-a",
                scopeID: "task-a"
            ))
            XCTAssertFalse(list.consumeHookApproval(
                name: "list_directory",
                argumentsJSON: args,
                hookIdentity: "hook-a",
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

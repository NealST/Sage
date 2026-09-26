//
//  Phase8GuardianSkillsTests.swift
//  Phase8GuardianSkillsTests
//
//  Sage addition (no codex counterpart).
//  Phase 8 context-fragments, agent-roles, hooks, and elicitation tests.
//

import CodexAgentRoles
import CodexCore
import CodexHooks
import CodexProtocol
import CodexUtils
import FileSystem
import Foundation
import XCTest

final class Phase8GuardianSkillsTests: XCTestCase {
    func testAdditionalContextUserFragmentRenderAndMatch() {
        let fragment = AdditionalContextUserFragment(key: "cwd", value: "/tmp/project")
        XCTAssertEqual(fragment.role, "user")
        XCTAssertEqual(fragment.contentKind.value, "additional_content.cwd")
        XCTAssertEqual(fragment.render(), "<external_cwd>/tmp/project</external_cwd>")
        XCTAssertTrue(AdditionalContextUserFragment.matchesText(fragment.render()))
        XCTAssertFalse(AdditionalContextUserFragment.matchesText("plain text"))
    }

    func testAdditionalContextDeveloperFragmentIsUnmarked() {
        let fragment = AdditionalContextDeveloperFragment(key: "note", value: "hello")
        XCTAssertEqual(fragment.role, "developer")
        XCTAssertEqual(fragment.render(), "<note>hello</note>")
        XCTAssertFalse(AdditionalContextDeveloperFragment.matchesText(fragment.render()))
    }

    func testAnnotatedContentRoundTrip() {
        var item = ResponseItem.message(
            id: nil,
            role: "user",
            content: [.inputText(text: "one"), .inputText(text: "two")],
            phase: nil,
            internalChatMessageMetadataPassthrough: InternalChatMessageMetadataPassthrough(
                contentItemKinds: [ContentItemKind("generic.one")]
            )
        )
        let annotated = toAnnotatedContent(&item)
        XCTAssertEqual(annotated?.count, 2)
        XCTAssertEqual(annotated?[0].kind.value, "generic.one")
        XCTAssertEqual(annotated?[1].kind.value, "unknown")
        guard case .message(_, _, let emptied, _, _) = item else {
            return XCTFail("expected message")
        }
        XCTAssertTrue(emptied.isEmpty)

        XCTAssertTrue(setAnnotatedContent(&item, annotated ?? []))
        guard case .message(_, _, let content, _, let metadata) = item else {
            return XCTFail("expected message")
        }
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(metadata?.contentItemKinds?.map(\.value), ["generic.one", "unknown"])
    }

    func testAnsweredQuestionBoundsUnicodeAndKeepsEnvelope() throws {
        let text = String(repeating: "é\n", count: 1_000)
        let id = #"["request_user_input_async","message",1]"#
        let answer = "A \"quoted\" answer\nwith a second line"
        let fragment = AnsweredQuestion(questionId: id, question: text, answer: answer)
        let body = fragment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [[String: Any]]
        XCTAssertEqual(json?.count, 1)
        XCTAssertEqual(json?[0]["questionItemId"] as? String, id)
        XCTAssertEqual(json?[0]["answer"] as? String, answer)
        let expectedQuestion = floorCharBoundaryForTest(text, maxBytes: 512)
            .replacingOccurrences(of: "\n", with: " ")
        XCTAssertEqual(json?[0]["question"] as? String, expectedQuestion)
    }

    func testRecapPromptBoundsTheEntireUtf8Fragment() {
        for history in [String(repeating: "a", count: 40_000), String(repeating: "進捗🦀", count: 10_000)] {
            let prompt = RecapPrompt(history: history).render()
            XCTAssertLessThanOrEqual(prompt.utf8.count, RecapPrompt.MAX_BYTES)
            XCTAssertLessThanOrEqual(approxTokenCount(prompt), RecapPrompt.MAX_ESTIMATED_TOKENS)
            let retained = prompt.components(separatedBy: "Conversation:\n").last ?? ""
            XCTAssertTrue(history.hasPrefix(retained))
            XCTAssertLessThan(RecapPrompt.MAX_BYTES - prompt.utf8.count, 4)
        }
    }

    func testRecapPromptPreservesHistoryThatFits() {
        let history = "User: Fix the parser.\n\nAssistant: Done. What should happen on empty input?"
        let prompt = RecapPrompt(history: history).render()
        XCTAssertEqual(prompt.components(separatedBy: "Conversation:\n").last, history)
    }

    func testRenderedFragmentBecomesResponseItem() {
        let fragment = AdditionalContextUserFragment(key: "cwd", value: "/tmp")
        let item = fragment.asResponseItem()
        guard case .message(_, let role, let content, _, let metadata) = item else {
            return XCTFail("expected message")
        }
        XCTAssertEqual(role, "user")
        XCTAssertEqual(content, [.inputText(text: fragment.render())])
        XCTAssertEqual(metadata?.contentItemKinds, [fragment.contentKind])
    }

    func testParseAgentRoleFileContents() throws {
        let toml = """
        name = "reviewer"
        description = "Reviews diffs"
        nickname_candidates = ["Rev", "Review-Bot"]
        developer_instructions = \"\"\"You review code.\"\"\"
        model = "gpt-5"
        """
        let parsed = try parseAgentRoleFileContents(
            toml,
            roleFileLabel: "/tmp/reviewer.toml",
            configBaseDir: "/tmp",
            roleNameHint: nil
        )
        XCTAssertEqual(parsed.roleName, "reviewer")
        XCTAssertEqual(parsed.description, "Reviews diffs")
        XCTAssertEqual(parsed.nicknameCandidates, ["Rev", "Review-Bot"])
        XCTAssertEqual(parsed.config["developer_instructions"]?.asString(), "You review code.")
        XCTAssertEqual(parsed.config["model"]?.asString(), "gpt-5")
        XCTAssertNil(parsed.config["name"])
    }

    func testParseAgentRoleFileRequiresNameAndInstructions() {
        XCTAssertThrowsError(
            try parseAgentRoleFileContents(
                "description = \"x\"\ndeveloper_instructions = \"y\"\n",
                roleFileLabel: "/tmp/role.toml",
                configBaseDir: "/tmp",
                roleNameHint: nil
            )
        )
        XCTAssertThrowsError(
            try parseAgentRoleFileContents(
                "name = \"x\"\ndescription = \"y\"\n",
                roleFileLabel: "/tmp/role.toml",
                configBaseDir: "/tmp",
                roleNameHint: nil
            )
        )
        XCTAssertNoThrow(
            try parseAgentRoleFileContents(
                "description = \"y\"\n",
                roleFileLabel: "/tmp/role.toml",
                configBaseDir: "/tmp",
                roleNameHint: "hinted"
            )
        )
    }

    func testNicknameCandidatesRejectDuplicatesAndInvalidChars() {
        XCTAssertThrowsError(
            try parseAgentRoleFileContents(
                """
                name = "x"
                description = "y"
                developer_instructions = "z"
                nickname_candidates = ["A", "A"]
                """,
                roleFileLabel: "/tmp/role.toml",
                configBaseDir: "/tmp",
                roleNameHint: nil
            )
        )
        XCTAssertThrowsError(
            try parseAgentRoleFileContents(
                """
                name = "x"
                description = "y"
                developer_instructions = "z"
                nickname_candidates = ["bad!"]
                """,
                roleFileLabel: "/tmp/role.toml",
                configBaseDir: "/tmp",
                roleNameHint: nil
            )
        )
    }

    func testCollectAgentRoleFilesWalksTomlTree() async throws {
        let fs = MemoryExecutorFileSystem()
        let root = try AbsolutePathBuf.fromAbsolutePath("/roles")
        fs.addDirectory("/roles")
        fs.addDirectory("/roles/nested")
        fs.addFile("/roles/a.toml", contents: "name = \"a\"")
        fs.addFile("/roles/nested/b.toml", contents: "name = \"b\"")
        fs.addFile("/roles/skip.txt", contents: "nope")
        let files = try await collectAgentRoleFiles(fs: fs, dir: root)
        XCTAssertEqual(files.map(\.path), ["/roles/a.toml", "/roles/nested/b.toml"])
    }

    func testLoadAgentRolesFromDirectory() async throws {
        let fs = MemoryExecutorFileSystem()
        fs.addDirectory("/cfg")
        fs.addDirectory("/cfg/agents")
        fs.addFile(
            "/cfg/agents/reviewer.toml",
            contents: """
            name = "reviewer"
            description = "Reviews diffs"
            developer_instructions = "Review carefully."
            """
        )
        var warnings: [String] = []
        let roles = try await loadAgentRoles(
            fs: fs,
            declaredRoles: [:],
            agentsDirectories: [try AbsolutePathBuf.fromAbsolutePath("/cfg/agents")],
            startupWarnings: &warnings
        )
        XCTAssertEqual(roles["reviewer"]?.description, "Reviews diffs")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testLoadAgentRolesLayerStackThrows() async {
        let fs = MemoryExecutorFileSystem()
        var warnings: [String] = []
        do {
            _ = try await loadAgentRoles(
                fs: fs,
                configLayerStackPresent: true,
                startupWarnings: &warnings
            )
            XCTFail("expected unsupported layer stack")
        } catch let error as IOError {
            XCTAssertTrue(error.message.contains("ConfigLayerStack"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHookKeyAndPayloadWireShape() throws {
        XCTAssertEqual(
            hookKey(keySource: "user", eventName: "PreToolUse", groupIndex: 1, handlerIndex: 2),
            "user:pre_tool_use:1:2"
        )
        let sessionId = ThreadId()
        let threadId = ThreadId()
        let cwd = AbsolutePathTestSupport.abs("/tmp")
        let payload = HookPayload(
            sessionId: sessionId,
            cwd: cwd,
            triggeredAt: Date(timeIntervalSince1970: 1_735_689_600),
            hookEvent: .afterAgent(
                HookEventAfterAgent(
                    threadId: threadId,
                    turnId: "turn-1",
                    inputMessages: ["hello"],
                    lastAssistantMessage: "hi"
                )
            )
        )
        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["session_id"] as? String, sessionId.description)
        XCTAssertEqual(object?["cwd"] as? String, "/tmp")
        XCTAssertEqual(object?["triggered_at"] as? String, "2025-01-01T00:00:00Z")
        let event = object?["hook_event"] as? [String: Any]
        XCTAssertEqual(event?["event_type"] as? String, "after_agent")
        XCTAssertEqual(event?["turn_id"] as? String, "turn-1")
    }

    func testMentionSyntaxReexportsUtilsSigils() {
        XCTAssertEqual(TOOL_MENTION_SIGIL, "$")
        XCTAssertEqual(PLUGIN_TEXT_MENTION_SIGIL, "@")
    }

    func testElicitationPausesUntilRegistrationsDrop() async {
        let service = ElicitationService()
        await service.waitUntilClear()
        let first = service.register()
        let second = service.register()
        var paused = false
        let subscribe = service.subscribe()
        for await value in subscribe {
            paused = value
            break
        }
        XCTAssertTrue(paused)
        _ = first
        _ = second
    }

    func testCoreHookMcpExecutorThrowsUntilRuntime() async {
        let executor = CoreHookMcpExecutor(threadId: ThreadId())
        do {
            _ = try await executor.execute(
                HookMcpCall(server: "srv", tool: "tool", timeout: 1)
            )
            XCTFail("expected unsupported MCP runtime")
        } catch is CodexErr {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

func floorCharBoundaryForTest(_ text: String, maxBytes: Int) -> String {
    if maxBytes <= 0 { return "" }
    if text.utf8.count <= maxBytes { return text }
    var used = 0
    var end = text.startIndex
    for character in text {
        let size = character.utf8.count
        if used + size > maxBytes { break }
        used += size
        end = text.index(after: end)
    }
    return String(text[..<end])
}

final class MemoryExecutorFileSystem: ExecutorFileSystem, @unchecked Sendable {
    private var directories = Set<String>(["/"])
    private var files: [String: String] = [:]

    func addDirectory(_ path: String) {
        directories.insert(path)
        var parent = (path as NSString).deletingLastPathComponent
        while parent != path && !parent.isEmpty {
            directories.insert(parent)
            let next = (parent as NSString).deletingLastPathComponent
            if next == parent { break }
            parent = next
        }
    }

    func addFile(_ path: String, contents: String) {
        addDirectory((path as NSString).deletingLastPathComponent)
        files[path] = contents
    }

    func canonicalize(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> PathUri {
        _ = sandbox
        return path
    }

    func readFile(
        _ path: PathUri,
        options: ReadFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> [UInt8] {
        _ = options
        _ = sandbox
        let native = path.inferredNativePathString()
        guard let contents = files[native] else {
            throw IOError.notFound(native)
        }
        return Array(contents.utf8)
    }

    func readFileStream(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> FileSystemReadStream {
        _ = path
        _ = sandbox
        throw IOError.other("readFileStream is unused in Phase 8 tests")
    }

    func writeFile(
        _ path: PathUri,
        contents: [UInt8],
        options: WriteFileOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {
        _ = path
        _ = contents
        _ = options
        _ = sandbox
        throw IOError.other("writeFile is unused in Phase 8 tests")
    }

    func createDirectory(
        _ path: PathUri,
        options: CreateDirectoryOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {
        _ = path
        _ = options
        _ = sandbox
        throw IOError.other("createDirectory is unused in Phase 8 tests")
    }

    func getMetadata(
        _ path: PathUri,
        options: GetMetadataOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> FileMetadata {
        _ = options
        _ = sandbox
        let native = path.inferredNativePathString()
        if files[native] != nil {
            return FileMetadata(
                isDirectory: false,
                isFile: true,
                isSymlink: false,
                size: 0,
                createdAtMs: 0,
                modifiedAtMs: 0
            )
        }
        if directories.contains(native) {
            return FileMetadata(
                isDirectory: true,
                isFile: false,
                isSymlink: false,
                size: 0,
                createdAtMs: 0,
                modifiedAtMs: 0
            )
        }
        throw IOError.notFound(native)
    }

    func readDirectory(
        _ path: PathUri,
        sandbox: FileSystemSandboxContext?
    ) async throws -> [ReadDirectoryEntry] {
        _ = sandbox
        let native = path.inferredNativePathString()
        if !directories.contains(native) {
            throw IOError.notFound(native)
        }
        var entries: [ReadDirectoryEntry] = []
        var seen = Set<String>()
        let prefix = native == "/" ? "/" : native + "/"
        for directory in directories where directory.hasPrefix(prefix) && directory != native {
            let rest = String(directory.dropFirst(prefix.count))
            let name = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
            if let name, seen.insert(name).inserted, !rest.contains("/") {
                entries.append(ReadDirectoryEntry(fileName: name, isDirectory: true, isFile: false))
            }
        }
        for file in files.keys where file.hasPrefix(prefix) {
            let rest = String(file.dropFirst(prefix.count))
            if !rest.contains("/"), seen.insert(rest).inserted {
                entries.append(ReadDirectoryEntry(fileName: rest, isDirectory: false, isFile: true))
            }
        }
        return entries
    }

    func walk(
        _ path: PathUri,
        options: WalkOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws -> WalkOutcome {
        _ = path
        _ = options
        _ = sandbox
        throw IOError.other("walk is unused in Phase 8 tests")
    }

    func remove(
        _ path: PathUri,
        options: RemoveOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {
        _ = path
        _ = options
        _ = sandbox
        throw IOError.other("remove is unused in Phase 8 tests")
    }

    func copy(
        sourcePath: PathUri,
        destinationPath: PathUri,
        options: CopyOptions,
        sandbox: FileSystemSandboxContext?
    ) async throws {
        _ = sourcePath
        _ = destinationPath
        _ = options
        _ = sandbox
        throw IOError.other("copy is unused in Phase 8 tests")
    }
}

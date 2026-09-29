//
//  Phase8GuardianSkillsTests.swift
//  Phase8GuardianSkillsTests
//
//  Sage addition (no codex counterpart).
//  Phase 8 context-fragments, agent-roles, hooks, skills, and AGENTS.md tests.
//

import CodexAgentRoles
import CodexCore
import CodexHooks
import CodexProtocol
import CodexSkills
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
            hookKey(keySource: "user", eventName: .preToolUse, groupIndex: 1, handlerIndex: 2),
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

    func testSkillFrontmatterRepairsColonsAndKeepsBlockScalars() throws {
        let repaired = try parseSkillFrontmatterMetadata(
            """
            ---
            name:  deploy  service
            description: Build for AWS: ECS
            metadata:
              short-description:  Deploy   safely
            ---

            """,
            defaultName: { "fallback" }
        )
        XCTAssertEqual(repaired.name, "deploy service")
        XCTAssertEqual(repaired.description, "Build for AWS: ECS")
        XCTAssertEqual(repaired.shortDescription, "Deploy safely")

        let block = try parseSkillFrontmatterMetadata(
            """
            ---
            name: block
            description: |-
              Build for AWS: ECS
            argument-hint: <duration: e.g. 7d>
            ---

            """,
            defaultName: { "fallback" }
        )
        XCTAssertEqual(block.description, "Build for AWS: ECS")

        XCTAssertThrowsError(
            try parseSkillFrontmatterMetadata("---\nname: demo\n---\n", defaultName: { "fallback" })
        ) { error in
            XCTAssertEqual(String(describing: error), "missing field `description`")
        }
    }

    func testExtractToolMentionsSkipsEnvVarsAndKeepsLinkedPaths() {
        let mentions = extractToolMentions("use $PATH and $alpha and [$beta](/tmp/beta)")
        XCTAssertEqual(mentions.names, ["alpha", "beta"])
        XCTAssertEqual(mentions.paths, ["/tmp/beta"])
        XCTAssertEqual(pluginConfigNameFromPath("plugin://sample@test?app=com.example.editor"), "sample@test")
    }

    func testHookMatcherExactPipeAndRegex() throws {
        XCTAssertTrue(matchesMatcher(nil, input: "Bash"))
        XCTAssertTrue(matchesMatcher("*", input: "Bash"))
        XCTAssertTrue(matchesMatcher("Edit|Write", input: "Edit"))
        XCTAssertFalse(matchesMatcher("Edit|Write", input: "Bash"))
        XCTAssertTrue(matchesMatcher("^Bash", input: "BashOutput"))
        XCTAssertFalse(matchesMatcher("^Bash$", input: "BashOutput"))
        XCTAssertThrowsError(try validateMatcherPattern("["))
        XCTAssertEqual(matcherPatternForEvent(.userPromptSubmit, matcher: "^hello"), nil)
        XCTAssertEqual(matcherPatternForEvent(.preToolUse, matcher: "Bash"), "Bash")
    }

    func testPluginHookDeclarationsUsePersistedKeys() {
        let declarations = pluginHookDeclarations([
            PluginHookSource(
                pluginId: "demo@test",
                sourceRelativePath: "hooks/hooks.json",
                groupsByEvent: [
                    (.preToolUse, [PluginHookMatcherGroup(handlerCount: 2)]),
                    (.sessionStart, [PluginHookMatcherGroup(handlerCount: 1)]),
                ]
            )
        ])
        XCTAssertEqual(
            declarations.map(\.key),
            [
                "demo@test:hooks/hooks.json:pre_tool_use:0:0",
                "demo@test:hooks/hooks.json:pre_tool_use:0:1",
                "demo@test:hooks/hooks.json:session_start:0:0",
            ]
        )
    }

    func testLoadedAgentsMdInsertsProjectSeparator() {
        var loaded = LoadedAgentsMd.fromUserInstructions(Instructions(text: "user rules"))
        loaded.entries = [
            InstructionEntry(
                contents: "project rules",
                provenance: .project(
                    sourcePath: PathUri.fromAbsPath(AbsolutePathTestSupport.abs("/tmp/AGENTS.md")),
                    environmentId: "local",
                    cwd: PathUri.fromAbsPath(AbsolutePathTestSupport.abs("/tmp"))
                )
            )
        ]
        XCTAssertEqual(loaded.text(), "user rules\n\n--- project-doc ---\n\nproject rules")
    }

    func testCandidateFilenamesIgnorePathSyntax() {
        let cwd = PathUri.fromAbsPath(AbsolutePathTestSupport.abs("/tmp"))
        XCTAssertEqual(
            candidateFilenames(cwd: cwd, fallbackFilenames: ["NOTES.md", "../escape", "AGENTS.md"]),
            [LOCAL_AGENTS_MD_FILENAME, DEFAULT_AGENTS_MD_FILENAME, "NOTES.md"]
        )
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

    func testRequiredMcpServersAndMentionedPluginsCollectsSkillAndPluginDeps() {
        var skills = SessionSkillsLookup()
        skills.insertHostSkill(
            name: "deploy",
            path: "/tmp/deploy/SKILL.md",
            prompt: "Deploy the service.",
            pluginId: "weather",
            mcpServers: ["deploy-mcp"]
        )
        let plugins = [
            PluginCapabilitySummary(
                configName: "weather",
                displayName: "Weather",
                hasSkills: true,
                mcpServerNames: ["weather-mcp"]
            ),
        ]
        let result = requiredMcpServersAndMentionedPlugins(
            userInput: [
                .mention(name: "weather", path: "plugin://weather"),
                .skill(name: "deploy", path: "/tmp/deploy/SKILL.md"),
                .mention(name: "linear", path: "mcp://linear/issues"),
            ],
            plugins: plugins,
            skills: skills,
            connectors: []
        )
        XCTAssertEqual(Set(result.servers), ["weather-mcp", "deploy-mcp", "linear"])
        XCTAssertEqual(result.plugins.map(\.configName), ["weather"])
    }

    func testBuildSkillAndPluginInjectionItemsRendersHostSkillAndPlugin() {
        var skills = SessionSkillsLookup()
        skills.insertHostSkill(
            name: "deploy",
            path: "/tmp/deploy/SKILL.md",
            prompt: "Deploy the service."
        )
        let plugins = [
            PluginCapabilitySummary(
                configName: "weather",
                displayName: "Weather",
                hasSkills: true
            ),
        ]
        let result = buildSkillAndPluginInjectionItems(
            userInput: [
                .mention(name: "weather", path: "plugin://weather"),
                .skill(name: "deploy", path: "/tmp/deploy/SKILL.md"),
            ],
            mentionedPlugins: plugins,
            skills: skills,
            mcpTools: [],
            connectors: []
        )
        XCTAssertTrue(result.items.contains { item in
            if case .message(_, _, let content, _, _) = item {
                return content.contains { part in
                    if case .inputText(let text) = part {
                        return text.contains("<skill>") && text.contains("Deploy the service.")
                    }
                    return false
                }
            }
            return false
        })
        XCTAssertTrue(result.items.contains { item in
            if case .message(_, _, let content, _, _) = item {
                return content.contains { part in
                    if case .inputText(let text) = part {
                        return text.contains("`Weather` plugin")
                    }
                    return false
                }
            }
            return false
        })
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testBuildCompactedHistoryKeepsUserMessagesAndAppendsSummary() {
        let users = collectUserMessages([
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "first")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "ignored")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
            .message(
                id: nil,
                role: "user",
                content: [.inputText(text: "second")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ),
        ])
        XCTAssertEqual(users.map(\.message), ["first", "second"])
        let compacted = buildCompactedHistory(userMessages: users, summaryText: "folded")
        XCTAssertEqual(compacted.count, 3)
        XCTAssertEqual(contentItemsToText(messageContent(compacted[0].item)), "first")
        XCTAssertEqual(contentItemsToText(messageContent(compacted[1].item)), "second")
        XCTAssertEqual(compacted[2].item, wrapCompactionSummary("folded"))
    }

    func testBuildCompactedHistoryUsesPlaceholderWhenSummaryEmpty() {
        let compacted = buildCompactedHistory(userMessages: [], summaryText: "")
        XCTAssertEqual(compacted.count, 1)
        XCTAssertEqual(contentItemsToText(messageContent(compacted[0].item)), compactNoSummaryAvailable)
    }

    func testParseTurnItemMapsAssistantReasoningAndWebSearch() {
        let assistant = parseTurnItem(.message(
            id: .fromServer("msg_1"),
            role: "assistant",
            content: [.outputText(text: "hi")],
            phase: .commentary,
            internalChatMessageMetadataPassthrough: nil
        ))
        guard case .agentMessage(let message) = assistant else {
            return XCTFail("expected agent message")
        }
        XCTAssertEqual(message.id, "msg_1")
        XCTAssertEqual(message.phase, .commentary)

        let reasoning = parseTurnItem(.reasoning(
            id: .fromServer("rsn_1"),
            summary: [.summaryText(text: "think")],
            content: [.text(text: "raw")],
            encryptedContent: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        guard case .reasoning(let item) = reasoning else {
            return XCTFail("expected reasoning")
        }
        XCTAssertEqual(item.summaryText, ["think"])
        XCTAssertEqual(item.rawContent, ["raw"])

        let search = parseTurnItem(.webSearchCall(
            id: .fromServer("ws_1"),
            status: nil,
            action: .search(query: "codex", queries: nil),
            internalChatMessageMetadataPassthrough: nil
        ))
        guard case .webSearch(let web) = search else {
            return XCTFail("expected web search")
        }
        XCTAssertEqual(web.query, "codex")
    }

    func testCollectRemoteCompactSummaryUsesLastAssistant() async throws {
        let stream = ResponseStream(events: AsyncStream { continuation in
            continuation.yield(.success(.outputItemDone(.message(
                id: nil,
                role: "assistant",
                content: [.outputText(text: "remote fold")],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            ))))
            continuation.yield(.success(.completed(
                responseId: "c1",
                tokenUsage: nil,
                usageMetadata: nil,
                endTurn: true
            )))
            continuation.finish()
        })
        let summary = try await collectRemoteCompactSummary(from: stream)
        XCTAssertEqual(summary, "remote fold")
    }

    func testHistoryItemGroupsAttachImageResizeNotice() {
        let user = ResponseItemEnvelope(.message(
            id: nil,
            role: "user",
            content: [.inputText(text: "hi")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        let notice = ResponseItemEnvelope(.message(
            id: nil,
            role: "developer",
            content: [.inputText(text: "<image_resize_notice>resized</image_resize_notice>")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        let groups = historyItemGroups([user, notice])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].attachedNotice, notice)
    }

    func testBuildV2CompactedHistoryKeepsUserDropsAssistant() {
        let user = ResponseItemEnvelope(.message(
            id: nil,
            role: "user",
            content: [.inputText(text: "keep")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        let assistant = ResponseItemEnvelope(.message(
            id: nil,
            role: "assistant",
            content: [.outputText(text: "chatter")],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        let compacted = buildV2CompactedHistory(
            promptInput: [user, assistant],
            compactionOutput: wrapCompactionSummary("folded")
        )
        XCTAssertEqual(compacted.count, 2)
        XCTAssertEqual(contentItemsToText(messageContent(compacted[0].item)), "keep")
        XCTAssertEqual(compacted[1].item, wrapCompactionSummary("folded"))
    }

    func testTrimFunctionCallHistoryRewritesOversizedOutput() {
        let history = ContextManager()
        history.recordItems([
            .functionCallOutput(
                id: nil,
                callId: "c1",
                name: "exec",
                namespace: nil,
                output: FunctionCallOutputPayload(body: .text(String(repeating: "x", count: 200))),
                internalChatMessageMetadataPassthrough: nil
            )
        ])
        let result = trimFunctionCallHistoryToFitContextWindow(
            history: history,
            contextWindow: 10,
            baseInstructions: ""
        )
        XCTAssertEqual(result.rewrittenOutputs, 1)
        if case .functionCallOutput(_, _, _, _, let output, _) = history.items[0].item {
            XCTAssertEqual(output.body.toText(), contextWindowTruncatedOutputMessage)
        } else {
            XCTFail("expected rewritten function output")
        }
    }

    func testCollectRemoteCompactionV2RejectsMultipleCompactionItems() async {
        let stream = ResponseStream(events: AsyncStream { continuation in
            continuation.yield(.success(.outputItemDone(.compaction(
                id: nil,
                encryptedContent: "one",
                internalChatMessageMetadataPassthrough: nil
            ))))
            continuation.yield(.success(.outputItemDone(.compaction(
                id: nil,
                encryptedContent: "two",
                internalChatMessageMetadataPassthrough: nil
            ))))
            continuation.yield(.success(.completed(
                responseId: "c2",
                tokenUsage: nil,
                usageMetadata: nil,
                endTurn: true
            )))
            continuation.finish()
        })
        do {
            _ = try await collectRemoteCompactionV2Output(from: stream)
            XCTFail("expected fatal for multiple compaction items")
        } catch let error as CodexErr {
            XCTAssertTrue(String(describing: error).contains("exactly one compaction"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTruncateMessageToTokenBudgetKeepsLaterImageAtomically() {
        let envelope = ResponseItemEnvelope(.message(
            id: nil,
            role: "user",
            content: [
                .inputText(text: String(repeating: "old ", count: 80)),
                .inputText(text: "<image>"),
                .inputImage(image: .inline(imageUrl: "https://example.com/a.png"), detail: .high),
                .inputText(text: "</image>"),
            ],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        ))
        let imageTokens = contentItemTokenCount(
            .inputImage(image: .inline(imageUrl: "https://example.com/a.png"), detail: .high)
        )
        let truncated = truncateMessageToTokenBudget(envelope, maxTokens: imageTokens + 4)
        XCTAssertNotNil(truncated)
        let content = messageContent(truncated!.item)
        XCTAssertTrue(content.contains { part in
            if case .inputImage = part { return true }
            return false
        })
        XCTAssertTrue(content.contains { part in
            if case .inputText(let text) = part { return text == "</image>" }
            return false
        })
    }

    func testShouldRetryWithCurrentModelRejectsAbort() {
        XCTAssertFalse(shouldRetryWithCurrentModel(CodexErr(details: .turnAborted)))
        XCTAssertTrue(shouldRetryWithCurrentModel(CodexErr.stream("boom")))
    }

    func testParseBase64ImageDataURLRequiresImageAndBase64() {
        XCTAssertEqual(
            parseBase64ImageDataURL("data:image/png;base64,abcd"),
            "abcd"
        )
        XCTAssertNil(parseBase64ImageDataURL("data:text/plain;base64,abcd"))
        XCTAssertNil(parseBase64ImageDataURL("data:image/png,abcd"))
        XCTAssertNil(parseBase64ImageDataURL("https://example.com/a.png"))
    }

    func testEstimateImageBytesUsesResizedConstantUnlessOriginalDataURL() {
        let longURL = "data:image/png;base64," + String(repeating: "A", count: 20_000)
        XCTAssertEqual(estimateImageBytes(longURL, detail: .high), resizedImageBytesEstimate)
        XCTAssertEqual(estimateImageBytes(longURL, detail: nil), resizedImageBytesEstimate)
        XCTAssertEqual(
            estimateImageReferenceBytes(.inline(imageUrl: longURL), detail: .high),
            resizedImageBytesEstimate
        )
        XCTAssertEqual(
            estimateImageReferenceBytes(.file(fileId: "file_a"), detail: .original),
            approxBytesForTokens(originalImageMaxPatches)
        )
    }

    func testOriginalDetailDataURLUsesDecodedPatchCount() {
        let png = pngDataURL(width: 1, height: 1)
        XCTAssertEqual(estimateImageBytes(png, detail: .original), approxBytesForTokens(1))
        let large = pngDataURL(width: 33, height: 33)
        XCTAssertEqual(estimateImageBytes(large, detail: .original), approxBytesForTokens(4))
        XCTAssertEqual(
            estimateImageBytes("data:image/png;base64,not-valid", detail: .original),
            resizedImageBytesEstimate
        )
    }

    func testEstimateItemTokenCountUsesModelVisibleBytes() {
        let item = ResponseItem.message(
            id: nil,
            role: "user",
            content: [
                .inputText(text: "hi"),
                .inputImage(image: .inline(imageUrl: "https://example.com/a.png"), detail: .high),
            ],
            phase: nil,
            internalChatMessageMetadataPassthrough: nil
        )
        let expected = Int(clamping: approxTokensFromByteCountI64(Int64("hi".utf8.count + resizedImageBytesEstimate)))
        XCTAssertEqual(estimateItemTokenCount(item), expected)
        XCTAssertEqual(estimateImageReferenceBytes(item), resizedImageBytesEstimate)
    }
}

private func messageContent(_ item: ResponseItem) -> [ContentItem] {
    if case .message(_, _, let content, _, _) = item { return content }
    return []
}

private func pngDataURL(width: Int, height: Int) -> String {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])
    data.append(contentsOf: u32beBytes(width))
    data.append(contentsOf: u32beBytes(height))
    return "data:image/png;base64," + data.base64EncodedString()
}

private func u32beBytes(_ value: Int) -> [UInt8] {
    let v = UInt32(clamping: value)
    return [
        UInt8((v >> 24) & 0xFF),
        UInt8((v >> 16) & 0xFF),
        UInt8((v >> 8) & 0xFF),
        UInt8(v & 0xFF),
    ]
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

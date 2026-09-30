@testable import Sage
import CodexProtocol
import XCTest

@MainActor
final class ExecuteHarnessGuardianLiveApprovalTests: XCTestCase {
    private var tempDirectory: URL?
    private var projectRoot: URL?
    private var scratchFiles: [URL] = []

    override func tearDown() async throws {
        GuardianReviewSession.shared.complete = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
        for file in scratchFiles {
            try? FileManager.default.removeItem(at: file)
        }
        try await super.tearDown()
    }

    func testProjectGuardianAllowSkipsTheHUDCard() async throws {
        GuardianReviewSession.shared.complete = { _ in "ALLOW" }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        try attachHookProject(to: runtime, hookContains: "gated")
        let step = readStep(id: "gated", path: "gated.md")
        let services = runtime.makeExecuteServices()
        let hook = await services.evaluatePreToolUse(
            name: step.toolName,
            argumentsJSON: step.argumentsJSON
        )
        guard case .ask(let approval) = hook else {
            return XCTFail("expected the project hook to ask")
        }

        let gate = await ToolBatchExecutor.reviewMissingApproval(
            step,
            hookApproval: approval,
            services: services
        )

        XCTAssertEqual(gate, .continueBatch)
        XCTAssertTrue(
            runtime.state.sessionAllowlist.containsHookApproval(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON,
                hookIdentity: approval.identity,
                scopeID: runtime.state.authorizationScopeID
            )
        )
    }

    func testProjectGuardianDenyFailsWithoutACard() async throws {
        GuardianReviewSession.shared.complete = { _ in "DENY secrets would leave the workspace" }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        try attachHookProject(to: runtime, hookContains: "gated")
        var plan = AgentPlan(
            summary: "Read",
            steps: [readStep(id: "gated", path: "gated.md")]
        )

        let outcome = await ToolBatchExecutor.runAdmittedBatch(
            plan: &plan,
            services: runtime.makeExecuteServices()
        )

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(plan.steps.map(\.status), [.failed])
        XCTAssertNil(runtime.state.pendingPrompt)
        XCTAssertTrue(plan.steps[0].result?.contains("secrets") == true)
    }

    func testProjectGuardianAskStillPausesTheBatch() async throws {
        GuardianReviewSession.shared.complete = { _ in "ASK let the user decide" }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        try attachHookProject(to: runtime, hookContains: "gated")
        var plan = AgentPlan(
            summary: "Read",
            steps: [readStep(id: "gated", path: "gated.md")]
        )

        let outcome = await ToolBatchExecutor.runAdmittedBatch(
            plan: &plan,
            services: runtime.makeExecuteServices()
        )

        XCTAssertEqual(outcome, .paused)
        XCTAssertEqual(plan.steps.map(\.status), [.pending])
        guard case .toolApproval(let callID, _, _, _) = runtime.state.pendingPrompt else {
            return XCTFail("ASK should still show the HUD card")
        }
        XCTAssertEqual(callID, "gated")
    }

    func testHomePolicyDoesNotConsultGuardianForAWriteGate() async throws {
        var reviews = 0
        GuardianReviewSession.shared.complete = { _ in
            reviews += 1
            return "DENY should not run"
        }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let path = homeScratchFile("note.md").path
        let step = AgentStep(
            toolCallID: "w1",
            toolName: "write_text_file",
            argumentsJSON: #"{"path":"\#(path)","content":"hi"}"#,
            title: "write note"
        )

        let gate = await ToolBatchExecutor.reviewMissingApproval(
            step,
            hookApproval: nil,
            services: runtime.makeExecuteServices()
        )

        XCTAssertEqual(reviews, 0)
        XCTAssertEqual(gate, .askHUD)
    }

    func testSandboxEscalationGoesThroughGuardianEvenAtHome() async throws {
        var reviews = 0
        GuardianReviewSession.shared.complete = { _ in
            reviews += 1
            return "ALLOW"
        }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let path = homeScratchFile("note.md").path
        let step = AgentStep(
            toolCallID: "w1",
            toolName: "write_text_file",
            argumentsJSON: #"{"path":"\#(path)","content":"hi"}"#,
            title: SandboxEscalation.title(
                reason: "Seatbelt blocked the write.",
                original: "write note"
            )
        )

        let gate = await ToolBatchExecutor.reviewMissingApproval(
            step,
            hookApproval: nil,
            services: runtime.makeExecuteServices()
        )

        XCTAssertEqual(reviews, 1)
        XCTAssertEqual(gate, .continueBatch)
        XCTAssertTrue(
            runtime.state.sessionAllowlist.contains(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON,
                policy: runtime.state.pathGuardPolicy,
                scopeID: runtime.state.authorizationScopeID
            )
        )
    }

    func testRoutesApprovalPolicyMatchesCodex() {
        let cases: [(CodexProtocol.AskForApproval, [Bool])] = [
            (.unlessTrusted, [false, false]),
            (.onRequest, [false, true]),
            (
                .granular(GranularApprovalConfig(
                    sandboxApproval: true,
                    rules: true,
                    skillApproval: true,
                    requestPermissions: true,
                    mcpElicitations: true
                )),
                [false, true]
            ),
            (.never, [false, false]),
        ]
        for (policy, expected) in cases {
            let actual = [ApprovalsReviewer.user, .autoReview].map { reviewer in
                GuardianReviewRequest.routesApprovalPolicyToGuardian(
                    policy: policy,
                    reviewer: reviewer
                )
            }
            XCTAssertEqual(actual, expected, "approval policy: \(policy)")
        }
    }

    func testDisabledReviewModeSkipsGuardianUnlessRetry() {
        XCTAssertFalse(
            GuardianReviewRequest.routesToGuardian(
                policy: .home,
                retry: false,
                scope: .shell,
                reviewer: .autoReview,
                reviewMode: .disabled
            )
        )
        XCTAssertTrue(
            GuardianReviewRequest.routesToGuardian(
                policy: .home,
                retry: true,
                scope: .shell,
                reviewer: .user,
                reviewMode: .disabled
            )
        )
    }

    func testParseFailureRetriesUntilAllow() async throws {
        var replies = ["not a decision", "ALLOW"]
        GuardianReviewSession.shared.complete = { _ in
            replies.removeFirst()
        }
        let raw = try await GuardianReviewSession.shared.review(prompt: "exec")
        XCTAssertEqual(raw, "ALLOW")
        XCTAssertTrue(replies.isEmpty)
    }

    func testPreparedContextIncludesTranscriptAndSkipsSystem() {
        let request = GuardianApprovalRequest.execCommand(
            id: "1",
            command: "npm test",
            cwd: FileManager.default.homeDirectoryForCurrentUser,
            permissionBits: []
        )
        let prepared = PreparedGuardianContext.prepare(
            request: request,
            approvalReason: nil,
            retryReason: nil,
            events: [
                AgentEvent(kind: .systemInstruction, content: "You are Sage."),
                AgentEvent(kind: .userInput, content: "run the tests"),
                AgentEvent(kind: .toolResult, content: "ok"),
            ]
        )
        XCTAssertTrue(prepared.user.contains(GuardianPrompt.transcriptStart))
        XCTAssertTrue(prepared.user.contains("userInput: run the tests"))
        XCTAssertTrue(prepared.user.contains("toolResult: ok"))
        XCTAssertFalse(prepared.user.contains("You are Sage."))
        XCTAssertTrue(prepared.user.contains(">>> ACTION"))
        XCTAssertTrue(prepared.user.contains("npm test"))
    }

    func testEmptyTranscriptUsesPlaceholderAndCapsApprovalReason() {
        let long = String(repeating: "x", count: 4_000)
        let user = GuardianPrompt.user(
            request: .networkAccess(id: "n", host: "example.com"),
            approvalReason: long,
            retryReason: nil
        )
        XCTAssertTrue(user.contains(GuardianPrompt.transcriptStart + GuardianPrompt.emptyTranscriptPlaceholder))
        XCTAssertTrue(user.contains("approval_reason:"))
        XCTAssertLessThan(user.count, long.count)
        XCTAssertTrue(user.contains("…"))
    }

    func testLiveReviewPromptSeesSessionEvents() async throws {
        var seen = ""
        GuardianReviewSession.shared.complete = { prompt in
            seen = prompt
            return "ASK"
        }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        _ = await runtime.taskStore.commit(
            appendEvents: [AgentEvent(kind: .userInput, content: "keep this ask")],
            deleteEventIDs: []
        ) { _ in }
        let path = homeScratchFile("note.md").path
        let step = AgentStep(
            toolCallID: "w1",
            toolName: "write_text_file",
            argumentsJSON: #"{"path":"\#(path)","content":"hi"}"#,
            title: SandboxEscalation.title(
                reason: "Seatbelt blocked the write.",
                original: "write note"
            )
        )

        _ = await ToolBatchExecutor.reviewMissingApproval(
            step,
            hookApproval: nil,
            services: runtime.makeExecuteServices()
        )

        XCTAssertTrue(seen.contains("keep this ask"))
        XCTAssertTrue(seen.contains(GuardianPrompt.transcriptStart))
    }

    func testFromStepClassifiesPatchMcpPermissionsAndStdin() {
        let cwd = FileManager.default.temporaryDirectory
        let patch = """
        *** Begin Patch
        *** Add File: notes/hello.md
        +hi
        *** End Patch
        """
        let patchAction = ApprovalAction.from(
            step: AgentStep(
                toolCallID: "p1",
                toolName: "apply_patch",
                argumentsJSON: patch,
                title: "patch"
            ),
            cwd: cwd
        )
        let patchRequest = GuardianApprovalRequest.from(patchAction)
        XCTAssertEqual(patchRequest.scope, .fileChanges)
        XCTAssertTrue(patchRequest.pretty().contains("apply_patch"))
        XCTAssertTrue(patchRequest.pretty().contains("notes/hello.md"))
        XCTAssertTrue(patchRequest.pretty().contains("*** Begin Patch"))

        let mcpRequest = GuardianApprovalRequest.from(
            ApprovalAction.from(
                step: AgentStep(
                    toolCallID: "m1",
                    toolName: "mcp__github__create_issue",
                    argumentsJSON: #"{"title":"bug"}"#,
                    title: "mcp"
                ),
                cwd: cwd
            )
        )
        XCTAssertEqual(mcpRequest.scope, .mcp)
        XCTAssertTrue(mcpRequest.pretty().contains("server: github"))
        XCTAssertTrue(mcpRequest.pretty().contains("tool_name: create_issue"))
        XCTAssertTrue(mcpRequest.pretty().contains(#""title":"bug""#))

        let permissions = GuardianApprovalRequest.from(
            ApprovalAction.from(
                step: AgentStep(
                    toolCallID: "r1",
                    toolName: "request_permissions",
                    argumentsJSON: #"{"reason":"need network","permissions":{"network":{"enabled":true}}}"#,
                    title: "perms"
                ),
                cwd: cwd
            )
        )
        XCTAssertEqual(permissions.scope, .permissions)
        XCTAssertTrue(permissions.pretty().contains("reason: need network"))

        let stdin = GuardianApprovalRequest.from(
            ApprovalAction.from(
                step: AgentStep(
                    toolCallID: "s1",
                    toolName: "write_stdin",
                    argumentsJSON: #"{"session_id":7,"chars":"yes\n"}"#,
                    title: "stdin"
                ),
                cwd: cwd
            )
        )
        XCTAssertEqual(stdin.scope, .shell)
        XCTAssertTrue(stdin.pretty().contains("process_id: 7"))
        XCTAssertTrue(stdin.pretty().contains("yes"))

        let write = GuardianApprovalRequest.from(
            ApprovalAction.from(
                step: AgentStep(
                    toolCallID: "w1",
                    toolName: "write_text_file",
                    argumentsJSON: #"{"path":"a.md","content":"x"}"#,
                    title: "write"
                ),
                cwd: cwd
            )
        )
        XCTAssertEqual(write.scope, .shell)
        XCTAssertTrue(write.pretty().contains("write_text_file"))
    }

    func testLiveReviewPromptSeesApplyPatchFiles() async throws {
        var seen = ""
        GuardianReviewSession.shared.complete = { prompt in
            seen = prompt
            return "ASK"
        }
        let runtime = try makeRuntime()
        _ = await runtime.taskStore.createAndActivateTask(relatedTo: [])
        let patch = """
        *** Begin Patch
        *** Add File: notes/hello.md
        +hi
        *** End Patch
        """
        let step = AgentStep(
            toolCallID: "p1",
            toolName: "apply_patch",
            argumentsJSON: patch,
            title: SandboxEscalation.title(
                reason: "Seatbelt blocked the write.",
                original: "apply patch"
            )
        )

        _ = await ToolBatchExecutor.reviewMissingApproval(
            step,
            hookApproval: nil,
            services: runtime.makeExecuteServices()
        )

        XCTAssertTrue(seen.contains("apply_patch"))
        XCTAssertTrue(seen.contains("notes/hello.md"))
        XCTAssertTrue(seen.contains(GuardianPrompt.transcriptStart))
    }

    func testReviewerConfigUsesReviewRoleExtraPolicyAndNetwork() {
        let settings = ModelSettingsSnapshot(
            baseURL: "https://example.com/v1",
            model: "review-model",
            apiKey: "k"
        )
        let config = GuardianReviewerConfig.resolve(
            settings: settings,
            extraPolicy: "Never allow outbound mail.",
            network: .seatbelt
        )
        XCTAssertEqual(config.model, "review-model")
        XCTAssertTrue(config.instructions.hasPrefix(GuardianPrompt.system))
        XCTAssertTrue(config.instructions.contains("Never allow outbound mail."))
        XCTAssertEqual(config.network, .seatbelt)
    }

    func testPreparedContextUsesResolvedInstructions() {
        let config = GuardianReviewerConfig.resolve(
            settings: ModelSettingsSnapshot(
                baseURL: "https://example.com/v1",
                model: "review-model",
                apiKey: ""
            ),
            extraPolicy: "Deny secret files."
        )
        let prepared = PreparedGuardianContext.prepare(
            request: .networkAccess(id: "n", host: "example.com"),
            approvalReason: nil,
            retryReason: nil,
            config: config
        )
        XCTAssertEqual(prepared.system, config.instructions)
        XCTAssertTrue(prepared.system.contains("Deny secret files."))
        XCTAssertEqual(prepared.scope, .network)
    }

    func testResolveLiveAttachesSeatbeltOnlyForNetworkScope() {
        XCTAssertEqual(GuardianReviewerConfig.resolveLive(scope: .network).network, .seatbelt)
        XCTAssertNil(GuardianReviewerConfig.resolveLive(scope: .shell).network)
        XCTAssertNil(GuardianReviewerConfig.resolveLive(scope: .fileChanges).network)
    }

    func testReviewActionRejectsWriteStdinWithoutAProcess() {
        let invalid = ReviewAction.from(
            ApprovalAction.writeStdin(
                id: "s1",
                processID: 0,
                input: "yes\n",
                cwd: FileManager.default.temporaryDirectory
            )
        )
        XCTAssertEqual(invalid.scope, .shell)
        guard case .denied(.denied(let reason)) = invalid.validate() else {
            return XCTFail("expected a deny when stdin has no process")
        }
        XCTAssertTrue(reason.contains("terminal's environment"))

        let valid = ReviewAction.from(
            ApprovalAction.writeStdin(
                id: "s2",
                processID: 7,
                input: "yes\n",
                cwd: FileManager.default.temporaryDirectory
            )
        )
        guard case .ready(let request) = valid.validate() else {
            return XCTFail("expected a prepared stdin request")
        }
        XCTAssertEqual(request.scope, .shell)
    }

    func testUnpreparedWriteStdinIsDeniedWithoutConsultingTheReviewer() async {
        var reviews = 0
        GuardianReviewSession.shared.complete = { _ in
            reviews += 1
            return "ALLOW"
        }
        let decision = await GuardianDecision.decide(
            action: .writeStdin(
                id: "s1",
                processID: 0,
                input: "yes\n",
                cwd: FileManager.default.temporaryDirectory
            ),
            context: ApprovalContext(callID: "s1", toolName: "write_stdin"),
            options: GuardianReviewOptions(requireGuardian: true)
        )
        XCTAssertEqual(
            decision,
            .denied(
                reason: "automatic approval review cannot access the terminal's environment; select it before retrying"
            )
        )
        XCTAssertEqual(reviews, 0)
    }

    private func homeScratchFile(_ name: String) -> URL {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/.sage-guardian-live-\(UUID().uuidString)-\(name)")
        scratchFiles.append(file)
        return file
    }

    private func readStep(id: String, path: String) -> AgentStep {
        AgentStep(
            toolCallID: id,
            toolName: "read_text_file",
            argumentsJSON: #"{"path":"\#(path)"}"#,
            title: path
        )
    }

    private func makeRuntime() throws -> AgentRuntime {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        let repository = GRDBTaskRepository(
            databaseURL: directory.appendingPathComponent("sage.sqlite"),
            legacyJSONURL: directory.appendingPathComponent("tasks.json")
        )
        let runtime = AgentRuntime(
            settings: .shared,
            tools: .makeDefault(),
            taskRepository: repository,
            skills: SkillSessionController()
        )
        runtime.turns.execute.useHarnessRunTurn = false
        return runtime
    }

    private func attachHookProject(to runtime: AgentRuntime, hookContains: String) throws {
        let project = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/.sage-guardian-live-\(UUID().uuidString)", isDirectory: true)
        let sage = project.appendingPathComponent(".sage", isDirectory: true)
        try FileManager.default.createDirectory(at: sage, withIntermediateDirectories: true)
        projectRoot = project
        let config = """
        {
          "pre_tool_use": [
            {
              "tool": "read_text_file",
              "action": "ask",
              "argument_contains": {"path": "\(hookContains)"},
              "reason": "Review this read"
            }
          ]
        }
        """
        try Data(config.utf8).write(to: sage.appendingPathComponent("hooks.json"))
        runtime.state.focusedProject = ProjectRecord(name: "guardian-live", rootPath: project.path)
    }
}

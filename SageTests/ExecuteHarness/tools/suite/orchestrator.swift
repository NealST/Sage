@testable import Sage
import XCTest

@MainActor
final class ExecuteHarnessOrchestratorTests: XCTestCase {
    private var tempDirectory: URL?

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testReadOnlyCommandDoesNotPrompt() async throws {
        let runtime = ScriptedRuntime()
        let approver = RecordingApprover()
        let output = try await ToolOrchestrator().run(
            tool: runtime,
            request: .readOnly,
            ctx: .general,
            approver: approver
        )
        XCTAssertEqual(output, "[exit 0]\nok")
        XCTAssertEqual(approver.calls.count, 0)
        XCTAssertEqual(runtime.attempts.count, 1)
    }

    func testWriteCommandPromptsOnceAndCachesTheSessionGrant() async throws {
        let store = ApprovalStore()
        let orchestrator = ToolOrchestrator(approvalStore: store)
        let approver = RecordingApprover(decision: .approvedForSession)
        let runtime = ScriptedRuntime()

        _ = try await orchestrator.run(
            tool: runtime,
            request: .write,
            ctx: .general,
            approver: approver
        )
        _ = try await orchestrator.run(
            tool: ScriptedRuntime(),
            request: .write,
            ctx: .general,
            approver: approver
        )

        XCTAssertEqual(approver.calls.count, 1)
        XCTAssertNil(approver.calls.first?.retryReason)
    }

    func testSandboxDenialEscalatesOnceWithoutReasking() async throws {
        let runtime = ScriptedRuntime(failFirst: true)
        let approver = RecordingApprover(decision: .approved)
        let output = try await ToolOrchestrator().run(
            tool: runtime,
            request: .write,
            ctx: .general,
            approver: approver
        )

        XCTAssertEqual(output, "[exit 0]\nok")
        XCTAssertEqual(runtime.attempts.count, 2)
        XCTAssertEqual(runtime.attempts.last, .none)
        XCTAssertEqual(approver.calls.count, 1)
        XCTAssertNil(approver.calls.first?.retryReason)
    }

    func testProjectModeKeepsSeatbeltOnEscalate() async throws {
        let runtime = ScriptedRuntime(failFirst: true)
        let approver = RecordingApprover(decision: .approved)
        _ = try await ToolOrchestrator().run(
            tool: runtime,
            request: .write,
            ctx: .project,
            approver: approver
        )
        XCTAssertEqual(runtime.attempts.count, 2)
        XCTAssertEqual(runtime.attempts[0], runtime.attempts[1])
        XCTAssertEqual(approver.calls.count, 1)
    }

    func testTimeoutIsReportedInShellOutput() async throws {
        let directory = try makeTempDirectory()
        let request = ShellExecRequest(
            command: "sleep 5",
            workingDirectory: directory,
            timeoutSeconds: 1,
            permissionBits: [],
            allowedSensitiveReadRoots: []
        )
        let ctx = ToolCtx(
            callID: "timeout",
            toolName: "run_shell_command",
            pathGuardPolicy: .home,
            workPlanKind: .act,
            approvalPolicy: .unlessTrusted,
            fileSystemPolicy: .sage(.home),
            readAllowlist: [],
            extraReadableRoots: []
        )
        let attempt = SandboxAttempt.make(
            sandbox: .none,
            sandboxRequested: false,
            bits: [],
            cwd: directory,
            ctx: ctx
        )
        let output = try await ShellRuntime().run(request, attempt: attempt, ctx: ctx)
        XCTAssertTrue(output.contains("timed out after 1s"), output)
    }

    func testUnapprovedSandboxDenialAsksForEscalation() async throws {
        let runtime = ScriptedRuntime(failFirst: true)
        let approver = InvocationApprover(authorization: nil, evidence: nil)
        do {
            _ = try await ToolOrchestrator().run(
                tool: runtime,
                request: .readOnly,
                ctx: .general,
                approver: approver
            )
            XCTFail("Expected an escalation approval")
        } catch let error as HarnessToolError {
            guard case .needsEscalationApproval = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertEqual(runtime.attempts.count, 1)
    }

    func testApprovedUnsandboxedRetrySkipsSeatbelt() async throws {
        let runtime = ScriptedRuntime()
        var ctx = ToolCtx.general
        ctx.allowUnsandboxedRetry = true
        let output = try await ToolOrchestrator().run(
            tool: runtime,
            request: .readOnly,
            ctx: ctx,
            approver: RecordingApprover()
        )
        XCTAssertEqual(output, "[exit 0]\nok")
        XCTAssertEqual(runtime.attempts, [.none])
    }

    func testPipelineTimeoutDurationForShellStaysAtTheOuterCap() {
        XCTAssertEqual(
            ToolInvocationPipeline.timeoutDuration(for: "run_shell_command"),
            .seconds(130)
        )
    }
}

@MainActor
private final class RecordingApprover: ApprovalRequesting {
    var decision: ReviewDecision
    var calls: [ApprovalContext] = []

    init(decision: ReviewDecision = .approved) {
        self.decision = decision
    }

    func requestApproval(
        action _: ApprovalAction,
        context: ApprovalContext
    ) async throws -> ReviewDecision {
        calls.append(context)
        return decision
    }
}

private final class ScriptedRuntime: ToolRuntime, @unchecked Sendable {
    var failFirst: Bool
    var attempts: [SandboxType] = []

    init(failFirst: Bool = false) {
        self.failFirst = failFirst
    }

    func sandboxPreference() -> SandboxablePreference { .auto }

    func execApprovalRequirement(_ request: ShellExecRequest) -> ExecApprovalRequirement? {
        ShellRuntime().execApprovalRequirement(request)
    }

    func approvalAction(_ request: ShellExecRequest, callID: String) -> ApprovalAction {
        ShellRuntime().approvalAction(request, callID: callID)
    }

    func sandboxCwd(_ request: ShellExecRequest) -> URL? {
        request.workingDirectory
    }

    func run(
        _: ShellExecRequest,
        attempt: SandboxAttempt,
        ctx _: ToolCtx
    ) async throws -> String {
        attempts.append(attempt.sandbox)
        if failFirst, attempts.count == 1 {
            throw HarnessToolError.sandboxDenied(
                output: "[exit 1]\nOperation not permitted"
            )
        }
        return "[exit 0]\nok"
    }
}

private extension ShellExecRequest {
    static var readOnly: Self {
        Self(
            command: "ls",
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            timeoutSeconds: 30,
            permissionBits: [],
            allowedSensitiveReadRoots: []
        )
    }

    static var write: Self {
        Self(
            command: "npm test",
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            timeoutSeconds: 30,
            permissionBits: [.writes],
            allowedSensitiveReadRoots: []
        )
    }
}

private extension ToolCtx {
    static var general: Self {
        Self(
            callID: "test",
            toolName: "run_shell_command",
            pathGuardPolicy: .home,
            workPlanKind: .act,
            approvalPolicy: .unlessTrusted,
            fileSystemPolicy: .sage(.home),
            readAllowlist: [],
            extraReadableRoots: []
        )
    }

    static var project: Self {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("proj", isDirectory: true)
        return Self(
            callID: "test",
            toolName: "run_shell_command",
            pathGuardPolicy: .project(root: root),
            workPlanKind: .act,
            approvalPolicy: .unlessTrusted,
            fileSystemPolicy: .sage(.project(root: root)),
            readAllowlist: [],
            extraReadableRoots: []
        )
    }
}

private extension ExecuteHarnessOrchestratorTests {
    func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage-orchestrator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        return directory
    }
}

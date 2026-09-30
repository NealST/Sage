@testable import CodexCore
import CodexProtocol
import CodexShellCommand
import CodexUtils
@testable import Sage
import XCTest

final class ExecuteHarnessUnifiedExecStdinApprovalTests: XCTestCase {
    func testEmptyAndCtrlCSkipReview() throws {
        let cwd = try Self.tmpCwd()
        XCTAssertNil(
            try decideStdinApproval(
                input: "",
                processId: 7,
                tty: true,
                cwd: cwd,
                callId: "c1",
                permissions: .nativeDefault(),
                current: .disabled,
                writeStdinApprovalEnabled: true,
                strictAutoReview: true
            ).get()
        )
        XCTAssertNil(
            try decideStdinApproval(
                input: "\u{3}",
                processId: 7,
                tty: false,
                cwd: cwd,
                callId: "c1",
                permissions: .nativeDefault(),
                current: .disabled,
                writeStdinApprovalEnabled: true,
                strictAutoReview: true
            ).get()
        )
    }

    func testNulInputIsRejected() throws {
        let cwd = try Self.tmpCwd()
        var permissions = TerminalPermissions.nativeDefault()
        permissions.launchProfile = .disabled
        switch decideStdinApproval(
            input: "yes\0no",
            processId: 7,
            tty: true,
            cwd: cwd,
            callId: "c1",
            permissions: permissions,
            current: .readOnly(),
            writeStdinApprovalEnabled: true,
            strictAutoReview: true
        ) {
        case .success:
            XCTFail("expected a NUL reject")
        case .failure(let error):
            XCTAssertTrue(error.description.contains("NUL"))
        }
    }

    func testProfileDriftAsksForReview() throws {
        let cwd = try Self.tmpCwd()
        var permissions = TerminalPermissions.nativeDefault()
        permissions.launchProfile = .disabled
        let need = try XCTUnwrap(
            try decideStdinApproval(
                input: "yes\n",
                processId: 7,
                tty: true,
                cwd: cwd,
                callId: "c1",
                permissions: permissions,
                current: .readOnly(),
                writeStdinApprovalEnabled: true,
                strictAutoReview: false
            ).get()
        )
        XCTAssertEqual(need.processId, 7)
        XCTAssertEqual(need.sandboxPermissions, .requireEscalated)
        XCTAssertTrue(need.reason.contains("filesystem sandbox"))
    }

    func testMatchingProfileSkipsUnlessStrictAutoReview() throws {
        let cwd = try Self.tmpCwd()
        var permissions = TerminalPermissions.nativeDefault()
        permissions.launchProfile = .readOnly()
        XCTAssertNil(
            try decideStdinApproval(
                input: "yes\n",
                processId: 7,
                tty: true,
                cwd: cwd,
                callId: "c1",
                permissions: permissions,
                current: .readOnly(),
                writeStdinApprovalEnabled: true,
                strictAutoReview: false
            ).get()
        )
        let need = try decideStdinApproval(
            input: "yes\n",
            processId: 7,
            tty: true,
            cwd: cwd,
            callId: "c1",
            permissions: permissions,
            current: .readOnly(),
            writeStdinApprovalEnabled: true,
            strictAutoReview: true
        ).get()
        XCTAssertEqual(try XCTUnwrap(need).sandboxPermissions, .useDefault)
    }

    func testReviewActionRejectsNulStdin() {
        let action = ReviewAction.from(
            ApprovalAction.writeStdin(
                id: "s1",
                processID: 7,
                input: "yes\0",
                cwd: FileManager.default.temporaryDirectory
            )
        )
        guard case .denied(.denied(let reason)) = action.validate() else {
            return XCTFail("expected a NUL deny")
        }
        XCTAssertTrue(reason.contains("NUL"))
    }

    func testShellSnapshotBuildsForLoginCommand() throws {
        let cwd = try Self.tmpCwd()
        let request = ExecCommandRequest(
            command: ["/bin/zsh", "-lc", "ls"],
            shellType: .zsh,
            hookCommand: "",
            processId: 3,
            yieldTimeMs: 250,
            maxOutputTokens: nil,
            cwd: cwd,
            sandboxCwd: cwd,
            shellMode: .direct,
            network: nil,
            tty: false,
            sandboxPermissions: .useDefault,
            additionalPermissions: nil,
            additionalPermissionsPreapproved: false,
            justification: nil,
            prefixRule: nil
        )
        let snapshot = try XCTUnwrap(
            shellSnapshotRequest(
                request: request,
                cwd: cwd,
                snapshotSupported: true,
                featureEnabled: true
            )
        )
        XCTAssertEqual(snapshot.shellName, "zsh")
        XCTAssertEqual(snapshot.scopeId, "3")
    }

    func testUserShellCommandRecordFormatsAndWraps() {
        let record = userShellCommandRecord(
            command: "ls",
            execOutput: ExecToolCallOutput(
                exitCode: 0,
                stdout: .new("a\n"),
                stderr: .new(""),
                aggregatedOutput: .new("a\n"),
                duration: .milliseconds(12),
                timedOut: false
            ),
            truncatedOutput: "a\n"
        )
        XCTAssertTrue(formatUserShellCommandRecord(record).contains("[ok]"))
        guard case .message(_, let role, let content, _, _) = userShellCommandRecordItem(record) else {
            return XCTFail("expected a user message item")
        }
        XCTAssertEqual(role, "user")
        XCTAssertTrue(String(describing: content).contains("$ ls"))
    }

    func testWriteStdinUnknownProcessDoesNotWait() async {
        let manager = UnifiedExecProcessManager()
        do {
            try await manager.writeStdin(
                WriteStdinRequest(processId: 99, input: "x", yieldTimeMs: 250, maxOutputTokens: nil)
            )
            XCTFail("expected unknown process")
        } catch let error as UnifiedExecError {
            guard case .unknownProcessId(processId: 99) = error else {
                return XCTFail("\(error)")
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    private static func tmpCwd() throws -> PathUri {
        try PathUri.fromAbsPath(AbsolutePathBuf.fromAbsolutePath("/tmp"))
    }
}

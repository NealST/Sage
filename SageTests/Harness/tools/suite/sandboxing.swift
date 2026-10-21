@testable import Sage
import XCTest

final class ExecuteHarnessSandboxingTests: XCTestCase {
    func testReadOnlyShellSkipsApproval() throws {
        let request = try ShellExecRequest.parse(
            #"{"command":"ls"}"#,
            policy: .home
        )
        XCTAssertTrue(request.permissionBits.isEmpty)
        XCTAssertEqual(
            ShellRuntime().execApprovalRequirement(request),
            Optional.some(.skip(bypassSandbox: false))
        )
    }

    func testWriteAndNetworkBecomePermissionBits() throws {
        let request = try ShellExecRequest.parse(
            #"{"command":"npm test","allow_writes":true,"allow_network":true}"#,
            policy: .home
        )
        XCTAssertEqual(request.permissionBits, [.writes, .network])
        XCTAssertEqual(
            ShellRuntime().execApprovalRequirement(request),
            Optional.some(.needsApproval(reason: nil))
        )
        XCTAssertEqual(ShellRuntime().sandboxPermissions(request), .requireEscalated)
    }

    func testDefaultApprovalAsksWhenFilesystemIsRestricted() {
        XCTAssertEqual(
            defaultExecApprovalRequirement(
                .onRequest,
                fileSystem: FileSystemSandboxPolicy(kind: .restricted, deniedReadRoots: [])
            ),
            .needsApproval(reason: nil)
        )
        XCTAssertEqual(
            defaultExecApprovalRequirement(
                .never,
                fileSystem: FileSystemSandboxPolicy(kind: .restricted, deniedReadRoots: [])
            ),
            .skip(bypassSandbox: false)
        )
    }

    func testProjectModeForbidsDroppingTheSandbox() {
        let home = PathGuard.resolvedHomePath
        let policy = FileSystemSandboxPolicy.sage(
            .project(root: URL(fileURLWithPath: home).appendingPathComponent("proj"))
        )
        XCTAssertTrue(policy.hasDeniedReadRestrictions)
        XCTAssertFalse(unsandboxedExecutionAllowed(policy))
        XCTAssertEqual(
            ExecSandbox.selectRetry(fileSystem: policy, preference: .auto),
            SeatbeltSandbox.isAvailable ? .seatbelt : .none
        )

        let general = FileSystemSandboxPolicy.sage(.home)
        XCTAssertTrue(unsandboxedExecutionAllowed(general))
        XCTAssertEqual(ExecSandbox.selectRetry(fileSystem: general, preference: .auto), .none)
    }

    func testPathGuardStillBlocksWorkingDirectoryOutsideTheSandbox() {
        XCTAssertThrowsError(
            try ShellExecRequest.parse(
                #"{"command":"ls","working_directory":"/etc"}"#,
                policy: .home
            )
        ) { error in
            guard let toolError = error as? ToolError,
                  case .pathNotAllowed = toolError else {
                return XCTFail("expected pathNotAllowed, got \(error)")
            }
        }
    }

    func testDenylistStillBlocksDangerousCommands() {
        XCTAssertThrowsError(try ShellCommandPolicy.validate("sudo rm -rf /")) { error in
            guard let toolError = error as? ToolError,
                  case .operationFailed(let message) = toolError else {
                return XCTFail("expected operationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("blocked") || message.contains("not allowed"))
        }
    }

    func testSandboxDenialHeuristic() {
        XCTAssertTrue(
            HarnessToolError.isSandboxDenial(
                exitCode: 1,
                output: "zsh:1: Operation not permitted"
            )
        )
        XCTAssertFalse(
            HarnessToolError.isSandboxDenial(exitCode: 0, output: "Operation not permitted")
        )
        XCTAssertFalse(
            HarnessToolError.isSandboxDenial(exitCode: 1, output: "not found")
        )
    }
}

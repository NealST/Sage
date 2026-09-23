@testable import Sage
import XCTest

@MainActor
final class ExecuteHarnessApprovalTests: XCTestCase {
    func testSessionApprovalIsReusedForTheSameCommand() async throws {
        let store = ApprovalStore()
        let action = ApprovalAction.execCommand(
            id: "1",
            command: "npm test",
            cwd: FileManager.default.homeDirectoryForCurrentUser,
            permissionBits: [.writes]
        )
        var fetches = 0
        let first = try await withCachedApproval(
            store: store,
            keys: [action.cacheKey]
        ) {
            fetches += 1
            return .approvedForSession
        }
        let second = try await withCachedApproval(
            store: store,
            keys: [action.cacheKey]
        ) {
            fetches += 1
            return .approved
        }
        XCTAssertEqual(first, .approvedForSession)
        XCTAssertEqual(second, .approvedForSession)
        XCTAssertEqual(fetches, 1)
    }

    func testInvocationApproverAcceptsMatchingEvidence() async throws {
        let requirement = ToolAuthorizationRequirement(
            resources: [
                ToolAuthorizationResource(capability: .localWrite, roots: ["/tmp/proj"]),
            ],
            principal: "shell"
        )
        let approver = InvocationApprover(
            authorization: requirement,
            evidence: ToolInvocationAuthorizationEvidence(requirementKey: requirement.stableKey)
        )
        let decision = try await approver.requestApproval(
            action: .execCommand(
                id: "1",
                command: "touch a",
                cwd: URL(fileURLWithPath: "/tmp/proj"),
                permissionBits: [.writes]
            ),
            context: ApprovalContext(callID: "1", toolName: "run_shell_command")
        )
        XCTAssertEqual(decision, .approved)
    }

    func testInvocationApproverRejectsMissingEvidence() async {
        let requirement = ToolAuthorizationRequirement(
            resources: [
                ToolAuthorizationResource(capability: .network, roots: []),
            ],
            principal: "shell"
        )
        let approver = InvocationApprover(authorization: requirement, evidence: nil)
        do {
            _ = try await approver.requestApproval(
                action: .execCommand(
                    id: "1",
                    command: "curl example.com",
                    cwd: FileManager.default.homeDirectoryForCurrentUser,
                    permissionBits: [.network]
                ),
                context: ApprovalContext(callID: "1", toolName: "run_shell_command")
            )
            XCTFail("expected rejection")
        } catch let error as HarnessToolError {
            XCTAssertEqual(error, .rejected("This tool call requires authorization."))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

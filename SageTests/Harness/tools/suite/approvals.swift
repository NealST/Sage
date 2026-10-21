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

    func testAllowlistSessionGrantIsVisibleToApprovalStore() async {
        let store = ApprovalStore()
        let list = isolatedAllowlist(approvalStore: store)
        let args = #"{"path":"~/Documents/note.txt","content":"hello"}"#
        XCTAssertNil(store.get(ApprovalStore.sessionCacheKey(name: "write_text_file", argumentsJSON: args)))
        list.allowThisTask(
            name: "write_text_file",
            argumentsJSON: args,
            policy: .home,
            scopeID: "task-a"
        )
        XCTAssertEqual(
            store.get(ApprovalStore.sessionCacheKey(name: "write_text_file", argumentsJSON: args)),
            .approvedForSession
        )
        XCTAssertTrue(
            list.contains(
                name: "write_text_file",
                argumentsJSON: args,
                policy: .home,
                scopeID: "task-a"
            )
        )
    }

    func testWithCachedApprovalReusesAllowlistSessionKey() async throws {
        let store = ApprovalStore()
        let list = isolatedAllowlist(approvalStore: store)
        let args = #"{"path":"~/Documents/note.txt","content":"hello"}"#
        list.allowThisTask(
            name: "write_text_file",
            argumentsJSON: args,
            policy: .home,
            scopeID: "task-a"
        )
        var fetches = 0
        let decision = try await withCachedApproval(
            store: store,
            keys: [
                ApprovalStore.sessionCacheKey(name: "write_text_file", argumentsJSON: args),
            ]
        ) {
            fetches += 1
            return .approved
        }
        XCTAssertEqual(decision, .approvedForSession)
        XCTAssertEqual(fetches, 0)
    }

    func testApplyPatchAsksBeforeDroppingTheSandboxOnRequest() {
        let runtime = ApplyPatchToolRuntime()
        XCTAssertTrue(runtime.wantsNoSandboxApproval(policy: .onRequest))
        XCTAssertTrue(runtime.wantsNoSandboxApproval(policy: .unlessTrusted))
        XCTAssertFalse(runtime.wantsNoSandboxApproval(policy: .never))
        XCTAssertFalse(ShellRuntime().wantsNoSandboxApproval(policy: .onRequest))
    }

    private func isolatedAllowlist(approvalStore: ApprovalStore) -> SessionToolAllowlist {
        let suite = "ExecuteHarnessApprovalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SessionToolAllowlist(
            grantStore: ToolAuthorizationGrantStore(defaults: defaults),
            approvalStore: approvalStore
        )
    }
}

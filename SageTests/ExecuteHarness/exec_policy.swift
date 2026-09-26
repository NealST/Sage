//
//  exec_policy.swift
//  SageTests
//
//  Port of selected codex-rs/core/src/exec_policy_tests.rs cases (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexExecPolicy
import CodexProtocol
import CodexUtils
@testable import CodexCore
import XCTest

final class CoreExecPolicyTests: XCTestCase {
    func testPromptIsRejectedByNever() {
        XCTAssertEqual(
            promptIsRejectedByPolicy(.never, promptIsRule: true),
            PROMPT_CONFLICT_REASON
        )
    }

    func testPromptIsRejectedByGranularRules() {
        let config = GranularApprovalConfig(
            sandboxApproval: true,
            rules: false,
            mcpElicitations: true
        )
        XCTAssertEqual(
            promptIsRejectedByPolicy(.granular(config), promptIsRule: true),
            REJECT_RULES_APPROVAL_REASON
        )
    }

    func testPromptIsRejectedByGranularSandbox() {
        let config = GranularApprovalConfig(
            sandboxApproval: false,
            rules: true,
            mcpElicitations: true
        )
        XCTAssertEqual(
            promptIsRejectedByPolicy(.granular(config), promptIsRule: false),
            REJECT_SANDBOX_APPROVAL_REASON
        )
    }

    func testUnmatchedGranularStillPromptsForRestrictedEscalation() {
        let decision = renderDecisionForUnmatchedCommand(
            ["madeup-cmd"],
            UnmatchedCommandContext(
                approvalPolicy: .granular(
                    GranularApprovalConfig(
                        sandboxApproval: true,
                        rules: true,
                        skillApproval: true,
                        requestPermissions: true,
                        mcpElicitations: true
                    )
                ),
                permissionProfile: .readOnly(),
                windowsSandboxLevel: .disabled,
                sandboxPermissions: .requireEscalated,
                commandOrigin: .generic
            )
        )
        XCTAssertEqual(decision, .prompt)
    }

    func testUnmatchedOnRequestPromptsForRestrictedEscalation() {
        let decision = renderDecisionForUnmatchedCommand(
            ["madeup-cmd"],
            UnmatchedCommandContext(
                approvalPolicy: .onRequest,
                permissionProfile: .readOnly(),
                windowsSandboxLevel: .disabled,
                sandboxPermissions: .requireEscalated,
                commandOrigin: .generic
            )
        )
        XCTAssertEqual(decision, .prompt)
    }

    func testKnownSafeOnRequestStillPromptsForEscalation() {
        let decision = renderDecisionForUnmatchedCommand(
            ["echo", "hello"],
            UnmatchedCommandContext(
                approvalPolicy: .onRequest,
                permissionProfile: .workspaceWrite(),
                windowsSandboxLevel: .restrictedToken,
                sandboxPermissions: .requireEscalated,
                commandOrigin: .generic
            )
        )
        XCTAssertEqual(decision, .prompt)
    }

    func testBannedPrefixSuggestionsAreRejected() {
        XCTAssertNil(
            deriveRequestedExecpolicyAmendmentFromPrefixRule(
                ["python", "-c"],
                [],
                Policy.empty(),
                [["echo"]],
                { _ in .allow },
                MatchOptions()
            )
        )
        XCTAssertNil(
            deriveRequestedExecpolicyAmendmentFromPrefixRule(
                ["bash", "-lc"],
                [],
                Policy.empty(),
                [["echo"]],
                { _ in .allow },
                MatchOptions()
            )
        )
        let allowed = deriveRequestedExecpolicyAmendmentFromPrefixRule(
            ["python", "-c", "print('hi')"],
            [],
            Policy.empty(),
            [["python", "-c", "print('hi')"]],
            { _ in .allow },
            MatchOptions()
        )
        XCTAssertEqual(allowed?.command, ["python", "-c", "print('hi')"])
    }

    func testLoadEmptyWhenRulesDirMissing() async throws {
        let missing = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-missing-rules-\(UUID().uuidString)")
        let policy = try await loadExecPolicy(
            layers: [ExecPolicyLayer(rulesDir: missing, isUserOrProject: true)]
        )
        XCTAssertTrue(policy.getAllowedPrefixes().isEmpty)
    }

    func testLoadsPoliciesFromRulesDirectory() async throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try #"prefix_rule(pattern=["echo"], decision="allow")"#
            .write(
                toFile: (dir as NSString).appendingPathComponent("echo.rules"),
                atomically: true,
                encoding: .utf8
            )
        let policy = try await loadExecPolicy(
            layers: [ExecPolicyLayer(rulesDir: dir, isUserOrProject: true)]
        )
        XCTAssertEqual(
            policy.check(["echo", "hi"]) { _ in .prompt }.decision,
            .allow
        )
    }

    func testIgnoresUserProjectRulesWhenAsked() async throws {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("sage-rules-ignored-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try #"prefix_rule(pattern=["echo"], decision="allow")"#
            .write(
                toFile: (dir as NSString).appendingPathComponent("echo.rules"),
                atomically: true,
                encoding: .utf8
            )
        let policy = try await loadExecPolicy(
            layers: [ExecPolicyLayer(rulesDir: dir, isUserOrProject: true)],
            ignoreUserAndProjectRules: true
        )
        XCTAssertEqual(
            policy.check(["echo", "hi"]) { _ in .prompt }.decision,
            .prompt
        )
    }

    func testNeverApprovalForbidsPolicyPrompt() async {
        let parser = PolicyParser()
        try? parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: #"prefix_rule(pattern=["rm"], decision="prompt")"#
        )
        let requirement = await ExecPolicyManager(parser.build())
            .createExecApprovalRequirementForCommand(
                ExecApprovalRequest(
                    command: ["rm"],
                    approvalPolicy: .never,
                    permissionProfile: .disabled,
                    environmentPolicy: nil,
                    windowsSandboxLevel: .disabled,
                    sandboxPermissions: .useDefault,
                    prefixRule: nil,
                    allowPrefixRules: .honor
                )
            )
        XCTAssertEqual(requirement, .forbidden(reason: PROMPT_CONFLICT_REASON))
    }

    func testProposedAmendmentForUnmatchedCommand() async {
        let requirement = await ExecPolicyManager.empty()
            .createExecApprovalRequirementForCommand(
                ExecApprovalRequest(
                    command: ["python"],
                    approvalPolicy: .unlessTrusted,
                    permissionProfile: .disabled,
                    environmentPolicy: nil,
                    windowsSandboxLevel: .disabled,
                    sandboxPermissions: .useDefault,
                    prefixRule: nil,
                    allowPrefixRules: .honor
                )
            )
        guard case .needsApproval(_, let amendment) = requirement else {
            return XCTFail("expected needsApproval, got \(requirement)")
        }
        XCTAssertEqual(amendment?.command, ["python"])
    }

    func testCyberPolicyStripsAllowPrefixes() throws {
        let parser = PolicyParser()
        try parser.parse(
            policyIdentifier: "test.rules",
            policyFileContents: """
            prefix_rule(pattern=["cargo"], decision="allow")
            prefix_rule(pattern=["cargo", "publish"], decision="prompt")
            prefix_rule(pattern=["rm"], decision="forbidden")
            network_rule(host="example.com", protocol="https", decision="allow")
            """
        )
        let manager = ExecPolicyManager(parser.build())
        XCTAssertTrue(manager.currentForPrefixRules(.honor).getAllowedPrefixes().contains(["cargo"]))
        let cyber = manager.currentForPrefixRules(.ignoreForCyberModel)
        XCTAssertTrue(cyber.getAllowedPrefixes().isEmpty)
        XCTAssertEqual(
            cyber.check(["cargo", "install"]) { _ in .prompt }.decision,
            .prompt
        )
        XCTAssertEqual(
            cyber.check(["cargo", "publish"]) { _ in .allow }.decision,
            .prompt
        )
        XCTAssertEqual(
            cyber.check(["rm", "file"]) { _ in .allow }.decision,
            .forbidden
        )
    }

    func testShellApprovalRejectsParentTraversal() {
        let shell = Shell(shellType: .sh, shellPath: "/bin/sh")
        let command = ["/bin/../workspace/bash", "-c", "ls"]
        XCTAssertEqual(
            shellApprovalCommand(command, shell, .direct),
            ["/bin/../workspace/bash"]
        )
        XCTAssertEqual(
            shellApprovalCommand(["/bin/sh", "-c", "ls"], shell, .direct),
            ["/bin/sh", "-c", "ls"]
        )
        XCTAssertEqual(
            shellApprovalCommand(["/opt/custom/zsh", "-c", "ls"], shell, .zshFork),
            ["/opt/custom/zsh", "-c", "ls"]
        )
    }

    func testChildUsesParentWhenFoldersMatch() {
        XCTAssertTrue(
            childUsesParentExecPolicy(
                parentRulesDirs: ["/a/rules"],
                childRulesDirs: ["/a/rules"],
                parentIgnoreUserAndProjectRules: false,
                childIgnoreUserAndProjectRules: false,
                parentRequirements: nil,
                childRequirements: nil
            )
        )
        XCTAssertFalse(
            childUsesParentExecPolicy(
                parentRulesDirs: ["/a/rules"],
                childRulesDirs: ["/b/rules"],
                parentIgnoreUserAndProjectRules: false,
                childIgnoreUserAndProjectRules: false,
                parentRequirements: nil,
                childRequirements: nil
            )
        )
    }

    func testForcedRmRejectedPromptReason() {
        XCTAssertEqual(
            deriveRejectedPromptReason(PROMPT_CONFLICT_REASON, .forcedRm),
            "rm -f style commands are not permitted. Use a safer approach"
        )
        XCTAssertEqual(
            deriveRejectedPromptReason(PROMPT_CONFLICT_REASON, .other),
            PROMPT_CONFLICT_REASON
        )
    }
}

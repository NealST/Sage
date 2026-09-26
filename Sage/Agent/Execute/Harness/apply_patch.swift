//
//  apply_patch.swift
//  Sage
//
//  Port of codex-rs/core/src/apply_patch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session/StepContext/TurnEnvironment wait for Phase 5. Callers pass
//  AskForApproval + PermissionProfile + PatchPolicyMatcher directly.
//

import ApplyPatch
import CodexProtocol
import CodexUtils
import Foundation

struct ApplyPatchRuntimeInvocation: Equatable {
    var action: ApplyPatchAction
    var autoApproved: Bool
    var execApprovalRequirement: ExecApprovalRequirement
}

func prepareApplyPatch(
    approvalPolicy: AskForApproval,
    permissionProfile: PermissionProfile,
    matching: PatchPolicyMatcher,
    action: ApplyPatchAction
) throws -> ApplyPatchRuntimeInvocation {
    let safety: SafetyCheck
    do {
        safety = try assessPatchSafety(
            action: action,
            policy: approvalPolicy,
            permissionProfile: permissionProfile,
            matching: matching
        )
    } catch {
        throw FunctionCallError.respondToModel(
            "failed to check patch permissions: \(error)"
        )
    }
    switch safety {
    case .autoApprove:
        return ApplyPatchRuntimeInvocation(
            action: action,
            autoApproved: true,
            execApprovalRequirement: .skip(
                bypassSandbox: false,
                proposedExecpolicyAmendment: nil
            )
        )
    case .askUser:
        return ApplyPatchRuntimeInvocation(
            action: action,
            autoApproved: false,
            execApprovalRequirement: .needsApproval(
                reason: nil,
                proposedExecpolicyAmendment: nil
            )
        )
    case .reject(let reason):
        throw FunctionCallError.respondToModel("patch rejected: \(reason)")
    }
}

func convertApplyPatchToProtocol(_ action: ApplyPatchAction) -> [String: FileChange] {
    var result: [String: FileChange] = [:]
    result.reserveCapacity(action.changes().count)
    for (path, change) in action.changes() {
        let protocolChange: FileChange
        switch change {
        case .add(let content):
            protocolChange = .add(content: content)
        case .delete(let content):
            protocolChange = .delete(content: content)
        case .update(let unifiedDiff, let movePath, _):
            protocolChange = .update(
                unifiedDiff: unifiedDiff,
                movePath: movePath?.toPathBuf()
            )
        }
        result[path.toPathBuf()] = protocolChange
    }
    return result
}

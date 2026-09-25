//
//  safety.swift
//  Sage
//
//  Port of codex-rs/core/src/safety.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Patch approval routing against writable-root constraints.
//

import ApplyPatch
import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

let PATCH_REJECTED_OUTSIDE_PROJECT_REASON =
    "writing outside of the project; rejected by user approval settings"
let PATCH_REJECTED_READ_ONLY_REASON =
    "writing is blocked by read-only sandbox; rejected by user approval settings"

public enum SafetyCheck: Equatable, Sendable {
    case autoApprove
    case askUser
    case reject(reason: String)
}

enum PatchSandboxRoute: Equatable, Sendable {
    case executorManaged
    case platform(WindowsSandboxLevel)
}

struct PatchPolicyMatcher {
    var configuredPolicy: FileSystemSandboxPolicy
    var context: FileSystemSandboxPolicyContext
    var sandboxRoute: PatchSandboxRoute
    var localMatching: LocalFileSystemPolicyMatcher?

    func canWritePath(_ path: PathUri) throws -> Bool {
        if let localMatching {
            return try localMatching.canWritePath(path)
        }
        return configuredPolicy.canWritePath(path, context: context)
    }
}

extension PatchSandboxRoute {
    func prepareMatching(
        configuredPolicy: FileSystemSandboxPolicy,
        context: FileSystemSandboxPolicyContext
    ) throws -> PatchPolicyMatcher {
        let localMatching: LocalFileSystemPolicyMatcher?
        switch self {
        case .platform:
            localMatching = try configuredPolicy.prepareLocalMatching(context: context)
        case .executorManaged:
            localMatching = nil
        }
        return PatchPolicyMatcher(
            configuredPolicy: configuredPolicy,
            context: context,
            sandboxRoute: self,
            localMatching: localMatching
        )
    }
}

public func assessPatchSafety(
    action: ApplyPatchAction,
    policy: AskForApproval,
    permissionProfile: PermissionProfile,
    matching: PatchPolicyMatcher
) throws -> SafetyCheck {
    if action.isEmpty {
        return .reject(reason: "empty patch")
    }

    switch policy {
    case .never, .onRequest, .granular:
        break
    case .unlessTrusted:
        return .askUser
    }

    let rejectsSandboxApproval: Bool
    switch policy {
    case .never:
        rejectsSandboxApproval = true
    case .granular(let config):
        rejectsSandboxApproval = !config.sandboxApproval
    default:
        rejectsSandboxApproval = false
    }

    let sandboxAvailable: Bool
    switch matching.sandboxRoute {
    case .executorManaged:
        sandboxAvailable = true
    case .platform(let windowsSandboxLevel):
        sandboxAvailable = getPlatformSandbox(
            windowsSandboxEnabled: windowsSandboxLevel != .disabled
        ) != nil
    }

    if try isWritePatchConstrainedToWritablePaths(action, matching: matching)
        && (matchesDisabledOrExternal(permissionProfile) || sandboxAvailable) {
        return .autoApprove
    }
    if rejectsSandboxApproval {
        return .reject(
            reason: patchRejectionReason(
                permissionProfile,
                matching.configuredPolicy,
                matching.context
            )
        )
    }
    return .askUser
}

private func matchesDisabledOrExternal(_ profile: PermissionProfile) -> Bool {
    switch profile {
    case .disabled, .external: return true
    case .managed: return false
    }
}

private func patchRejectionReason(
    _ permissionProfile: PermissionProfile,
    _ fileSystemSandboxPolicy: FileSystemSandboxPolicy,
    _ context: FileSystemSandboxPolicyContext
) -> String {
    let hasNoWritableRoots = !fileSystemSandboxPolicy.hasConfiguredWritableRoots(context)
    switch permissionProfile {
    case .managed
        where !fileSystemSandboxPolicy.hasFullDiskWriteAccess(context: context)
            && hasNoWritableRoots:
        return PATCH_REJECTED_READ_ONLY_REASON
    default:
        return PATCH_REJECTED_OUTSIDE_PROJECT_REASON
    }
}

private func isWritePatchConstrainedToWritablePaths(
    _ action: ApplyPatchAction,
    matching: PatchPolicyMatcher
) throws -> Bool {
    if matching.configuredPolicy.hasFullDiskWriteAccess(context: matching.context) {
        return true
    }
    for (path, change) in action.changes() {
        switch change {
        case .add, .delete:
            if try !matching.canWritePath(path) { return false }
        case .update(_, let movePath, _):
            if try !matching.canWritePath(path) { return false }
            if let dest = movePath, try !matching.canWritePath(dest) { return false }
        }
    }
    return true
}

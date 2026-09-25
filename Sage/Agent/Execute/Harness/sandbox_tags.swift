//
//  sandbox_tags.swift
//  Sage
//
//  Port of codex-rs/core/src/sandbox_tags.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Diagnostic labels only — never used for authorization.
//  `CodexResponsesMetadata` (Phase 6) is represented by the local
//  `SandboxDiagnosticMetadata` sink until that type is ported.
//

import CodexProtocol
import CodexSandboxing
import FileSystem
import Foundation

struct SandboxDiagnosticMetadata {
    var sandbox: String?
    var sandboxMode: String?
}

struct SandboxTags {
    var sandbox: String
    var policy: String

    init(
        profile: PermissionProfile,
        cwd: String,
        windowsSandboxSelection: WindowsSandboxSelection,
        enforceManagedNetwork: Bool
    ) {
        sandbox = permissionProfileSandboxTag(
            profile,
            windowsSandboxSelection: windowsSandboxSelection,
            enforceManagedNetwork: enforceManagedNetwork
        )
        policy = permissionProfilePolicyTag(profile, cwd: cwd)
    }

    func appendMetricTags(_ tags: inout [(String, String)]) {
        tags.append(("sandbox", sandbox))
        tags.append(("sandbox_policy", policy))
    }

    func recordMetadata(_ metadata: inout SandboxDiagnosticMetadata) {
        metadata.sandbox = sandbox
        metadata.sandboxMode = policy
    }
}

func recordPolicyMetadata(
    profile: PermissionProfile,
    cwd: String,
    metadata: inout SandboxDiagnosticMetadata
) {
    metadata.sandboxMode = permissionProfilePolicyTag(profile, cwd: cwd)
}

private func permissionProfileSandboxTag(
    _ profile: PermissionProfile,
    windowsSandboxSelection: WindowsSandboxSelection,
    enforceManagedNetwork: Bool
) -> String {
    switch profile {
    case .disabled:
        return "none"
    case .external:
        return "external"
    case .managed(let fileSystem, let network):
        let fileSystemPolicy = fileSystem.toSandboxPolicy()
        if !shouldRequirePlatformSandbox(
            fileSystemPolicy: fileSystemPolicy,
            networkPolicy: network,
            hasManagedNetworkRequirements: enforceManagedNetwork
        ) {
            return "none"
        }
    }
    switch windowsSandboxSelection {
    case .mxc:
        return SandboxType.windowsMxc.metricTag
    case .elevated:
        return "windows_elevated"
    case .restrictedToken:
        return SandboxType.windowsRestrictedToken.metricTag
    case .disabled:
        return getPlatformSandbox(windowsSandboxEnabled: false)?.metricTag ?? "none"
    }
}

private func permissionProfilePolicyTag(_ profile: PermissionProfile, cwd: String) -> String {
    switch profile {
    case .disabled:
        return "danger-full-access"
    case .external:
        return "external-sandbox"
    case .managed:
        let fileSystemPolicy = profile.fileSystemSandboxPolicy()
        if fileSystemPolicy.hasFullDiskWriteAccess() {
            return "danger-full-access"
        }
        if !fileSystemPolicy.hasConfiguredWritableRootsWithCwd(cwd) {
            return "read-only"
        }
        return "workspace-write"
    }
}

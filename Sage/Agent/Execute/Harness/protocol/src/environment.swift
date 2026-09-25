//
//  environment.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/environment.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `RequirementsExecPolicy` (execpolicy crate, Phase 3) and
//  `EnvironmentNetworkPolicy` (network-proxy, excluded) are type placeholders
//  until those crates are ported. `PermissionProfile` /
//  `PermissionProfileSnapshot` come from models + snapshot files (same module).
//

import CodexUtils
import Foundation

/// Type placeholder for `codex_execpolicy::RequirementsExecPolicy` until Phase 3.
public struct RequirementsExecPolicy: Equatable, Sendable {
    public var raw: String

    public init(raw: String) {
        self.raw = raw
    }
}

/// Type placeholder for `codex_network_proxy::EnvironmentNetworkPolicy` until Phase 4.
public struct EnvironmentNetworkPolicy: Equatable, Sendable {
    public var raw: JSONValue?

    public init(raw: JSONValue? = nil) {
        self.raw = raw
    }
}

/// Configuration supplied for a thread's selected environment.
public enum EnvironmentConfigState: Equatable, Sendable {
    /// Preserve the existing thread-derived environment configuration.
    case fromThread
    /// The owner will supply environment configuration later.
    case pending
    /// The owner supplied configuration for this environment attachment.
    case ready(EnvironmentConfig)
    /// The owner could not supply configuration for this environment attachment.
    case failed(String)
}

/// Full Access requires no approvals and unrestricted permissions everywhere selected.
/// Thread-owned attachments inherit the fallback profile; unresolved owner authority
/// is never Full Access. All approval and background-review paths use this decision.
public func hasFullAccess(
    approvalPolicy: AskForApproval,
    threadProfile: PermissionProfile,
    environments: [EnvironmentConfigState]
) -> Bool {
    guard approvalPolicy == .never else { return false }
    if environments.isEmpty {
        return isDisabledPermissionProfile(threadProfile)
    }
    return environments.allSatisfy { environment in
        switch environment {
        case .fromThread:
            return isDisabledPermissionProfile(threadProfile)
        case .ready(let config):
            return isDisabledPermissionProfile(config.permissionProfile.permissionProfile())
        case .pending, .failed:
            return false
        }
    }
}

private func isDisabledPermissionProfile(_ profile: PermissionProfile) -> Bool {
    if case .disabled = profile { return true }
    return false
}

/// Resolved configuration for a thread/environment attachment.
public struct EnvironmentConfig: Equatable, Sendable {
    /// Whether shell tools may start login shells in this environment.
    public var allowLoginShell: Bool
    /// Effective workspace roots resolved for this environment attachment.
    public var workspaceRoots: [PathUri]
    /// Resolved permissions for this thread's environment attachment.
    public var permissionProfile: PermissionProfileSnapshot
    /// Controls which environment variables shell commands may inherit.
    public var shellEnvironmentPolicy: ShellEnvironmentPolicy
    /// Legacy Windows restricted-token setup level for this environment attachment.
    public var windowsSandboxLevel: WindowsSandboxLevel
    /// Concrete Windows sandbox backend selected for this environment attachment.
    public var windowsSandboxType: SandboxType
    /// Whether Linux sandbox processes use the legacy Landlock backend.
    public var useLegacyLandlock: Bool
    /// Additional managed command restrictions for this environment attachment.
    public var execPolicy: RequirementsExecPolicy?
    /// Additional managed MCP restrictions for this environment attachment.
    public var mcpPolicy: EnvironmentMcpPolicy?
    /// Owner-provided traffic restrictions. `nil` keeps the existing controller policy.
    public var networkPolicy: EnvironmentNetworkPolicy?
    /// Capability roots selected for this thread's environment attachment.
    public var selectedCapabilityRoots: [SelectedCapabilityRoot]

    public init(
        allowLoginShell: Bool,
        workspaceRoots: [PathUri],
        permissionProfile: PermissionProfileSnapshot,
        shellEnvironmentPolicy: ShellEnvironmentPolicy,
        windowsSandboxLevel: WindowsSandboxLevel,
        windowsSandboxType: SandboxType,
        useLegacyLandlock: Bool,
        execPolicy: RequirementsExecPolicy? = nil,
        mcpPolicy: EnvironmentMcpPolicy? = nil,
        networkPolicy: EnvironmentNetworkPolicy? = nil,
        selectedCapabilityRoots: [SelectedCapabilityRoot] = []
    ) {
        self.allowLoginShell = allowLoginShell
        self.workspaceRoots = workspaceRoots
        self.permissionProfile = permissionProfile
        self.shellEnvironmentPolicy = shellEnvironmentPolicy
        self.windowsSandboxLevel = windowsSandboxLevel
        self.windowsSandboxType = windowsSandboxType
        self.useLegacyLandlock = useLegacyLandlock
        self.execPolicy = execPolicy
        self.mcpPolicy = mcpPolicy
        self.networkPolicy = networkPolicy
        self.selectedCapabilityRoots = selectedCapabilityRoots
    }
}

extension EnvironmentConfig: CustomDebugStringConvertible {
    public var debugDescription: String {
        "EnvironmentConfig(allowLoginShell: \(allowLoginShell), workspaceRoots: \(workspaceRoots), permissionProfile: \(permissionProfile), shellEnvironmentPolicy: <redacted>, windowsSandboxLevel: \(windowsSandboxLevel), windowsSandboxType: \(windowsSandboxType), useLegacyLandlock: \(useLegacyLandlock), execPolicy: \(String(describing: execPolicy)), mcpPolicy: \(String(describing: mcpPolicy)), networkPolicy: \(String(describing: networkPolicy)), selectedCapabilityRoots: \(selectedCapabilityRoots))"
    }
}

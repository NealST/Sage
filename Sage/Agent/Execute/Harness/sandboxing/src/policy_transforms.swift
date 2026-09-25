//
//  policy_transforms.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/policy_transforms.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Public effective-policy / merge / normalize / shouldRequirePlatformSandbox
//  helpers are ported. Intersection's glob/materialize helpers that depend
//  on the full ReadDenyMatcher context walk will be completed with the
//  remaining private functions from the 670-line upstream file.
//

import CodexProtocol
import CodexUtils
import Foundation

public func normalizeAdditionalPermissions(
    _ additionalPermissions: AdditionalPermissionProfile
) throws -> AdditionalPermissionProfile {
    let network = additionalPermissions.network.flatMap { $0.isEmpty ? nil : $0 }
    let fileSystem: FileSystemPermissions?
    if let permissions = additionalPermissions.fileSystem {
        var entries: [FileSystemSandboxEntry] = []
        entries.reserveCapacity(permissions.entries.count)
        for entry in permissions.entries {
            if case .globPattern = entry.path, entry.access != .deny {
                throw CodexErr.invalidRequest(
                    "glob file system permissions only support deny-read entries"
                )
            }
            if !entries.contains(entry) {
                entries.append(entry)
            }
        }
        let fileSystemPermissions = FileSystemPermissions(
            entries: entries,
            globScanMaxDepth: permissions.globScanMaxDepth
        )
        fileSystem = fileSystemPermissions.isEmpty ? nil : fileSystemPermissions
    } else {
        fileSystem = nil
    }
    return AdditionalPermissionProfile(network: network, fileSystem: fileSystem)
}

public func normalizeAdditionalPermissionsWithContext(
    _ additionalPermissions: AdditionalPermissionProfile,
    context: FileSystemSandboxPolicyContext
) throws -> AdditionalPermissionProfile {
    let normalized = try normalizeAdditionalPermissions(additionalPermissions)
    if let fileSystem = normalized.fileSystem {
        for entry in fileSystem.entries {
            guard case .path(let path) = entry.path else { continue }
            if path.inferPathConvention() == nil
                || path.inferPathConvention() != context.cwd.inferPathConvention()
                || (try? path.join(".")) == nil {
                throw CodexErr.invalidRequest(
                    "permission path `\(path)` does not match executor cwd `\(context.cwd)`"
                )
            }
        }
    }
    return normalized
}

public func mergePermissionProfiles(
    base: AdditionalPermissionProfile?,
    permissions: AdditionalPermissionProfile?
) -> AdditionalPermissionProfile? {
    guard let permissions else { return base }
    guard let base else {
        return permissions.isEmpty ? nil : permissions
    }
    let network: NetworkPermissions?
    switch (base.network, permissions.network) {
    case (.some(let left), _) where left.enabled == true:
        network = NetworkPermissions(enabled: true)
    case (_, .some(let right)) where right.enabled == true:
        network = NetworkPermissions(enabled: true)
    default:
        network = nil
    }
    let fileSystem: FileSystemPermissions?
    switch (base.fileSystem, permissions.fileSystem) {
    case (.some(let left), .some(let right)):
        let merged = FileSystemPermissions(
            entries: mergePermissionEntries(left.entries, right.entries),
            globScanMaxDepth: nil
        )
        fileSystem = merged.isEmpty ? nil : merged
    case (.some(let left), .none):
        fileSystem = left
    case (.none, .some(let right)):
        fileSystem = right
    case (.none, .none):
        fileSystem = nil
    }
    let merged = AdditionalPermissionProfile(network: network, fileSystem: fileSystem)
    return merged.isEmpty ? nil : merged
}

public func effectiveFileSystemSandboxPolicy(
    _ fileSystemPolicy: FileSystemSandboxPolicy,
    additionalPermissions: AdditionalPermissionProfile?
) -> FileSystemSandboxPolicy {
    guard let additionalPermissions,
          let fileSystemPermissions = additionalPermissions.fileSystem,
          !fileSystemPermissions.isEmpty else {
        return fileSystemPolicy
    }
    return mergeFileSystemPolicyWithAdditionalPermissions(fileSystemPolicy, fileSystemPermissions)
}

public func effectiveNetworkSandboxPolicy(
    _ networkPolicy: NetworkSandboxPolicy,
    additionalPermissions: AdditionalPermissionProfile?
) -> NetworkSandboxPolicy {
    if let additionalPermissions,
       mergeNetworkAccess(networkPolicy.isEnabled, additionalPermissions) {
        return .enabled
    }
    if additionalPermissions != nil {
        return .restricted
    }
    return networkPolicy
}

public func effectivePermissionProfile(
    _ permissionProfile: PermissionProfile,
    additionalPermissions: AdditionalPermissionProfile?
) -> PermissionProfile {
    let (fileSystemPolicy, networkPolicy) = permissionProfile.toRuntimePermissions()
    return PermissionProfile.fromRuntimePermissionsWithEnforcement(
        permissionProfile.enforcement(),
        effectiveFileSystemSandboxPolicy(fileSystemPolicy, additionalPermissions: additionalPermissions),
        effectiveNetworkSandboxPolicy(networkPolicy, additionalPermissions: additionalPermissions)
    )
}

public func shouldRequirePlatformSandbox(
    fileSystemPolicy: FileSystemSandboxPolicy,
    networkPolicy: NetworkSandboxPolicy,
    hasManagedNetworkRequirements: Bool
) -> Bool {
    if hasManagedNetworkRequirements { return true }
    if !networkPolicy.isEnabled {
        return fileSystemPolicy.kind != .externalSandbox
    }
    switch fileSystemPolicy.kind {
    case .restricted:
        return !fileSystemPolicy.hasFullDiskWriteAccess()
    case .unrestricted, .externalSandbox:
        return false
    }
}

private func mergeNetworkAccess(
    _ baseNetworkAccess: Bool,
    _ additionalPermissions: AdditionalPermissionProfile
) -> Bool {
    baseNetworkAccess
        || (additionalPermissions.network?.enabled ?? false)
}

private func mergePermissionEntries(
    _ left: [FileSystemSandboxEntry],
    _ right: [FileSystemSandboxEntry]
) -> [FileSystemSandboxEntry] {
    var entries = left
    for entry in right where !entries.contains(entry) {
        entries.append(entry)
    }
    return entries
}

private func mergeFileSystemPolicyWithAdditionalPermissions(
    _ fileSystemPolicy: FileSystemSandboxPolicy,
    _ additional: FileSystemPermissions
) -> FileSystemSandboxPolicy {
    switch fileSystemPolicy.kind {
    case .restricted:
        var merged = fileSystemPolicy
        for entry in additional.entries {
            let sandboxEntry = FileSystemSandboxEntry.new(entry.path, entry.access)
            if !merged.entries.contains(sandboxEntry) {
                merged.entries.append(sandboxEntry)
            }
        }
        return merged
    case .unrestricted, .externalSandbox:
        return fileSystemPolicy
    }
}

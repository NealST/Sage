//
//  policy_transforms.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/policy_transforms.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Normalize / merge / intersect / materialize / effective-policy helpers
//  match upstream. `Result<_, String>` is `CodexErr.invalidRequest`.
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

/// Resolves cwd-dependent permission entries without filtering their authority.
///
/// Unlike intersection, this preserves narrower grants beneath denied paths.
public func materializeAdditionalPermissionsWithContext(
    _ additionalPermissions: AdditionalPermissionProfile,
    context: FileSystemSandboxPolicyContext
) throws -> AdditionalPermissionProfile {
    var additionalPermissions = additionalPermissions
    if var fileSystem = additionalPermissions.fileSystem {
        guard let entries = materializeContextDependentEntries(fileSystem.entries, context: context) else {
            throw CodexErr.invalidRequest(
                "unable to resolve permission path in `\(context.cwd)`"
            )
        }
        fileSystem.entries = entries
        additionalPermissions.fileSystem = fileSystem
    }
    return try normalizeAdditionalPermissionsWithContext(additionalPermissions, context: context)
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
            globScanMaxDepth: mergeGlobScanMaxDepth(
                left.entries, left.globScanMaxDepth,
                right.entries, right.globScanMaxDepth)
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

public func intersectPermissionProfilesWithContext(
    requested: AdditionalPermissionProfile,
    granted: AdditionalPermissionProfile,
    context: FileSystemSandboxPolicyContext
) -> AdditionalPermissionProfile {
    let fileSystem: FileSystemPermissions? = requested.fileSystem.flatMap { requestedFileSystem in
        let grantedFileSystem = granted.fileSystem ?? FileSystemPermissions()
        guard let requestedEntries = materializeContextDependentEntries(
            requestedFileSystem.entries, context: context
        ),
        let grantedEntries = materializeContextDependentEntries(
            grantedFileSystem.entries, context: context
        ) else {
            return nil
        }
        let requestedPolicy = FileSystemSandboxPolicy.restricted(requestedEntries)
        let requestedReadDenyMatcher = ReadDenyMatcher.fromContext(requestedPolicy, context: context)
        var acceptedEntries: [FileSystemSandboxEntry] = []
        for entry in grantedEntries where grantedFileSystemEntryWithinRequest(
            requested: requestedFileSystem,
            requestedPolicy: requestedPolicy,
            requestedReadDenyMatcher: requestedReadDenyMatcher,
            grantedEntry: entry,
            context: context
        ) {
            if !acceptedEntries.contains(entry) {
                acceptedEntries.append(entry)
            }
        }
        var entries = acceptedEntries
        let requestedRetained = retainConstrainingDenyEntries(
            requestedEntries, acceptedEntries: acceptedEntries, context: context, output: &entries)
        let grantedRetained = retainConstrainingDenyEntries(
            grantedEntries, acceptedEntries: acceptedEntries, context: context, output: &entries)
        let permissions = FileSystemPermissions(
            entries: entries,
            globScanMaxDepth: mergeGlobScanMaxDepth(
                requestedRetained, requestedFileSystem.globScanMaxDepth,
                grantedRetained, grantedFileSystem.globScanMaxDepth)
        )
        return permissions.isEmpty ? nil : permissions
    }
    let network: NetworkPermissions?
    if requested.network?.enabled == true, granted.network?.enabled == true {
        network = NetworkPermissions(enabled: true)
    } else {
        network = nil
    }
    return AdditionalPermissionProfile(network: network, fileSystem: fileSystem)
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

private enum GlobScanDepth: Equatable {
    case bounded(Int)
    case unbounded
}

private func mergeGlobScanMaxDepth(
    _ leftEntries: [FileSystemSandboxEntry],
    _ leftDepth: Int?,
    _ rightEntries: [FileSystemSandboxEntry],
    _ rightDepth: Int?
) -> Int? {
    let left = effectiveGlobScanDepth(leftEntries, leftDepth)
    let right = effectiveGlobScanDepth(rightEntries, rightDepth)
    switch (left, right) {
    case (.some(.unbounded), _), (_, .some(.unbounded)):
        return nil
    case (.some(.bounded(let lhs)), .some(.bounded(let rhs))):
        return max(lhs, rhs)
    case (.some(.bounded(let depth)), .none), (.none, .some(.bounded(let depth))):
        return depth
    case (.none, .none):
        return nil
    }
}

private func effectiveGlobScanDepth(
    _ entries: [FileSystemSandboxEntry],
    _ depth: Int?
) -> GlobScanDepth? {
    let hasDenyGlob = entries.contains { entry in
        guard entry.access == .deny else { return false }
        if case .globPattern = entry.path { return true }
        return false
    }
    guard hasDenyGlob else { return nil }
    if let depth { return .bounded(depth) }
    return .unbounded
}

private func grantedFileSystemEntryWithinRequest(
    requested: FileSystemPermissions,
    requestedPolicy: FileSystemSandboxPolicy,
    requestedReadDenyMatcher: ReadDenyMatcher?,
    grantedEntry: FileSystemSandboxEntry,
    context: FileSystemSandboxPolicyContext
) -> Bool {
    if !grantedEntry.access.canRead() {
        return false
    }
    if case .special(let value) = grantedEntry.path, value == .slashTmp,
       context.cwd.inferPathConvention() != .posix {
        return false
    }
    if context.cwd.inferPathConvention() == .windows,
       isRootEntry(grantedEntry),
       !requested.entries.contains(where: {
           isRootEntry($0) && accessCovers($0.access, granted: grantedEntry.access)
       }) {
        return false
    }
    if let path = resolvePermissionPath(grantedEntry.path, context: context) {
        if path.inferPathConvention() != context.cwd.inferPathConvention()
            || requestedReadDenyMatcher?.isReadDeniedUri(path, context: context) == true {
            return false
        }
        return accessCovers(
            requestedPolicy.resolveAccess(path, context: context),
            granted: grantedEntry.access)
    }
    return requested.entries.contains {
        accessCovers($0.access, granted: grantedEntry.access) && $0.path == grantedEntry.path
    }
}

private func retainConstrainingDenyEntries(
    _ sourceEntries: [FileSystemSandboxEntry],
    acceptedEntries: [FileSystemSandboxEntry],
    context: FileSystemSandboxPolicyContext,
    output: inout [FileSystemSandboxEntry]
) -> [FileSystemSandboxEntry] {
    var retained: [FileSystemSandboxEntry] = []
    for entry in sourceEntries where entry.access == .deny {
        guard denyEntryConstrainsAcceptedGrant(entry, acceptedEntries: acceptedEntries, context: context) else {
            continue
        }
        if !output.contains(entry) {
            output.append(entry)
        }
        retained.append(entry)
    }
    return retained
}

private func denyEntryConstrainsAcceptedGrant(
    _ denyEntry: FileSystemSandboxEntry,
    acceptedEntries: [FileSystemSandboxEntry],
    context: FileSystemSandboxPolicyContext
) -> Bool {
    acceptedEntries
        .filter { $0.access.canRead() }
        .contains { entry in
            if isRootEntry(entry) { return true }
            guard let grantPath = resolvePermissionPath(entry.path, context: context) else {
                return true
            }
            switch denyEntry.path {
            case .globPattern(let pattern):
                if let prefix = globStaticPrefixPath(pattern, context: context) {
                    return pathsOverlap(prefix, grantPath)
                }
                return true
            case .path, .special:
                if let denyPath = resolvePermissionPath(denyEntry.path, context: context) {
                    return pathsOverlap(denyPath, grantPath)
                }
                return true
            }
        }
}

private func globStaticPrefixPath(
    _ pattern: String,
    context: FileSystemSandboxPolicyContext
) -> PathUri? {
    let isWindows = context.cwd.inferPathConvention() == .windows
    let wildcardChars: [Character] = ["*", "?", "[", "]"]
    let prefix: String
    let wildcardInSegment: Bool
    if let index = pattern.firstIndex(where: { wildcardChars.contains($0) }) {
        if index == pattern.startIndex { return nil }
        prefix = String(pattern[..<index])
        wildcardInSegment = !(prefix.hasSuffix("/") || (isWindows && prefix.hasSuffix("\\")))
    } else {
        prefix = pattern
        wildcardInSegment = false
    }
    guard let joined = try? context.cwd.join(prefix) else { return nil }
    return wildcardInSegment ? joined.parent() : joined
}

private func pathsOverlap(_ left: PathUri, _ right: PathUri) -> Bool {
    left.overlaps(right) ?? true
}

private func accessCovers(_ requested: FileSystemAccessMode, granted: FileSystemAccessMode) -> Bool {
    switch granted {
    case .read: return requested.canRead()
    case .write: return requested.canWrite()
    case .deny: return false
    }
}

private func isRootEntry(_ entry: FileSystemSandboxEntry) -> Bool {
    if case .special(.root) = entry.path { return true }
    return false
}

private func materializeCwdDependentEntry(
    _ entry: FileSystemSandboxEntry,
    context: FileSystemSandboxPolicyContext
) -> FileSystemSandboxEntry? {
    switch entry.path {
    case .globPattern(let pattern):
        let isWindows = context.cwd.inferPathConvention() == .windows
        let homeRelative: String?
        if let suffix = pattern.stripPrefix("~/") {
            homeRelative = suffix
        } else if pattern == "~" {
            homeRelative = ""
        } else if isWindows {
            homeRelative = pattern.stripPrefix("~\\")
        } else {
            homeRelative = nil
        }
        let root: PathUri
        let relative: String
        if let suffix = homeRelative {
            guard let home = context.userHomeDir else { return nil }
            root = home
            relative = String(suffix.drop(while: { $0 == "/" || (isWindows && $0 == "\\") }))
        } else {
            root = context.cwd
            relative = pattern
        }
        guard let path = try? root.join(relative) else { return nil }
        return FileSystemSandboxEntry(
            path: .globPattern(pattern: path.inferredNativePathString()),
            access: entry.access,
            missingPathBehavior: entry.missingPathBehavior)
    case .path, .special:
        return entry
    }
}

private func resolvePermissionPath(
    _ path: FileSystemPath,
    context: FileSystemSandboxPolicyContext
) -> PathUri? {
    switch path {
    case .path(let path):
        return path
    case .globPattern:
        return nil
    case .special(let value):
        switch value {
        case .root:
            return fileSystemRoot(context)
        case .projectRoots(let subpath):
            guard let root = context.workspaceRoots.first else { return nil }
            if let subpath { return try? root.join(subpath) }
            return root
        case .tmpdir:
            return context.temporaryDirectories?.first
        case .slashTmp where context.cwd.inferPathConvention() == .posix:
            return try? context.cwd.join("/tmp")
        case .slashTmp, .minimal:
            return nil
        case .unknown:
            return nil
        }
    }
}

private func materializeContextDependentEntries(
    _ entries: [FileSystemSandboxEntry],
    context: FileSystemSandboxPolicyContext
) -> [FileSystemSandboxEntry]? {
    var materialized: [FileSystemSandboxEntry] = []
    for entry in entries {
        switch entry.path {
        case .special(.projectRoots):
            var resolved: [FileSystemSandboxEntry] = []
            for root in context.workspaceRoots {
                var rootContext = context
                rootContext.workspaceRoots = [root]
                guard let path = resolvePermissionPath(entry.path, context: rootContext) else {
                    if entry.access == .deny { return nil }
                    continue
                }
                resolved.append(materializedPathEntry(entry, path: path))
            }
            if entry.access == .deny && resolved.isEmpty { return nil }
            materialized.append(contentsOf: resolved)
        case .special(.tmpdir):
            guard let temporaryDirectories = context.temporaryDirectories else {
                if entry.access == .deny { return nil }
                materialized.append(entry)
                continue
            }
            materialized.append(contentsOf: temporaryDirectories.map { materializedPathEntry(entry, path: $0) })
        case .special(.root):
            guard resolvePermissionPath(entry.path, context: context) != nil else { return nil }
            materialized.append(entry)
        default:
            guard let materializedEntry = materializeCwdDependentEntry(entry, context: context) else {
                if entry.access == .deny { return nil }
                continue
            }
            materialized.append(materializedEntry)
        }
    }
    return materialized
}

private func materializedPathEntry(
    _ entry: FileSystemSandboxEntry,
    path: PathUri
) -> FileSystemSandboxEntry {
    FileSystemSandboxEntry(
        path: .path(path: path),
        access: entry.access,
        missingPathBehavior: entry.missingPathBehavior)
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
        for entry in additional.entries where !merged.entries.contains(entry) {
            merged.entries.append(entry)
        }
        merged.globScanMaxDepth = mergeGlobScanMaxDepth(
            fileSystemPolicy.entries, fileSystemPolicy.globScanMaxDepth,
            additional.entries, additional.globScanMaxDepth)
        return merged
    case .unrestricted, .externalSandbox:
        return fileSystemPolicy
    }
}

private func mergeNetworkAccess(
    _ baseNetworkAccess: Bool,
    _ additionalPermissions: AdditionalPermissionProfile
) -> Bool {
    baseNetworkAccess || (additionalPermissions.network?.enabled ?? false)
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

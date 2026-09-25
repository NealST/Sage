//
//  permission_profile_intersection.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permission_profile_intersection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Intersects already-effective filesystem permissions and network access.
//  Concrete grant paths are canonicalized before comparison so symlinks
//  cannot acquire authority beyond either input.
//

import CodexUtils
import Foundation

/// A policy cannot be intersected without weakening either input.
public enum PermissionIntersectionError: Error, Equatable, CustomStringConvertible {
    case externalSandbox
    case platformDefaults
    case unsupportedPath(String)

    public var description: String {
        switch self {
        case .externalSandbox:
            return "externally enforced filesystem permissions cannot be intersected safely"
        case .platformDefaults:
            return "platform-default filesystem permissions cannot be intersected safely"
        case .unsupportedPath(let path):
            return "unsupported permission path: \(path)"
        }
    }
}

/// Intersects already-effective filesystem permissions and network access.
public func intersectEffectivePermissionProfiles(
    _ authority: PermissionProfile,
    _ requested: PermissionProfile,
    cwd: String
) throws -> PermissionProfile {
    if case .external = authority { throw PermissionIntersectionError.externalSandbox }
    if case .external = requested { throw PermissionIntersectionError.externalSandbox }
    do {
        _ = try AbsolutePathBuf.fromAbsolutePathChecked(cwd)
    } catch {
        throw PermissionIntersectionError.unsupportedPath(String(describing: error))
    }
    for profile in [authority, requested] {
        for entry in profile.fileSystemSandboxPolicy().entries {
            switch entry.path {
            case .path(let path):
                do {
                    _ = try path.toAbsPath()
                } catch {
                    throw PermissionIntersectionError.unsupportedPath(String(describing: error))
                }
            case .special(value: .projectRoots):
                throw PermissionIntersectionError.unsupportedPath(
                    "workspace permissions must already be materialized")
            case .globPattern(let pattern)
                where pattern.hasPrefix(projectRootsGlobPattern("")):
                throw PermissionIntersectionError.unsupportedPath(pattern)
            default:
                break
            }
        }
    }

    var authorityPolicy = authority.fileSystemSandboxPolicy()
    var requestedPolicy = requested.fileSystemSandboxPolicy()
    let rootPath = FileSystemPath.special(value: .root)
    let network: NetworkSandboxPolicy =
        authority.networkSandboxPolicy().isEnabled && requested.networkSandboxPolicy().isEnabled
        ? .enabled : .restricted
    if case .disabled = authority, case .disabled = requested {
        return .disabled
    }
    if authorityPolicy == requestedPolicy {
        return PermissionProfile.fromRuntimePermissions(authorityPolicy, network)
    }
    if authorityPolicy.kind == .unrestricted {
        return PermissionProfile.fromRuntimePermissions(requestedPolicy, network)
    }
    if requestedPolicy.kind == .unrestricted {
        return PermissionProfile.fromRuntimePermissions(authorityPolicy, network)
    }

    try normalizePolicy(&authorityPolicy)
    try normalizePolicy(&requestedPolicy)
    let tmpdir = FileSystemPath.special(value: .tmpdir)
    let tempEntries = [authorityPolicy, requestedPolicy].map { policy in
        policy.entries.filter { $0.path == tmpdir }
    }
    let commonTemp: FileSystemSandboxEntry?
    switch (tempEntries[0], tempEntries[1]) {
    case (let left, let right) where left.count == 1 && right.count == 1
        && [left[0], right[0]].allSatisfy({ $0.access.canWrite() && !$0.skipsMissingPath() }):
        commonTemp = FileSystemSandboxEntry.new(tmpdir, left[0].access)
    case ([], []):
        commonTemp = nil
    case (let left, []) where left.count == 1 && left[0].access.canWrite() && !left[0].skipsMissingPath():
        commonTemp = nil
    case ([], let right) where right.count == 1 && right[0].access.canWrite() && !right[0].skipsMissingPath():
        commonTemp = nil
    default:
        throw PermissionIntersectionError.unsupportedPath(
            ":tmpdir restrictions require executor-local bindings")
    }
    authorityPolicy.entries.removeAll { $0.path == tmpdir }
    requestedPolicy.entries.removeAll { $0.path == tmpdir }

    let authorityDenies: ReadDenyMatcher?
    let requestedDenies: ReadDenyMatcher?
    do {
        authorityDenies = try ReadDenyMatcher.tryNewForLocalPaths(authorityPolicy, cwd: cwd)
        requestedDenies = try ReadDenyMatcher.tryNewForLocalPaths(requestedPolicy, cwd: cwd)
    } catch {
        throw PermissionIntersectionError.unsupportedPath(String(describing: error))
    }
    let sources: [(FileSystemSandboxPolicy, ReadDenyMatcher?)] = [
        (authorityPolicy, authorityDenies),
        (requestedPolicy, requestedDenies),
    ]
    var paths: [AbsolutePathBuf] = []
    var denies: [FileSystemSandboxEntry] = []
    var globDepth: Int??
    for (policy, _) in sources {
        let writableRoots = policy.getWritableRootsWithCwd(cwd)
        for entry in policy.entries {
            if entry.access == .deny && !denies.contains(entry) {
                denies.append(entry)
            }
            if case .globPattern = entry.path {
                switch globDepth {
                case .none:
                    globDepth = .some(policy.globScanMaxDepth)
                case .some(.some(let previous)):
                    globDepth = .some(policy.globScanMaxDepth.map { max(previous, $0) })
                case .some(.none):
                    globDepth = .some(nil)
                }
            }
            guard let path = try entryPath(entry, cwd: cwd) else { continue }
            if entry.skipsMissingPath()
                && (entry.access != .read
                    || !writableRoots.contains { root in
                        root.readOnlySubpaths.contains(path)
                            || defaultReadOnlySubpathsForWritableRoot(
                                root.root, protectMissingDotCodex: false
                            ).contains(path)
                            || path.parent == root.root
                                && PROTECTED_METADATA_PATH_NAMES.contains {
                                    (path.asPath as NSString).lastPathComponent == $0
                                }
                    })
            {
                throw PermissionIntersectionError.unsupportedPath("non-metadata optional permissions")
            }
            paths.append(path)
        }
        paths.append(contentsOf: policy.getReadableRootsWithCwd(cwd))
        for root in writableRoots {
            paths.append(root.root)
            paths.append(contentsOf: PROTECTED_METADATA_PATH_NAMES.map { root.root.join($0) })
            paths.append(contentsOf: root.readOnlySubpaths)
        }
    }
    paths.sort { left, right in
        let lc = pathComponentCount(left.asPath)
        let rc = pathComponentCount(right.asPath)
        if lc != rc { return lc < rc }
        return left.asPath < right.asPath
    }
    var uniquePaths: [AbsolutePathBuf] = []
    for path in paths where uniquePaths.last != path {
        uniquePaths.append(path)
    }
    paths = uniquePaths
    denies.sort { formatDebugPath($0.path) < formatDebugPath($1.path) }
    var intersection = FileSystemSandboxPolicy.restricted(denies)
    if case .some(let depth) = globDepth {
        intersection.globScanMaxDepth = depth
    }
    let intersectionDenies: ReadDenyMatcher?
    do {
        intersectionDenies = try ReadDenyMatcher.tryNewForLocalPaths(intersection, cwd: cwd)
    } catch {
        throw PermissionIntersectionError.unsupportedPath(String(describing: error))
    }

    for path in paths {
        let left = effectiveAccess(sources[0].0, denies: sources[0].1, path: path.asPath, cwd: cwd)
        let right = effectiveAccess(sources[1].0, denies: sources[1].1, path: path.asPath, cwd: cwd)
        let access = intersectAccess(left, right)
        let current = effectiveAccess(intersection, denies: intersectionDenies, path: path.asPath, cwd: cwd)
        let optionalMetadata = sources.contains { policy, _ in
            policy.entries.contains { entry in
                entry.skipsMissingPath()
                    && (try? entryPath(entry, cwd: cwd)) == path
            }
        }
        let requiredRestriction = sources.contains { policy, _ in
            policy.entries.contains { entry in
                !entry.skipsMissingPath()
                    && !entry.access.canWrite()
                    && (try? entryPath(entry, cwd: cwd)) == path
            }
        }
        if access == current && !optionalMetadata && !requiredRestriction {
            continue
        }
        let resolvedPath: FileSystemPath
        if path.parent == nil
            && pathHasPrefix(cwd, prefix: path.asPath)
            && sources.allSatisfy({ policy, _ in
                policy.entries.contains { $0.path == rootPath }
            })
        {
            resolvedPath = rootPath
        } else {
            resolvedPath = FileSystemPath(path)
        }
        let entry = optionalMetadata && !requiredRestriction && access == .read
            ? FileSystemSandboxEntry.skipMissingPath(resolvedPath, access)
            : FileSystemSandboxEntry.new(resolvedPath, access)
        if !intersection.entries.contains(entry) {
            intersection.entries.append(entry)
        }
    }
    if let temp = commonTemp {
        intersection.entries.append(temp)
    }
    return PermissionProfile.fromRuntimePermissions(intersection, network)
}

func normalizePolicy(_ policy: inout FileSystemSandboxPolicy) throws {
    if policy.includePlatformDefaults() {
        throw PermissionIntersectionError.platformDefaults
    }
    for index in policy.entries.indices {
        switch policy.entries[index].path {
        case .path(let path):
            let abs: AbsolutePathBuf
            do {
                abs = try path.toAbsPath()
            } catch {
                throw PermissionIntersectionError.unsupportedPath(String(describing: error))
            }
            let entry = policy.entries[index]
            let physical: AbsolutePathBuf
            if entry.access.canWrite()
                || (entry.access == .read && !entry.skipsMissingPath())
            {
                do {
                    physical = try abs.canonicalize()
                } catch {
                    throw PermissionIntersectionError.unsupportedPath(
                        "\(abs.asPath.displayPath): \(error)")
                }
            } else {
                physical = try physicalPath(abs)
            }
            let logical: AbsolutePathBuf? = abs.ancestors().compactMap { ancestor in
                var st = stat()
                guard lstat(ancestor.asPath, &st) == 0 else { return nil }
                guard let preserved = try? canonicalizePreservingSymlinks(ancestor.asPath),
                      let suffix = pathStripPrefix(abs.asPath, prefix: ancestor.asPath),
                      let preservedAbs = try? AbsolutePathBuf.fromAbsolutePathChecked(preserved)
                else {
                    return nil
                }
                return suffix.isEmpty ? preservedAbs : preservedAbs.join(suffix)
            }.first
            if !entry.access.canWrite() && logical != physical {
                throw PermissionIntersectionError.unsupportedPath(
                    "symlinked restriction: \(abs.asPath.displayPath)")
            }
            policy.entries[index].path = FileSystemPath(physical)
        case .globPattern(let pattern)
            where policy.entries[index].access != .deny
                || policy.entries[index].skipsMissingPath():
            throw PermissionIntersectionError.unsupportedPath("glob permissions: \(pattern)")
        case .globPattern:
            break
        case .special(value: .root), .special(value: .tmpdir):
            break
        case .special(value: .slashTmp):
            do {
                let tmp = try AbsolutePathBuf.fromAbsolutePathChecked("/tmp")
                policy.entries[index].path = FileSystemPath(try physicalPath(tmp))
            } catch let error as PermissionIntersectionError {
                throw error
            } catch {
                throw PermissionIntersectionError.unsupportedPath(String(describing: error))
            }
        case .special(value: .minimal):
            throw PermissionIntersectionError.platformDefaults
        case .special(let value):
            throw PermissionIntersectionError.unsupportedPath(String(describing: value))
        }
    }
}

func entryPath(
    _ entry: FileSystemSandboxEntry,
    cwd: String
) throws -> AbsolutePathBuf? {
    switch entry.path {
    case .path(let path):
        do {
            return try path.toAbsPath()
        } catch {
            throw PermissionIntersectionError.unsupportedPath(String(describing: error))
        }
    case .special(value: .root):
        let root = URL(fileURLWithPath: cwd).pathComponents.first.map { _ in "/" } ?? "/"
        guard let abs = try? AbsolutePathBuf.fromAbsolutePathChecked(root) else {
            throw PermissionIntersectionError.unsupportedPath(cwd)
        }
        return abs
    case .special(value: .tmpdir), .special(value: .slashTmp):
        return nil
    case .special(let value):
        throw PermissionIntersectionError.unsupportedPath(String(describing: value))
    case .globPattern:
        return nil
    }
}

func physicalPath(_ path: AbsolutePathBuf) throws -> AbsolutePathBuf {
    for ancestor in path.ancestors() {
        if let physical = try? ancestor.canonicalize(),
           let suffix = pathStripPrefix(path.asPath, prefix: ancestor.asPath)
        {
            return suffix.isEmpty ? physical : physical.join(suffix)
        }
    }
    throw PermissionIntersectionError.unsupportedPath(path.asPath.displayPath)
}

func effectiveAccess(
    _ policy: FileSystemSandboxPolicy,
    denies: ReadDenyMatcher?,
    path: String,
    cwd: String
) -> FileSystemAccessMode {
    if denies?.isLocalPathReadDenied(path) == true {
        return .deny
    }
    if policy.canWriteLocalPathWithCwd(path, cwd: cwd) {
        return .write
    }
    if policy.canReadLocalPathWithCwd(path, cwd: cwd) {
        return .read
    }
    return .deny
}

func intersectAccess(
    _ left: FileSystemAccessMode,
    _ right: FileSystemAccessMode
) -> FileSystemAccessMode {
    switch (left, right) {
    case (.deny, _), (_, .deny):
        return .deny
    case (.write, .write):
        return .write
    default:
        return .read
    }
}

private func pathComponentCount(_ path: String) -> Int {
    URL(fileURLWithPath: path).pathComponents.count
}

private func formatDebugPath(_ path: FileSystemPath) -> String {
    String(describing: path)
}

private extension String {
    var displayPath: String { self }
}

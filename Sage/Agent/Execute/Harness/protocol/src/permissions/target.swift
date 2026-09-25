//
//  target.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permissions/target.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Executor-context policy operations that never consult controller paths
//  or environment. Read-deny matching and workspace-root materialization
//  stay on PathUri facts supplied by the caller.
//

import CodexUtils
import Foundation

private let invalidPath = "managed filesystem denial cannot be materialized safely"
private let shadowed = "managed filesystem denial is shadowed by a selected profile grant"

extension ReadDenyMatcher {
    /// Builds a strict matcher using only the supplied execution-host paths.
    public static func tryNewWithContext(
        _ policy: FileSystemSandboxPolicy,
        context: FileSystemSandboxPolicyContext
    ) throws -> ReadDenyMatcher? {
        guard hasContextReadDenials(policy, context: context) else { return nil }
        try validateContextPaths(policy, context: context)
        let prepared = try policy.prepareDenyReadMatcher(
            context: context,
            invalidGlobBehavior: .returnError
        )
        return ReadDenyMatcher(
            nativeCwd: nil,
            userHomeDir: nil,
            temporaryDirectories: [],
            prepared: prepared
        )
    }
}

extension FileSystemSandboxPolicy {
    /// Checks exact-root read access using paths owned by the execution host.
    /// Deny glob enforcement is checked separately with `ReadDenyMatcher`.
    public func canReadPath(_ path: PathUri, context: FileSystemSandboxPolicyContext) -> Bool {
        resolveAccess(path, context: context).canRead()
    }

    /// Preserves workspace-root symbols and adds their executor-owned concrete paths.
    /// Legacy home-relative workspace denials clear all grants when their target is unknown.
    public func withMaterializedProjectRootsForPathUris(_ roots: [PathUri]) -> FileSystemSandboxPolicy {
        guard let materialized = cloneForMaterialize().tryMaterializeProjectRootsWithPathUris(roots) else {
            return .restricted([])
        }
        var copy = self
        for entry in materialized.entries where !copy.entries.contains(entry) {
            copy.entries.append(entry)
        }
        return copy
    }

    /// Builds workspace-write defaults without inspecting the execution host's filesystem.
    public static func workspaceWriteWithPathUris(
        _ roots: [PathUri],
        excludeTmpdirEnvVar: Bool,
        excludeSlashTmp: Bool
    ) -> FileSystemSandboxPolicy {
        workspaceWrite([], excludeTmpdirEnvVar: excludeTmpdirEnvVar, excludeSlashTmp: excludeSlashTmp)
            .withMaterializedProjectRootsForPathUris(roots)
    }

    /// Returns explicitly denied roots using only the selected executor's paths.
    public func getUnreadableRootsWithContext(
        _ context: FileSystemSandboxPolicyContext
    ) throws -> [PathUri] {
        guard kind == .restricted else { return [] }
        if context.temporaryDirectories == nil
            && entries.contains(where: { entry in
                entry.access == .deny
                    && {
                        if case .special(value: .tmpdir) = entry.path { return true }
                        return false
                    }()
            })
        {
            throw PermissionStringError("executor did not report its denied temporary directories")
        }
        let filesystemRoot = fileSystemRoot(context)
        var seen = Set<PathUri>()
        var roots: [PathUri] = []
        for (path, access) in resolvedEntries(context) where access == .deny {
            if let filesystemRoot, path.startsWith(filesystemRoot) && filesystemRoot.startsWith(path) {
                continue
            }
            if seen.insert(path).inserted {
                roots.append(path)
            }
        }
        return roots
    }

    /// Resolves deny glob text using the execution host's convention and home.
    public func getUnreadableGlobsWithContext(
        _ context: FileSystemSandboxPolicyContext
    ) throws -> [String] {
        try denyReadGlobs(context)
    }

    /// Checks the existing Core rules for required entries and readable concrete paths.
    public func validateManagedDenyRead(
        _ required: FileSystemSandboxPolicy,
        context: FileSystemSandboxPolicyContext
    ) throws {
        let validator = try DenyReadValidator(required: required, context: context)
        do {
            try validator.validate(self, context: context)
        } catch {
            throw PermissionStringError(shadowed)
        }
    }

    private func cloneForMaterialize() -> FileSystemSandboxPolicy { self }
}

func validateContextPaths(
    _ policy: FileSystemSandboxPolicy,
    context: FileSystemSandboxPolicyContext
) throws {
    guard let convention = context.cwd.inferPathConvention() else {
        throw PermissionStringError(invalidPath)
    }
    func valid(_ path: PathUri) -> Bool {
        path.inferPathConvention() == convention && path.lexicalDepth() != nil
    }
    if !valid(context.cwd) || context.workspaceRoots.contains(where: { !valid($0) }) {
        throw PermissionStringError(invalidPath)
    }
    for entry in policy.entries {
        switch entry.path {
        case .path(let path) where !valid(path):
            throw PermissionStringError(invalidPath)
        case .special(value: .tmpdir):
            guard let directories = context.temporaryDirectories else {
                throw PermissionStringError(
                    "executor temporary-directory metadata is unavailable for managed filesystem denials")
            }
            if directories.contains(where: { !valid($0) }) {
                throw PermissionStringError(
                    "executor temporary-directory metadata cannot be materialized safely")
            }
        case .special(value: .projectRoots(let subpath?))
            where context.workspaceRoots.contains(where: { (try? $0.join(subpath)) == nil }):
            throw PermissionStringError(invalidPath)
        case .globPattern(let pattern)
            where (pattern.hasPrefix("~/")
                || (convention == .windows && pattern.hasPrefix("~\\")))
                && !(context.userHomeDir.map(valid) ?? false):
            throw PermissionStringError(invalidPath)
        default:
            break
        }
    }
}

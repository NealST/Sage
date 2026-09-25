//
//  local_aliases.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/permissions/local_aliases.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Prepare local policy paths in the sandbox's trusted system-alias
//  namespace. `AbsolutePathBuf.normalizeSystemAliases` is not ported yet
//  and is an identity on POSIX/macOS, so macOS `/var` ↔ `/private/var`
//  folding is skipped until that helper lands on AbsolutePathBuf.
//

import CodexUtils
import Foundation

/// Owns native environment bindings so one matcher can serve a whole root calculation.
struct LocalPolicyContext {
    var cwd: PathUri
    var userHomeDir: PathUri?
    var temporaryDirectories: [PathUri]

    init?(cwd: String) {
        guard let abs = try? AbsolutePathBuf.fromAbsolutePath(cwd) else { return nil }
        self.cwd = PathUri(abs)
        self.userHomeDir = try? PathUri.fromHostNativePath("~")
        self.temporaryDirectories = localTemporaryDirectories()
    }

    func asContext() -> FileSystemSandboxPolicyContext {
        FileSystemSandboxPolicyContext(
            cwd: cwd,
            workspaceRoots: [cwd],
            userHomeDir: userHomeDir,
            temporaryDirectories: temporaryDirectories
        )
    }
}

/// An operation-scoped view of a configured policy with local roots resolved.
public struct LocalFileSystemPolicyMatcher {
    var policy: FileSystemSandboxPolicy
    var context: FileSystemSandboxPolicyContext
}

extension FileSystemSandboxPolicy {
    /// Prepare local permission matching, resolving trusted aliases on macOS.
    /// Remote paths must use `canWritePath` instead.
    public func prepareLocalMatching(
        context: FileSystemSandboxPolicyContext
    ) throws -> LocalFileSystemPolicyMatcher {
        var policy = self
        #if os(macOS)
        policy.entries = policy.entries.filter { entry in
            switch entry.path {
            case .globPattern:
                return true
            case .special(value: .root), .special(value: .minimal), .special(value: .unknown):
                return true
            default:
                return false
            }
        }
        for (root, access) in resolvedEntries(context) {
            if root.isOpaque() { continue }
            do {
                let normalized = try root.toAbsPath().normalizeSystemAliases()
                policy.entries.append(FileSystemSandboxEntry.new(FileSystemPath(normalized), access))
            } catch {
                throw IOError(
                    kind: (error as? IOError)?.kind ?? .other,
                    "failed to normalize \(root): \(error)")
            }
        }
        #endif
        return LocalFileSystemPolicyMatcher(policy: policy, context: context)
    }
}

extension LocalFileSystemPolicyMatcher {
    /// Check write access, preserving any failure to normalize the target path.
    public func canWritePath(_ path: PathUri) throws -> Bool {
        try withPath(path) { path in
            policy.canWritePath(path, context: context)
        }
    }

    func resolveAccess(_ path: PathUri) -> FileSystemAccessMode {
        (try? withPath(path) { path in
            policy.resolveAccess(path, context: context)
        }) ?? .deny
    }

    private func withPath<T>(_ path: PathUri, evaluate: (PathUri) -> T) throws -> T {
        #if os(macOS)
        do {
            let normalized = try PathUri(path.toAbsPath().normalizeSystemAliases())
            return evaluate(normalized)
        } catch {
            throw IOError(
                kind: (error as? IOError)?.kind ?? .other,
                "failed to normalize \(path): \(error)")
        }
        #else
        return evaluate(path)
        #endif
    }
}

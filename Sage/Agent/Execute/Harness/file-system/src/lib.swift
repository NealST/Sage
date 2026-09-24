//
//  lib.swift
//  FileSystem
//
//  Port of codex-rs/file-system/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Only `FileSystemSandboxContext` is ported so far; `ExecutorFileSystem`,
//  `environment_accessor.rs` and `find_up.rs` arrive in Phase 2.
//  Codex stores the policy on the executor. On Mac the same context is what
//  apply_patch checks before each read and write.
//

import Foundation

public struct FileSystemSandboxContext: Sendable {
    public var cwd: URL
    public var workspaceRoots: [URL]
    public var userHomeDir: URL?
    public var temporaryDirectories: [URL]
    public var denyProtectedWrites: Bool
    public var followSymlinks: Bool
    /// Full-disk read would skip a platform sandbox. Mac execute never has it.
    public var fullDiskRead: Bool
    public var fullDiskWrite: Bool

    public init(
        cwd: URL,
        workspaceRoots: [URL],
        userHomeDir: URL? = nil,
        temporaryDirectories: [URL] = [],
        denyProtectedWrites: Bool,
        followSymlinks: Bool,
        fullDiskRead: Bool = false,
        fullDiskWrite: Bool = false
    ) {
        self.cwd = cwd
        self.workspaceRoots = workspaceRoots
        self.userHomeDir = userHomeDir
        self.temporaryDirectories = temporaryDirectories
        self.denyProtectedWrites = denyProtectedWrites
        self.followSymlinks = followSymlinks
        self.fullDiskRead = fullDiskRead
        self.fullDiskWrite = fullDiskWrite
    }

    /// Codex `should_read_from_sandbox`: reads need a sandbox unless the
    /// profile already has full-disk read.
    public var shouldReadFromSandbox: Bool { !fullDiskRead }

    /// Codex `should_write_into_sandbox`.
    public var shouldWriteIntoSandbox: Bool { !fullDiskWrite }

    public func assertAllowed(_ url: URL, write: Bool) throws {
        let standardized = url.standardizedFileURL
        if write, denyProtectedWrites, isProtected(standardized) {
            throw FileSystemSandboxError.notPermitted(path: standardized.path, write: true)
        }
        if !followSymlinks, isSymlink(standardized) {
            throw FileSystemSandboxError.notPermitted(path: standardized.path, write: write)
        }
        if write, fullDiskWrite { return }
        if !write, fullDiskRead { return }
        guard isInsideWorkspace(standardized) else {
            throw FileSystemSandboxError.notPermitted(path: standardized.path, write: write)
        }
    }

    public func isProtected(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { component in
            component == ".git" || component == ".sage" || component == ".agents"
        }
    }

    public func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    public func isInsideWorkspace(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let roots = workspaceRoots.map { $0.standardizedFileURL.path }
            + [cwd.standardizedFileURL.path]
            + temporaryDirectories.map { $0.standardizedFileURL.path }
        return roots.contains { root in
            path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }
}

public enum FileSystemSandboxError: Error, Equatable, Sendable {
    case notPermitted(path: String, write: Bool)
}

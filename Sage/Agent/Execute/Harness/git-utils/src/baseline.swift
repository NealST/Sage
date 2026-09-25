//
//  baseline.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/baseline.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Upstream uses `gix` to write trees and diffs. This port shells out to
//  `/usr/bin/git` (`Process`) for init / commit / status / diff so we do
//  not invent a git library.
//

import Foundation

let BASELINE_COMMIT_MESSAGE =
    "Initialize Codex git baseline\n\nCo-authored-by: Codex <noreply@openai.com>"

/// File-level change status between a git baseline and the current directory.
public enum GitBaselineChangeStatus: Equatable, Sendable {
    case added
    case modified
    case deleted

    /// Returns the short git-style status label for this change.
    public var label: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        }
    }
}

/// One changed file between a git baseline and the current directory.
public struct GitBaselineChange: Equatable, Sendable {
    public var status: GitBaselineChangeStatus
    public var path: String

    public init(status: GitBaselineChangeStatus, path: String) {
        self.status = status
        self.path = path
    }
}

/// Structured diff from the latest git baseline reset to the current directory.
public struct GitBaselineDiff: Equatable, Sendable {
    public var changes: [GitBaselineChange]
    public var unifiedDiff: String

    public init(changes: [GitBaselineChange], unifiedDiff: String) {
        self.changes = changes
        self.unifiedDiff = unifiedDiff
    }

    public var hasChanges: Bool { !changes.isEmpty }
}

/// Replaces any existing `.git` metadata in `root` with a fresh one-commit baseline.
///
/// This is intentionally destructive for `root/.git`. It is meant for internal directories where
/// git is used only as a baseline/diff implementation detail, not for user repositories.
public func resetGitRepository(root: String) async throws {
    try await Task.detached {
        try resetGitRepositorySync(root)
    }.value
}

/// Ensures `root` has a usable git baseline repository.
///
/// Existing usable `.git/` metadata is preserved. Missing or unusable metadata is replaced with a
/// fresh one-commit baseline.
public func ensureGitBaselineRepository(root: String) async throws {
    try await Task.detached {
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let gitPath = (root as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir), isDir.boolValue {
            if (try? resolveHead(root)) != nil {
                return
            }
        }
        try resetGitRepositorySync(root)
    }.value
}

/// Returns the diff between the latest baseline reset and the current directory contents.
public func diffSinceLatestInit(root: String) async throws -> GitBaselineDiff {
    try await Task.detached {
        try diffSinceLatestInitSync(root)
    }.value
}

private func resetGitRepositorySync(_ root: String) throws {
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    try removeGitMetadata(root)
    try runGitForStatus(root, ["init", "-q"])
    try runGitForStatus(root, ["-c", "user.name=Codex", "-c", "user.email=noreply@openai.com", "add", "-A"])
    try runGitForStatus(root, [
        "-c", "user.name=Codex",
        "-c", "user.email=noreply@openai.com",
        "commit",
        "--allow-empty",
        "-q",
        "-m", BASELINE_COMMIT_MESSAGE,
    ])
}

private func removeGitMetadata(_ root: String) throws {
    let gitPath = (root as NSString).appendingPathComponent(".git")
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir) else { return }
    if isDir.boolValue {
        try FileManager.default.removeItem(atPath: gitPath)
    } else {
        try FileManager.default.removeItem(atPath: gitPath)
    }
}

private func diffSinceLatestInitSync(_ root: String) throws -> GitBaselineDiff {
    let nameStatus = try runGitForStdoutAllowDirty(root, ["diff", "--name-status", "HEAD"])
    var changes: [GitBaselineChange] = []
    for line in nameStatus.split(whereSeparator: \.isNewline) {
        let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2 else { continue }
        let code = String(parts[0])
        let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
        let status: GitBaselineChangeStatus
        switch code.first {
        case "A": status = .added
        case "M": status = .modified
        case "D": status = .deleted
        default: continue
        }
        changes.append(GitBaselineChange(status: status, path: path))
    }

    let untracked = try runGitForStdout(root, ["ls-files", "--others", "--exclude-standard"])
    for line in untracked.split(whereSeparator: \.isNewline) {
        let path = line.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { continue }
        if !changes.contains(where: { $0.path == path }) {
            changes.append(GitBaselineChange(status: .added, path: path))
        }
    }

    var unified = try runGitForStdoutAllowDirty(root, ["diff", "--no-ext-diff", "HEAD"])
    if !untracked.isEmpty {
        for file in untracked.split(whereSeparator: \.isNewline).map({ String($0) }).filter({ !$0.isEmpty }) {
            if let extra = try? runGitForStdoutAllowDirty(
                root,
                ["diff", "--no-ext-diff", "--no-index", "--", "/dev/null", file]
            ) {
                unified += extra
            }
        }
    }

    changes.sort { $0.path < $1.path }
    return GitBaselineDiff(changes: changes, unifiedDiff: unified)
}

/// `git diff` exits 1 when there is a diff; treat that as success.
private func runGitForStdoutAllowDirty(_ dir: String, _ args: [String]) throws -> String {
    do {
        return try runGitForStdout(dir, args)
    } catch let error as GitToolingError {
        if case .gitCommand(_, let status, _) = error, status == 1 {
            // Re-run and capture stdout even when dirty. `runGitForStdout` throws
            // before returning stdout, so invoke the process directly.
            var argsVec = ["-c", SAFE_BARE_REPOSITORY_CONFIG, "-c", "core.hooksPath=\(DISABLED_HOOKS_PATH)"]
            argsVec.append(contentsOf: args)
            let output = try runGitSync(arguments: argsVec, currentDirectory: dir)
            if output.status == 0 || output.status == 1, let text = utf8String(output.stdout) {
                return text
            }
        }
        throw error
    }
}

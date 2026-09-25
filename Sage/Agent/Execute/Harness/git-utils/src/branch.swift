//
//  branch.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/branch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Git invocations use `/usr/bin/git` via `runGitForStdout`.
//

import Foundation

/// Returns the merge-base commit between `HEAD` and the latest version between local
/// and remote of the provided branch, if both exist.
///
/// The function mirrors `git merge-base HEAD <branch>` but returns `nil` when
/// the repository has no `HEAD` yet or when the branch cannot be resolved.
public func mergeBaseWithHead(repoPath: String, branch: String) throws -> String? {
    try ensureGitRepository(repoPath)
    let repoRoot = try resolveRepositoryRoot(repoPath)
    guard let head = try resolveHead(repoRoot) else {
        return nil
    }
    guard let branchRef = try resolveBranchRef(repoRoot, branch) else {
        return nil
    }
    let preferredRef: String
    if let upstream = try resolveUpstreamIfRemoteAhead(repoRoot, branch) {
        preferredRef = try resolveBranchRef(repoRoot, upstream) ?? branchRef
    } else {
        preferredRef = branchRef
    }
    return try runGitForStdout(repoRoot, ["merge-base", head, preferredRef])
}

private func resolveBranchRef(_ repoRoot: String, _ branch: String) throws -> String? {
    do {
        return try runGitForStdout(repoRoot, ["rev-parse", "--verify", branch])
    } catch let error as GitToolingError {
        if case .gitCommand = error {
            return nil
        }
        throw error
    }
}

private func resolveUpstreamIfRemoteAhead(_ repoRoot: String, _ branch: String) throws -> String? {
    let upstream: String
    do {
        let name = try runGitForStdout(
            repoRoot,
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "\(branch)@{upstream}"]
        )
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        upstream = trimmed
    } catch let error as GitToolingError {
        if case .gitCommand = error { return nil }
        throw error
    }

    let counts: String
    do {
        counts = try runGitForStdout(
            repoRoot,
            ["rev-list", "--left-right", "--count", "\(branch)...\(upstream)"]
        )
    } catch let error as GitToolingError {
        if case .gitCommand = error { return nil }
        throw error
    }

    let parts = counts.split(whereSeparator: \.isWhitespace)
    let right = Int64(parts.dropFirst().first.map(String.init) ?? "0") ?? 0
    return right > 0 ? upstream : nil
}

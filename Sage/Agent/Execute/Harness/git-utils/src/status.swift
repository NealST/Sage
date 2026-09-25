//
//  status.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/status.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Rust coalesces in-flight status queries with `WeakShared` futures. This
//  port uses an actor that shares one `Task` per `(git, repoRoot)` key.
//

import CodexUtils
import Foundation

private struct GitStatusKey: Hashable, Sendable {
    var git: String
    var repoRoot: String
}

private actor GitStatusShare {
    var runs: [GitStatusKey: Task<Bool?, Never>] = [:]

    func share(key: GitStatusKey, run: @escaping @Sendable () async -> Bool?) async -> Bool? {
        if let existing = runs[key] {
            return await existing.value
        }
        let task = Task { await run() }
        runs[key] = task
        let result = await task.value
        runs[key] = nil
        return result
    }
}

private let gitStatusShare = GitStatusShare()

public func getHasChangesInRepo(cwd: String, repoRoot: String) async -> Bool? {
    let git = "/usr/bin/git"
    let key = await gitStatusKey(git: git, repoRoot: repoRoot)
    return await gitStatusShare.share(key: key) {
        let fsmonitor = await detectLocalFsmonitorOverride(git: git, cwd: cwd)
        guard let output = await runGitCommandWithTimeoutFrom(
            git: git,
            args: ["status", "--porcelain"],
            cwd: cwd,
            fsmonitor: fsmonitor
        ) else {
            return nil
        }
        return output.success ? !output.stdout.isEmpty : nil
    }
}

private func gitStatusKey(git: String, repoRoot: String) async -> GitStatusKey {
    let canonical = (try? AbsolutePathBuf.fromAbsolutePath(repoRoot).canonicalize().asPath) ?? repoRoot
    return GitStatusKey(git: git, repoRoot: canonical)
}

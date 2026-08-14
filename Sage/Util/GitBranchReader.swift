//
//  GitBranchReader.swift
//  Sage
//
//  Lightweight git metadata for project chrome (branch list / checkout).
//

import Foundation

enum GitBranchReader {
    /// Returns the current branch name, or a short detached HEAD SHA. `nil` if not a git repo.
    static func currentBranch(inProjectRoot root: URL) -> String? {
        guard let headURL = gitHEADFile(in: root),
              let raw = try? String(contentsOf: headURL, encoding: .utf8)
        else {
            return nil
        }
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: ") {
            let ref = String(head.dropFirst(5))
            if let name = ref.split(separator: "/").last {
                return String(name)
            }
            return ref
        }
        // Detached HEAD — show short SHA.
        return head.count > 7 ? String(head.prefix(7)) : head
    }

    /// Local branch names (no remotes), current first when known.
    static func localBranches(inProjectRoot root: URL) -> [String] {
        guard isGitRepository(root) else { return [] }
        let result = runGit(["branch", "--format=%(refname:short)"], in: root)
        guard result.exitCode == 0 else { return [] }
        let names = result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let current = currentBranch(inProjectRoot: root) else { return names }
        return names.sorted { lhs, rhs in
            if lhs == current { return true }
            if rhs == current { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    /// Checks out a local branch. Returns `nil` on success, or an error message.
    static func checkout(branch: String, inProjectRoot root: URL) -> String? {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Branch name is empty." }
        guard isGitRepository(root) else { return "Not a git repository." }
        let result = runGit(["checkout", trimmed], in: root)
        if result.exitCode == 0 { return nil }
        let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Could not switch to “\(trimmed)”." : detail
    }

    /// Recent commits for the History tab (`hash\tsubject`), newest first.
    static func recentCommits(inProjectRoot root: URL, limit: Int = 50) -> [GitCommitSummary] {
        guard isGitRepository(root) else { return [] }
        let capped = max(1, min(limit, 100))
        let result = runGit(
            ["log", "-n", "\(capped)", "--format=%h\t%s"],
            in: root
        )
        guard result.exitCode == 0 else { return [] }
        return result.output
            .split(separator: "\n")
            .compactMap { line -> GitCommitSummary? in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let hash = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !hash.isEmpty else { return nil }
                return GitCommitSummary(shortHash: hash, subject: subject)
            }
    }

    static func isGitRepository(_ root: URL) -> Bool {
        gitHEADFile(in: root) != nil
    }

    // MARK: - Internals

    private static func runGit(_ arguments: [String], in root: URL) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func gitHEADFile(in root: URL) -> URL? {
        let gitPath = root.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath.path, isDirectory: &isDirectory)
        else {
            return nil
        }
        if isDirectory.boolValue {
            return gitPath.appendingPathComponent("HEAD")
        }
        // `.git` file for worktrees: `gitdir: /path/to/gitdir`
        guard let text = try? String(contentsOf: gitPath, encoding: .utf8)
        else {
            return nil
        }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("gitdir:") {
                let dir = trimmed.dropFirst("gitdir:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let gitDirURL: URL
                if dir.hasPrefix("/") {
                    gitDirURL = URL(fileURLWithPath: dir)
                } else {
                    gitDirURL = root.appendingPathComponent(dir).standardizedFileURL
                }
                return gitDirURL.appendingPathComponent("HEAD")
            }
        }
        return nil
    }
}

struct GitCommitSummary: Identifiable, Equatable, Sendable {
    var id: String { shortHash }
    let shortHash: String
    let subject: String
}

//
//  GitBranchReader.swift
//  Sage
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

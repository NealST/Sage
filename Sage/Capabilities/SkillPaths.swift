//
//  SkillPaths.swift
//  Sage
//
//  Single source of truth for on-disk skill directory layout.
//

import Foundation

enum SkillPathsError: LocalizedError {
    case projectRootRequired
    case directoryCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectRootRequired:
            return "A project folder is required to save a project skill."
        case .directoryCreationFailed(let path):
            return "Could not create skill directory at: \(path)"
        }
    }
}

enum SkillPaths {
    /// Sage-managed global skills: `~/Library/Application Support/Sage/Skills`.
    static func userSkillsDirectory(createIfNeeded: Bool = false) -> URL {
        AppSupportPaths.userSkillsDirectory(createIfNeeded: createIfNeeded)
    }

    /// Shared user agents skills: `~/.agents/skills` (read-only for Sage writes).
    static func userAgentsSkillsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills", isDirectory: true)
    }

    /// Project-owned Sage skills: `<root>/.sage/skills`.
    static func projectSageSkillsDirectory(root: URL, createIfNeeded: Bool = false) -> URL {
        let dir = root.appendingPathComponent(".sage/skills", isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Project agents skills: `<root>/.agents/skills`.
    static func projectAgentsSkillsDirectory(root: URL) -> URL {
        root.appendingPathComponent(".agents/skills", isDirectory: true)
    }

    /// Roots scanned for global skills (App Support first, then ~/.agents/skills if present).
    static func globalScanRoots() -> [URL] {
        var roots = [userSkillsDirectory(createIfNeeded: true)]
        let agents = userAgentsSkillsDirectory()
        if FileManager.default.fileExists(atPath: agents.path) {
            roots.append(agents)
        }
        return roots
    }

    /// Roots scanned for project skills (existing folders only).
    static func projectScanRoots(root: URL) -> [URL] {
        [
            projectAgentsSkillsDirectory(root: root),
            projectSageSkillsDirectory(root: root),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Writable root for creating a new skill.
    static func writableDirectory(for scope: SkillScope, projectRoot: URL?) throws -> URL {
        switch scope {
        case .global:
            return userSkillsDirectory(createIfNeeded: true)
        case .project:
            guard let projectRoot else {
                throw SkillPathsError.projectRootRequired
            }
            let dir = projectSageSkillsDirectory(root: projectRoot, createIfNeeded: true)
            guard FileManager.default.fileExists(atPath: dir.path) else {
                throw SkillPathsError.directoryCreationFailed(dir.path)
            }
            return dir
        }
    }
}

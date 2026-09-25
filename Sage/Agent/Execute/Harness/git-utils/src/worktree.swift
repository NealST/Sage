//
//  worktree.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/worktree.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolves repository identity and sibling checkouts from validated Git
//  metadata without executing Git. PathBuf maps to String.
//

import CodexUtils
import Foundation

/// The stable on-disk identity shared by a repository and its linked worktrees.
public struct RepositoryIdentity: Equatable, Hashable, Sendable {
    /// Canonical shared Git administrative directory.
    public var commonDir: AbsolutePathBuf
    /// Directory within the current checkout, preserved across linked worktrees.
    public var relativeCwd: String
    /// Canonical root of the repository's primary checkout.
    public var primaryRoot: AbsolutePathBuf

    public init(commonDir: AbsolutePathBuf, relativeCwd: String, primaryRoot: AbsolutePathBuf) {
        self.commonDir = commonDir
        self.relativeCwd = relativeCwd
        self.primaryRoot = primaryRoot
    }
}

private func canonicalizeNative(_ path: String) -> String? {
    (try? AbsolutePathBuf.fromAbsolutePath(path).canonicalize())?.asPath
}

/// Identifies a checkout without executing Git or trusting unchecked administrative links.
public func repositoryIdentity(cwd: String) -> RepositoryIdentity? {
    guard let canonicalCwd = canonicalizeNative(cwd) else { return nil }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: canonicalCwd, isDirectory: &isDir), isDir.boolValue else {
        return nil
    }
    guard let checkoutRoot = getGitRepoRoot(canonicalCwd).flatMap(canonicalizeNative) else {
        return nil
    }
    guard let relativeCwd = pathStripPrefix(canonicalCwd, prefix: checkoutRoot) else {
        return nil
    }
    let gitEntry = (checkoutRoot as NSString).appendingPathComponent(".git")
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: gitEntry),
          let type = attrs[.type] as? FileAttributeType
    else {
        return nil
    }
    if type == .typeSymbolicLink {
        return nil
    }

    let commonDir: String
    if type == .typeDirectory {
        guard let canonical = canonicalizeNative(gitEntry) else { return nil }
        commonDir = canonical
    } else if type == .typeRegular {
        guard let gitDir = readGitPath(gitEntry, relativeTo: checkoutRoot, prefix: "gitdir:") else {
            return nil
        }
        var gitDirIsDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir, isDirectory: &gitDirIsDir), gitDirIsDir.boolValue else {
            return nil
        }
        guard let common = readGitPath(
            (gitDir as NSString).appendingPathComponent("commondir"),
            relativeTo: gitDir,
            prefix: ""
        ) else {
            return nil
        }
        var commonIsDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: common, isDirectory: &commonIsDir), commonIsDir.boolValue else {
            return nil
        }
        guard let registeredRoot = canonicalizeNative((common as NSString).appendingPathComponent("worktrees")),
              (gitDir as NSString).deletingLastPathComponent == registeredRoot
        else {
            return nil
        }
        guard let backlink = readGitPath(
            (gitDir as NSString).appendingPathComponent("gitdir"),
            relativeTo: gitDir,
            prefix: ""
        ), backlink == canonicalizeNative(gitEntry) else {
            return nil
        }
        commonDir = common
    } else {
        return nil
    }

    let primaryRoot = (commonDir as NSString).deletingLastPathComponent
    let primaryGitEntry = (primaryRoot as NSString).appendingPathComponent(".git")
    guard let primaryAttrs = try? FileManager.default.attributesOfItem(atPath: primaryGitEntry),
          let primaryType = primaryAttrs[.type] as? FileAttributeType,
          primaryType == .typeDirectory,
          canonicalizeNative(primaryGitEntry) == commonDir
    else {
        return nil
    }

    guard let commonAbs = try? AbsolutePathBuf.fromAbsolutePathChecked(commonDir),
          let primaryAbs = try? AbsolutePathBuf.fromAbsolutePathChecked(primaryRoot)
    else {
        return nil
    }
    return RepositoryIdentity(commonDir: commonAbs, relativeCwd: relativeCwd, primaryRoot: primaryAbs)
}

/// Returns corresponding existing directories in the current, primary, and linked checkouts.
public func linkedWorktreeCwds(cwd: String) -> [String]? {
    guard let identity = repositoryIdentity(cwd: cwd),
          let currentCwd = canonicalizeNative(cwd)
    else {
        return nil
    }
    var result = [cwd]
    var seen: Set<String> = [cwd]
    if seen.insert(currentCwd).inserted {
        result.append(currentCwd)
    }
    appendLinkedCwd(&result, seen: &seen, checkoutRoot: identity.primaryRoot.asPath, identity: identity)

    let worktrees = identity.commonDir.join("worktrees").asPath
    guard FileManager.default.fileExists(atPath: worktrees) else {
        return result
    }
    guard let canonicalWorktrees = canonicalizeNative(worktrees),
          let entries = try? FileManager.default.contentsOfDirectory(atPath: canonicalWorktrees)
    else {
        return nil
    }
    let registered = entries.sorted().compactMap { name -> String? in
        let path = (canonicalWorktrees as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return path
    }
    for entry in registered {
        guard let gitDir = canonicalizeNative(entry),
              (gitDir as NSString).deletingLastPathComponent == canonicalWorktrees,
              let gitFile = readGitPath(
                (gitDir as NSString).appendingPathComponent("gitdir"),
                relativeTo: gitDir,
                prefix: ""
              ),
              (gitFile as NSString).lastPathComponent == ".git"
        else {
            continue
        }
        let checkoutRoot = (gitFile as NSString).deletingLastPathComponent
        appendLinkedCwd(&result, seen: &seen, checkoutRoot: checkoutRoot, identity: identity)
    }
    return result
}

private func appendLinkedCwd(
    _ result: inout [String],
    seen: inout Set<String>,
    checkoutRoot: String,
    identity: RepositoryIdentity
) {
    guard let checkoutRoot = canonicalizeNative(checkoutRoot) else { return }
    let joined = identity.relativeCwd.isEmpty
        ? checkoutRoot
        : (checkoutRoot as NSString).appendingPathComponent(identity.relativeCwd)
    guard let candidate = canonicalizeNative(joined) else { return }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue,
          candidate == checkoutRoot || candidate.hasPrefix(checkoutRoot.hasSuffix("/") ? checkoutRoot : checkoutRoot + "/")
    else {
        return
    }
    guard let candidateIdentity = repositoryIdentity(cwd: candidate),
          candidateIdentity.commonDir == identity.commonDir,
          candidateIdentity.relativeCwd == identity.relativeCwd,
          seen.insert(candidate).inserted
    else {
        return
    }
    result.append(candidate)
}

private func readGitPath(_ path: String, relativeTo: String, prefix: String) -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          (attrs[.type] as? FileAttributeType) == .typeRegular,
          let contents = try? String(contentsOfFile: path, encoding: .utf8)
    else {
        return nil
    }
    let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    let value: String
    if prefix.isEmpty {
        value = trimmed
    } else if let stripped = trimmed.stripPrefix(prefix) {
        value = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        return nil
    }
    if value.isEmpty || value.contains("\n") || value.contains("\r") {
        return nil
    }
    return canonicalizeNative((relativeTo as NSString).appendingPathComponent(value))
}

private func pathStripPrefix(_ path: String, prefix: String) -> String? {
    if path == prefix { return "" }
    let boundary = prefix.hasSuffix("/") ? prefix : prefix + "/"
    guard path.hasPrefix(boundary) else { return nil }
    return String(path.dropFirst(boundary.count))
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

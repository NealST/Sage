//
//  trust.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/trust.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolve repository trust roots through `ExecutorFileSystem`. Async
//  `async let` stands in for `tokio::join!`. Byte trimming uses UTF-8
//  `trimmingCharacters` when the payload is valid UTF-8, otherwise ASCII
//  whitespace on the raw bytes.
//

import CodexUtils
import FileSystem
import Foundation

let MAX_GIT_METADATA_FILE_BYTES: UInt64 = 64 * 1024

/// Resolve the path that should be used for trust checks. Similar to
/// `getGitRepoRoot`, but resolves to the root of the main
/// repository. Handles worktrees via filesystem inspection without invoking
/// the `git` executable.
public func resolveRootGitProjectForTrust(
    fs: any ExecutorFileSystem,
    cwd: AbsolutePathBuf
) async -> AbsolutePathBuf? {
    guard let root = await resolveRoot(fs: fs, cwd: .native(cwd)) else { return nil }
    if case .native(let path) = root {
        return path
    }
    return nil
}

/// Resolve the main repository's trust root using the executor's path convention.
public func resolveRootGitProjectUriForTrust(
    fs: any ExecutorFileSystem,
    cwd: PathUri
) async -> PathUri? {
    await resolveRoot(fs: fs, cwd: .uri(cwd))?.uri
}

private enum TrustPath {
    case native(AbsolutePathBuf)
    case uri(PathUri)

    var uri: PathUri {
        switch self {
        case .native(let path): return PathUri.fromAbsPath(path)
        case .uri(let path): return path
        }
    }

    func parent() -> TrustPath? {
        switch self {
        case .native(let path): return path.parent.map(TrustPath.native)
        case .uri(let path): return path.parent().map(TrustPath.uri)
        }
    }

    func join(_ component: String) -> TrustPath? {
        switch self {
        case .native(let path): return .native(path.join(component))
        case .uri(let path): return (try? path.join(component)).map(TrustPath.uri)
        }
    }
}

private func resolveRoot(fs: any ExecutorFileSystem, cwd: TrustPath) async -> TrustPath? {
    let cwdUri = cwd.uri
    let base: TrustPath
    if let metadata = try? await fs.getMetadata(cwdUri, options: .default, sandbox: nil),
       metadata.isDirectory
    {
        base = cwd
    } else {
        guard let parent = cwd.parent() else { return nil }
        base = parent
    }

    var search = base
    let repoRoot: TrustPath
    while true {
        let candidate: TrustPath
        switch search {
        case .native(let path):
            guard let found = try? await findNearestNativeAncestorWithMarkers(
                fileSystem: fs,
                start: path,
                markers: [".git"],
                errorPolicy: .ignore,
                sandbox: nil
            ) else {
                return nil
            }
            candidate = .native(found)
        case .uri(let path):
            guard let found = try? await findNearestAncestorWithMarkers(
                fileSystem: fs,
                start: path,
                markers: [".git"],
                errorPolicy: .ignore,
                sandbox: nil
            ) else {
                return nil
            }
            candidate = .uri(found)
        }
        guard let dotGit = candidate.join(".git"),
              let metadata = try? await fs.getMetadata(dotGit.uri, options: .default, sandbox: nil)
        else {
            return nil
        }
        guard let head = dotGit.join("HEAD") else { return nil }
        let hasHead = (try? await fs.getMetadata(head.uri, options: .default, sandbox: nil)) != nil
        if !metadata.isDirectory || hasHead {
            repoRoot = candidate
            break
        }
        guard let parent = candidate.parent() else { return nil }
        search = parent
    }

    guard let dotGitUri = repoRoot.join(".git")?.uri,
          let dotGitMetadata = try? await fs.getMetadata(dotGitUri, options: .default, sandbox: nil)
    else {
        return nil
    }
    if dotGitMetadata.isDirectory {
        return repoRoot
    }
    if !dotGitMetadata.isFile
        || dotGitMetadata.isSymlink
        || dotGitMetadata.size > MAX_GIT_METADATA_FILE_BYTES
    {
        return nil
    }

    guard let gitDirUri = await readGitdirFile(fs: fs, path: dotGitUri) else { return nil }
    let gitDirPath: TrustPath
    switch repoRoot {
    case .native:
        guard let abs = try? gitDirUri.toAbsPath() else { return nil }
        gitDirPath = .native(abs)
    case .uri:
        gitDirPath = .uri(gitDirUri)
    }
    guard let gitDirMetadata = try? await fs.getMetadata(gitDirUri, options: .default, sandbox: nil),
          gitDirMetadata.isDirectory, !gitDirMetadata.isSymlink
    else {
        return nil
    }

    guard let canonicalGitDirUri = try? await fs.canonicalize(gitDirUri, sandbox: nil),
          let worktreesDirUri = canonicalGitDirUri.parent(),
          worktreesDirUri.basename() == "worktrees",
          let commonDirUri = worktreesDirUri.parent(),
          let worktreeGitdirUri = try? canonicalGitDirUri.join("gitdir"),
          let commondirUri = try? canonicalGitDirUri.join("commondir")
    else {
        return nil
    }

    async let worktreeGitdirBytes = readMetadataFile(fs: fs, path: worktreeGitdirUri)
    async let commondirBytes = readMetadataFile(fs: fs, path: commondirUri)
    guard let worktreeGitdirRaw = await worktreeGitdirBytes,
          let commondirRaw = await commondirBytes
    else {
        return nil
    }
    let worktreeGitdir = trimASCIIBytes(worktreeGitdirRaw)
    if worktreeGitdir.isEmpty { return nil }
    guard let worktreeDotGitUri = try? canonicalGitDirUri.joinNativeBytes(worktreeGitdir),
          worktreeDotGitUri.basename() == ".git"
    else {
        return nil
    }
    let commondir = trimASCIIBytes(commondirRaw)
    if commondir.isEmpty { return nil }
    guard let linkedCommonDirUri = try? canonicalGitDirUri.joinNativeBytes(commondir),
          let registeredCheckoutUri = worktreeDotGitUri.parent()
    else {
        return nil
    }
    let checkoutUri = repoRoot.uri

    async let registeredCheckout = fs.canonicalize(registeredCheckoutUri, sandbox: nil)
    async let checkout = fs.canonicalize(checkoutUri, sandbox: nil)
    async let linkedCommonDir = fs.canonicalize(linkedCommonDirUri, sandbox: nil)
    guard let registered = try? await registeredCheckout,
          let checked = try? await checkout,
          let linked = try? await linkedCommonDir
    else {
        return nil
    }
    if registered.toUrl() != checked.toUrl() || linked.toUrl() != commonDirUri.toUrl() {
        return nil
    }

    guard let commonDir = gitDirPath.parent()?.parent(),
          let mainRoot = commonDir.parent(),
          let mainDotGitUri = mainRoot.join(".git")?.uri,
          let mainMetadata = try? await fs.getMetadata(mainDotGitUri, options: .default, sandbox: nil)
    else {
        return nil
    }
    let mainGitDirUri: PathUri
    if mainMetadata.isDirectory {
        mainGitDirUri = mainDotGitUri
    } else {
        guard let resolved = await readGitdirFile(fs: fs, path: mainDotGitUri) else { return nil }
        mainGitDirUri = resolved
    }
    guard let canonicalMain = try? await fs.canonicalize(mainGitDirUri, sandbox: nil),
          canonicalMain.toUrl() == commonDirUri.toUrl()
    else {
        return nil
    }
    return mainRoot
}

private func readGitdirFile(fs: any ExecutorFileSystem, path: PathUri) async -> PathUri? {
    guard let contents = await readMetadataFile(fs: fs, path: path) else { return nil }
    let trimmed = trimASCIIBytes(contents)
    let prefix = Array("gitdir:".utf8)
    guard trimmed.starts(with: prefix) else { return nil }
    let target = trimASCIIBytes(Array(trimmed.dropFirst(prefix.count)))
    if target.isEmpty { return nil }
    return try? path.parent()?.joinNativeBytes(target)
}

private func readMetadataFile(fs: any ExecutorFileSystem, path: PathUri) async -> [UInt8]? {
    guard let metadata = try? await fs.getMetadata(path, options: .default, sandbox: nil),
          metadata.isFile, !metadata.isSymlink, metadata.size <= MAX_GIT_METADATA_FILE_BYTES
    else {
        return nil
    }
    guard let bytes = try? await fs.readFile(path, options: .default, sandbox: nil) else {
        return nil
    }
    return bytes.count <= MAX_GIT_METADATA_FILE_BYTES ? bytes : nil
}

private func trimASCIIBytes(_ bytes: [UInt8]) -> [UInt8] {
    var start = 0
    var end = bytes.count
    func isSpace(_ b: UInt8) -> Bool {
        b == 9 || b == 10 || b == 13 || b == 32
    }
    while start < end && isSpace(bytes[start]) { start += 1 }
    while end > start && isSpace(bytes[end - 1]) { end -= 1 }
    return Array(bytes[start..<end])
}

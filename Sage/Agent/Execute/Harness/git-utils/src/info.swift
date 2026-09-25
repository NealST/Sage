//
//  info.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/info.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Git invocations use `/usr/bin/git` via `Process`. `GitInfo` is the
//  git-utils type; CodexProtocol also exports `GitInfo` — callers that
//  import both modules must qualify.
//

import CodexProtocol
import Foundation

/// Timeout for git commands to prevent freezing on large repositories
let GIT_COMMAND_TIMEOUT: TimeInterval = 5

/// Return `true` if the project folder specified by the `Config` is inside a
/// Git repository.
///
/// The check walks up the directory hierarchy looking for a `.git` file or
/// directory (note `.git` can be a file that contains a `gitdir` entry). This
/// approach does **not** require the `git` binary and is therefore fairly
/// lightweight.
///
/// Note that this does **not** detect *work-trees* created with
/// `git worktree add` where the checkout lives outside the main repository
/// directory.
public func getGitRepoRoot(_ baseDir: String) -> String? {
    var isDir: ObjCBool = false
    let base: String
    if FileManager.default.fileExists(atPath: baseDir, isDirectory: &isDir), isDir.boolValue {
        base = baseDir
    } else {
        let parent = (baseDir as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != baseDir else {
            return nil
        }
        base = parent
    }
    return findAncestorGitEntry(base)?.repoRoot
}

public struct GitInfo: Codable, Equatable, Sendable {
    /// Current commit hash (SHA)
    public var commitHash: GitSha?
    /// Current branch name
    public var branch: String?
    /// Repository URL (if available from remote)
    public var repositoryUrl: SanitizedGitUrl?

    enum CodingKeys: String, CodingKey {
        case commitHash = "commit_hash"
        case branch
        case repositoryUrl = "repository_url"
    }

    public init(
        commitHash: GitSha? = nil,
        branch: String? = nil,
        repositoryUrl: SanitizedGitUrl? = nil
    ) {
        self.commitHash = commitHash
        self.branch = branch
        self.repositoryUrl = repositoryUrl
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(commitHash, forKey: .commitHash)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encodeIfPresent(repositoryUrl, forKey: .repositoryUrl)
    }
}

public struct GitDiffToRemote: Codable, Equatable, Sendable {
    public var sha: GitSha
    public var diff: String

    public init(sha: GitSha, diff: String) {
        self.sha = sha
        self.diff = diff
    }
}

/// Collect git repository information from the given working directory using command-line git.
/// Returns nil if no git repository is found or if git operations fail.
public func collectGitInfo(cwd: String) async -> GitInfo? {
    guard let isGitRepo = await runGitCommandWithTimeout(["rev-parse", "--git-dir"], cwd: cwd),
          isGitRepo.success
    else {
        return nil
    }

    async let commitResult = runGitCommandWithTimeout(["rev-parse", "HEAD"], cwd: cwd)
    async let branchResult = runGitCommandWithTimeout(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)
    async let urlResult = runGitCommandWithTimeout(["remote", "get-url", "origin"], cwd: cwd)
    let (commit, branch, url) = await (commitResult, branchResult, urlResult)

    var gitInfo = GitInfo()

    if let commit, commit.success, let hash = utf8String(commit.stdout) {
        gitInfo.commitHash = GitSha(hash.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    if let branch, branch.success, let name = utf8String(branch.stdout) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != "HEAD" {
            gitInfo.branch = trimmed
        }
    }

    if let url, url.success, let raw = utf8String(url.stdout) {
        gitInfo.repositoryUrl = try? SanitizedGitUrl(parsing: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return gitInfo
}

/// Collect fetch remotes in a multi-root-friendly format: {"origin": "https://..."}.
public func getGitRemoteUrls(cwd: String) async -> [String: SanitizedGitUrl]? {
    guard let isGitRepo = await runGitCommandWithTimeout(["rev-parse", "--git-dir"], cwd: cwd),
          isGitRepo.success
    else {
        return nil
    }
    return await getGitRemoteUrlsAssumeGitRepo(cwd: cwd)
}

/// Collect fetch remotes without checking whether `cwd` is in a git repo.
public func getGitRemoteUrlsAssumeGitRepo(cwd: String) async -> [String: SanitizedGitUrl]? {
    guard let output = await runGitCommandWithTimeout(["remote", "-v"], cwd: cwd),
          output.success,
          let stdout = utf8String(output.stdout)
    else {
        return nil
    }
    return parseGitRemoteUrls(stdout)
}

/// Return the current HEAD commit hash without checking whether `cwd` is in a git repo.
public func getHeadCommitHash(cwd: String) async -> GitSha? {
    guard let output = await runGitCommandWithTimeout(["rev-parse", "HEAD"], cwd: cwd),
          output.success,
          let stdout = utf8String(output.stdout)
    else {
        return nil
    }
    let hash = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return hash.isEmpty ? nil : GitSha(hash)
}

public func canonicalizeGitRemoteUrl(_ url: String) -> String? {
    let trimmed = trimGitSuffix(url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix(while: { $0 == "/" }))
    if trimmed.isEmpty {
        return nil
    }

    if let range = trimmed.range(of: "://") {
        return canonicalizeGitUrlLikeRemote(
            scheme: String(trimmed[..<range.lowerBound]),
            rest: String(trimmed[range.upperBound...])
        )
    }

    if let scp = parseScpLikeRemote(trimmed) {
        return canonicalizeGitRemoteHostPath(hostPart: scp.host, path: scp.path, defaultPort: nil)
    }

    guard let slash = trimmed.firstIndex(of: "/") else { return nil }
    return canonicalizeGitRemoteHostPath(
        hostPart: String(trimmed[..<slash]),
        path: String(trimmed[trimmed.index(after: slash)...]),
        defaultPort: nil
    )
}

private func canonicalizeGitUrlLikeRemote(scheme: String, rest: String) -> String? {
    let defaultPort: String?
    switch scheme {
    case "git": defaultPort = "9418"
    case "http": defaultPort = "80"
    case "https": defaultPort = "443"
    case "ssh": defaultPort = "22"
    default: return nil
    }

    var rest = rest
    if let suffixIndex = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) {
        rest = String(rest[..<suffixIndex])
    }
    guard let slash = rest.firstIndex(of: "/") else { return nil }
    return canonicalizeGitRemoteHostPath(
        hostPart: String(rest[..<slash]),
        path: String(rest[rest.index(after: slash)...]),
        defaultPort: defaultPort
    )
}

private func parseScpLikeRemote(_ remote: String) -> (host: String, path: String)? {
    if let slash = remote.firstIndex(of: "/"),
       remote.firstIndex(of: ":").map({ slash < $0 }) ?? true
    {
        return nil
    }
    guard let colon = remote.firstIndex(of: ":") else { return nil }
    let hostPart = String(remote[..<colon])
    let path = String(remote[remote.index(after: colon)...])
    if hostPart.isEmpty || path.isEmpty {
        return nil
    }
    return (hostPart, path)
}

private func canonicalizeGitRemoteHostPath(
    hostPart: String,
    path: String,
    defaultPort: String?
) -> String? {
    let hostRaw = hostPart.rsplitOnce("@").map(\.tail) ?? hostPart
    let host = normalizeRemoteHost(
        hostRaw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingSuffix(while: { $0 == "/" }),
        defaultPort: defaultPort
    )
    if host.isEmpty {
        return nil
    }

    let trimmedPath = trimGitSuffix(path.trimmingCharacters(in: .whitespacesAndNewlines).trimming(while: { $0 == "/" }))
    let components = trimmedPath.split(separator: "/").filter { !$0.isEmpty }.map(String.init)
    guard components.count >= 2 else { return nil }
    let owner = components[0]
    let repo = components[1]
    if owner == "." || owner == ".." || repo == "." || repo == ".." {
        return nil
    }
    let joined = components.joined(separator: "/")
    if host == "github.com" {
        return "\(host)/\(joined.lowercased())"
    }
    return "\(host)/\(joined)"
}

private func normalizeRemoteHost(_ host: String, defaultPort: String?) -> String {
    let host = host.lowercased()
    if let defaultPort,
       let colon = host.lastIndex(of: ":"),
       String(host[host.index(after: colon)...]) == defaultPort
    {
        return String(host[..<colon])
    }
    return host
}

private func trimGitSuffix(_ value: String) -> String {
    if value.hasSuffix(".git") {
        return String(value.dropLast(4))
    }
    return value
}

func parseGitRemoteUrls(_ stdout: String) -> [String: SanitizedGitUrl]? {
    var remotes: [String: SanitizedGitUrl] = [:]
    for line in stdout.split(whereSeparator: \.isNewline) {
        let line = String(line)
        guard let fetchLine = line.hasSuffix(" (fetch)") ? String(line.dropLast(" (fetch)".count)) : nil else {
            continue
        }
        let split = fetchLine.splitOnce("\t") ?? fetchLine.splitOnce(" ")
        guard let split else { continue }
        let url = split.tail.trimmingPrefix(while: { $0.isWhitespace })
        if !url.isEmpty, let sanitized = try? SanitizedGitUrl(parsing: String(url)) {
            remotes[split.head] = sanitized
        }
    }
    return remotes.isEmpty ? nil : remotes
}

/// A minimal commit summary entry used for pickers (subject + timestamp + sha).
public struct CommitLogEntry: Codable, Equatable, Sendable {
    public var sha: String
    /// Unix timestamp (seconds since epoch) of the commit time (committer time).
    public var timestamp: Int64
    /// Single-line subject of the commit message.
    public var subject: String

    public init(sha: String, timestamp: Int64, subject: String) {
        self.sha = sha
        self.timestamp = timestamp
        self.subject = subject
    }
}

/// Return the last `limit` commits reachable from HEAD for the current branch.
public func recentCommits(cwd: String, limit: Int) async -> [CommitLogEntry] {
    guard let out = await runGitCommandWithTimeout(["rev-parse", "--git-dir"], cwd: cwd),
          out.success
    else {
        return []
    }

    let fmt = "%H%x1f%ct%x1f%s"
    var args = ["log"]
    if limit > 0 {
        args.append(contentsOf: ["-n", String(limit)])
    }
    args.append("--pretty=format:\(fmt)")
    guard let logOut = await runGitCommandWithTimeout(args, cwd: cwd), logOut.success else {
        return []
    }

    let text = utf8Lossy(logOut.stdout)
    var entries: [CommitLogEntry] = []
    for line in text.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: "\u{001f}", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { continue }
        let sha = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let tsS = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if sha.isEmpty || tsS.isEmpty { continue }
        entries.append(CommitLogEntry(sha: sha, timestamp: Int64(tsS) ?? 0, subject: subject))
    }
    return entries
}

/// Returns the closest git sha to HEAD that is on a remote as well as the diff to that sha.
public func gitDiffToRemote(cwd: String) async -> GitDiffToRemote? {
    guard getGitRepoRoot(cwd) != nil else { return nil }
    guard let remotes = await getGitRemotes(cwd: cwd),
          let branches = await branchAncestry(cwd: cwd),
          let baseSha = await findClosestSha(cwd: cwd, branches: branches, remotes: remotes),
          let diff = await diffAgainstSha(cwd: cwd, sha: baseSha)
    else {
        return nil
    }
    return GitDiffToRemote(sha: baseSha, diff: diff)
}

func runGitCommandWithTimeout(_ args: [String], cwd: String) async -> GitProcessOutput? {
    await runGitCommandWithTimeoutFrom(
        git: "/usr/bin/git",
        args: args,
        cwd: cwd,
        fsmonitor: .disabled
    )
}

struct LocalFsmonitorProbeRunner: FsmonitorProbeRunner {
    var git: String
    var cwd: String

    mutating func runProbe(_ args: [String]) async -> [UInt8]? {
        var command = ["-c", SAFE_BARE_REPOSITORY_CONFIG]
        command.append(contentsOf: args)
        guard let output = await runGitCommandWithTimeoutOutput(
            arguments: command,
            currentDirectory: cwd,
            timeout: GIT_COMMAND_TIMEOUT
        ), output.success else {
            return nil
        }
        return Array(output.stdout)
    }
}

func detectLocalFsmonitorOverride(git: String, cwd: String) async -> FsmonitorOverride {
    var runner = LocalFsmonitorProbeRunner(git: git, cwd: cwd)
    return await detectFsmonitorOverride(&runner)
}

func runGitCommandWithTimeoutFrom(
    git: String,
    args: [String],
    cwd: String,
    fsmonitor: FsmonitorOverride
) async -> GitProcessOutput? {
    _ = git
    var arguments = [
        "-c", SAFE_BARE_REPOSITORY_CONFIG,
        "-c", "core.hooksPath=\(DISABLED_HOOKS_PATH)",
        "-c", fsmonitor.gitConfigArg,
    ]
    arguments.append(contentsOf: args)
    return await runGitCommandWithTimeoutOutput(
        arguments: arguments,
        currentDirectory: cwd,
        extraEnvironment: ["GIT_OPTIONAL_LOCKS": "0"],
        timeout: GIT_COMMAND_TIMEOUT
    )
}

private func getGitRemotes(cwd: String) async -> [String]? {
    guard let output = await runGitCommandWithTimeout(["remote"], cwd: cwd), output.success,
          let stdout = utf8String(output.stdout)
    else {
        return nil
    }
    var remotes = stdout.split(whereSeparator: \.isNewline).map { String($0) }
    if let pos = remotes.firstIndex(of: "origin") {
        let origin = remotes.remove(at: pos)
        remotes.insert(origin, at: 0)
    }
    return remotes
}

private func getDefaultBranch(cwd: String) async -> String? {
    let remotes = await getGitRemotes(cwd: cwd) ?? []
    for remote in remotes {
        if let symrefOutput = await runGitCommandWithTimeout(
            ["symbolic-ref", "--quiet", "refs/remotes/\(remote)/HEAD"],
            cwd: cwd
        ), symrefOutput.success, let sym = utf8String(symrefOutput.stdout) {
            let trimmed = sym.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = trimmed.rsplitOnce("/")?.tail, !name.isEmpty {
                return name
            }
        }
        if let showOutput = await runGitCommandWithTimeout(["remote", "show", remote], cwd: cwd),
           showOutput.success, let text = utf8String(showOutput.stdout)
        {
            for line in text.split(whereSeparator: \.isNewline) {
                let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let rest = line.stripPrefix("HEAD branch:") {
                    let name = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        return name
                    }
                }
            }
        }
    }
    return await getDefaultBranchLocal(cwd: cwd)
}

public func defaultBranchName(cwd: String) async -> String? {
    await getDefaultBranch(cwd: cwd)
}

private func getDefaultBranchLocal(cwd: String) async -> String? {
    for candidate in ["main", "master"] {
        if let verify = await runGitCommandWithTimeout(
            ["rev-parse", "--verify", "--quiet", "refs/heads/\(candidate)"],
            cwd: cwd
        ), verify.success {
            return candidate
        }
    }
    return nil
}

private func branchAncestry(cwd: String) async -> [String]? {
    let currentBranch: String? = await {
        guard let output = await runGitCommandWithTimeout(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd),
              output.success, let text = utf8String(output.stdout)
        else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "HEAD" ? nil : trimmed
    }()
    let defaultBranch = await getDefaultBranch(cwd: cwd)

    var ancestry: [String] = []
    var seen = Set<String>()
    if let currentBranch {
        seen.insert(currentBranch)
        ancestry.append(currentBranch)
    }
    if let defaultBranch, !seen.contains(defaultBranch) {
        seen.insert(defaultBranch)
        ancestry.append(defaultBranch)
    }

    let remotes = await getGitRemotes(cwd: cwd) ?? []
    for remote in remotes {
        if let output = await runGitCommandWithTimeout(
            ["for-each-ref", "--format=%(refname:short)", "--contains=HEAD", "refs/remotes/\(remote)"],
            cwd: cwd
        ), output.success, let text = utf8String(output.stdout) {
            for line in text.split(whereSeparator: \.isNewline) {
                let short = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let stripped = short.stripPrefix("\(remote)/"), !stripped.isEmpty, !seen.contains(stripped) {
                    seen.insert(stripped)
                    ancestry.append(stripped)
                }
            }
        }
    }
    return ancestry
}

private func branchRemoteAndDistance(
    cwd: String,
    branch: String,
    remotes: [String]
) async -> (GitSha?, Int)? {
    var foundRemoteSha: GitSha?
    var foundRemoteRef: String?
    for remote in remotes {
        let remoteRef = "refs/remotes/\(remote)/\(branch)"
        guard let verifyOutput = await runGitCommandWithTimeout(
            ["rev-parse", "--verify", "--quiet", remoteRef],
            cwd: cwd
        ) else {
            return nil
        }
        if !verifyOutput.success { continue }
        guard let sha = utf8String(verifyOutput.stdout) else { return nil }
        foundRemoteSha = GitSha(sha.trimmingCharacters(in: .whitespacesAndNewlines))
        foundRemoteRef = remoteRef
        break
    }

    let countOutput: GitProcessOutput
    if let localCount = await runGitCommandWithTimeout(
        ["rev-list", "--count", "\(branch)..HEAD"],
        cwd: cwd
    ) {
        if localCount.success {
            countOutput = localCount
        } else if let remoteRef = foundRemoteRef {
            guard let remoteCount = await runGitCommandWithTimeout(
                ["rev-list", "--count", "\(remoteRef)..HEAD"],
                cwd: cwd
            ) else {
                return nil
            }
            countOutput = remoteCount
        } else {
            return nil
        }
    } else if let remoteRef = foundRemoteRef {
        guard let remoteCount = await runGitCommandWithTimeout(
            ["rev-list", "--count", "\(remoteRef)..HEAD"],
            cwd: cwd
        ) else {
            return nil
        }
        countOutput = remoteCount
    } else {
        return nil
    }

    guard countOutput.success, let distanceStr = utf8String(countOutput.stdout),
          let distance = Int(distanceStr.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
        return nil
    }
    return (foundRemoteSha, distance)
}

private func findClosestSha(cwd: String, branches: [String], remotes: [String]) async -> GitSha? {
    var closest: (GitSha, Int)?
    for branch in branches {
        guard let (maybeRemoteSha, distance) = await branchRemoteAndDistance(
            cwd: cwd,
            branch: branch,
            remotes: remotes
        ) else {
            continue
        }
        guard let remoteSha = maybeRemoteSha else { continue }
        if closest == nil || distance < closest!.1 {
            closest = (remoteSha, distance)
        }
    }
    return closest?.0
}

private func diffAgainstSha(cwd: String, sha: GitSha) async -> String? {
    let git = "/usr/bin/git"
    let fsmonitor = await detectLocalFsmonitorOverride(git: git, cwd: cwd)
    guard let output = await runGitCommandWithTimeoutFrom(
        git: git,
        args: ["diff", "--no-textconv", "--no-ext-diff", sha.value],
        cwd: cwd,
        fsmonitor: fsmonitor
    ) else {
        return nil
    }
    let exitOk = output.status == 0 || output.status == 1
    guard exitOk, var diff = utf8String(output.stdout) else { return nil }

    if let untrackedOutput = await runGitCommandWithTimeoutFrom(
        git: git,
        args: ["ls-files", "--others", "--exclude-standard"],
        cwd: cwd,
        fsmonitor: fsmonitor
    ), untrackedOutput.success, let text = utf8String(untrackedOutput.stdout) {
        let untracked = text.split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.isEmpty }
        if !untracked.isEmpty {
            await withTaskGroup(of: GitProcessOutput?.self) { group in
                for file in untracked {
                    group.addTask {
                        await runGitCommandWithTimeoutFrom(
                            git: git,
                            args: [
                                "diff",
                                "--no-textconv",
                                "--no-ext-diff",
                                "--binary",
                                "--no-index",
                                "--",
                                "/dev/null",
                                file,
                            ],
                            cwd: cwd,
                            fsmonitor: fsmonitor
                        )
                    }
                }
                for await extra in group {
                    if let extra, extra.status == 0 || extra.status == 1,
                       let s = utf8String(extra.stdout)
                    {
                        diff.append(s)
                    }
                }
            }
        }
    }
    return diff
}

private func findAncestorGitEntry(_ baseDir: String) -> (repoRoot: String, dotGit: String)? {
    var dir = (baseDir as NSString).standardizingPath
    let fm = FileManager.default
    while true {
        let dotGit = (dir as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
            if !isDir.boolValue || fm.fileExists(atPath: (dotGit as NSString).appendingPathComponent("HEAD")) {
                return (dir, dotGit)
            }
        }
        let parent = (dir as NSString).deletingLastPathComponent
        if parent == dir || parent.isEmpty {
            break
        }
        dir = parent
    }
    return nil
}

/// Returns a list of local git branches.
/// Includes the default branch at the beginning of the list, if it exists.
public func localGitBranches(cwd: String) async -> [String] {
    var branches: [String] = []
    if let out = await runGitCommandWithTimeout(
        ["for-each-ref", "--format=%(refname:short)", "refs/heads"],
        cwd: cwd
    ), out.success {
        branches = utf8Lossy(out.stdout)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    branches.sort()
    if let base = await getDefaultBranchLocal(cwd: cwd),
       let pos = branches.firstIndex(of: base)
    {
        let baseBranch = branches.remove(at: pos)
        branches.insert(baseBranch, at: 0)
    }
    return branches
}

/// Returns the current checked out branch name.
public func currentBranchName(cwd: String) async -> String? {
    guard let out = await runGitCommandWithTimeout(["branch", "--show-current"], cwd: cwd),
          out.success, let text = utf8String(out.stdout)
    else {
        return nil
    }
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    func trimmingSuffix(while predicate: (Character) -> Bool) -> String {
        var result = self
        while let last = result.last, predicate(last) {
            result.removeLast()
        }
        return result
    }

    func trimming(while predicate: (Character) -> Bool) -> String {
        String(trimmingPrefix(while: predicate)).trimmingSuffix(while: predicate)
    }

    func splitOnce(_ separator: String) -> (head: String, tail: String)? {
        guard let range = range(of: separator) else { return nil }
        return (String(self[..<range.lowerBound]), String(self[range.upperBound...]))
    }

    func rsplitOnce(_ separator: String) -> (head: String, tail: String)? {
        guard let range = range(of: separator, options: .backwards) else { return nil }
        return (String(self[..<range.lowerBound]), String(self[range.upperBound...]))
    }
}

private extension Substring {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

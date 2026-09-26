//
//  helpers.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/helpers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Path helpers and id parsing. Owned-path discovery walks FileManager;
//  `ownedRolloutPathsFromIndex` uses CodexRollout's reference index when
//  callers already scanned. State-DB name/section lookup is omitted
//  until GRDB lands.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import CodexState
import Foundation

func scopedRolloutPath(
    root: String,
    rolloutPath: String,
    rootName: String
) throws -> String {
    guard let canonicalRoot = canonicalizePath(root) else {
        throw ThreadStoreError.internal(
            "failed to resolve \(rootName) directory `\(root)`")
    }
    guard let canonicalRollout = canonicalizePath(rolloutPath) else {
        throw ThreadStoreError.invalidRequest(
            "rollout path `\(rolloutPath)` must be in \(rootName) directory")
    }
    if pathIsInside(canonicalRollout, root: canonicalRoot) {
        return canonicalRollout
    }
    throw ThreadStoreError.invalidRequest(
        "rollout path `\(rolloutPath)` must be in \(rootName) directory")
}

func rolloutPathIsArchived(codexHome: String, path: String) -> Bool {
    let archivedRoot = (codexHome as NSString).appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
    if pathIsInside(path, root: archivedRoot) { return true }
    return path.split(separator: "/").contains { $0 == ARCHIVED_SESSIONS_SUBDIR }
}

func ownedRolloutPaths(store: LocalThreadStore, threadId: ThreadId) -> [String] {
    var paths: [String] = []
    for subdir in [SESSIONS_SUBDIR, ARCHIVED_SESSIONS_SUBDIR] {
        let root = (store.config.codexHome as NSString).appendingPathComponent(subdir)
        collectOwnedRolloutPaths(root: root, threadId: threadId, into: &paths)
    }
    return paths
}

func ownedRolloutPathsFromIndex(_ index: RolloutReferenceIndex, threadId: ThreadId) -> [String] {
    index.rolloutsForThread(threadId).map { _, path in path }
}

func validatedRolloutFileName(rolloutPath: String, displayPath: String) throws -> String {
    let fileName = (rolloutPath as NSString).lastPathComponent
    guard !fileName.isEmpty, fileName != "/", fileName != "." else {
        throw ThreadStoreError.invalidRequest(
            "rollout path `\(displayPath)` missing file name")
    }
    if rolloutIdFromPath(rolloutPath) != nil {
        return fileName
    }
    throw ThreadStoreError.invalidRequest(
        "rollout path `\(displayPath)` has an invalid filename")
}

func touchModifiedTime(_ path: String) throws {
    try FileManager.default.setAttributes(
        [.modificationDate: Date()],
        ofItemAtPath: path
    )
}

func restoreRolloutMoves(_ moves: [(String, String)]) throws {
    for (source, destination) in moves.reversed() {
        try FileManager.default.moveItem(atPath: destination, toPath: source)
    }
}

func storedThreadFromRolloutItem(
    _ item: ThreadItem,
    archived: Bool,
    defaultProvider: String
) -> StoredThread? {
    let threadId = item.threadId ?? threadIdFromRolloutPath(item.path)
    guard let threadId else { return nil }
    let createdAt = item.createdAt.flatMap(parseSessionTimestamp) ?? Date()
    let updatedAt = item.updatedAt.flatMap(parseSessionTimestamp) ?? createdAt
    let recencyAt = item.recencyAt.flatMap(parseSessionTimestamp) ?? updatedAt
    let archivedAt = archived ? updatedAt : nil
    let gitInfo = gitInfoFromParts(
        sha: item.gitSha,
        branch: item.gitBranch,
        originUrl: item.gitOriginUrl
    )
    let source = item.source ?? .unknown
    let preview = item.preview ?? item.firstUserMessage ?? ""
    let rolloutPath = plainRolloutPath(item.path)
    return StoredThread(
        originator: item.originator,
        threadId: threadId,
        extraConfig: nil,
        rolloutPath: rolloutPath,
        forkedFromId: nil,
        parentThreadId: item.parentThreadId,
        preview: preview,
        name: isGuardianReviewSource(source) ? GUARDIAN_THREAD_TITLE : nil,
        modelProvider: {
            if let provider = item.modelProvider, !provider.isEmpty { return provider }
            return defaultProvider
        }(),
        model: item.model,
        reasoningEffort: item.reasoningEffort,
        createdAt: createdAt,
        updatedAt: updatedAt,
        recencyAt: recencyAt,
        archivedAt: archivedAt,
        section: item.section.map(storedSection(from:)),
        sectionPosition: nil,
        sectionEnteredAt: nil,
        projectId: item.projectId,
        daybreakEnabled: item.daybreakEnabled,
        cwd: item.cwd ?? "",
        cliVersion: item.cliVersion ?? "",
        source: source,
        historyMode: item.historyMode,
        threadSource: nil,
        agentNickname: item.agentNickname,
        agentRole: item.agentRole,
        agentPath: nil,
        gitInfo: gitInfo,
        approvalMode: .onRequest,
        permissionProfile: .readOnly(),
        tokenUsage: nil,
        firstUserMessage: item.firstUserMessage,
        history: nil
    )
}

func permissionProfileFromMetadataValue(_ value: String, cwd: String) -> PermissionProfile {
    if let data = value.data(using: .utf8),
       let profile = try? JSONDecoder().decode(PermissionProfile.self, from: data)
    {
        return profile
    }
    if let policy = parseLegacySandboxPolicy(value) {
        return .fromLegacySandboxPolicyForCwd(policy, cwd: cwd)
    }
    return .readOnly()
}

func permissionProfileToMetadataValue(_ permissionProfile: PermissionProfile) -> String {
    guard let data = try? JSONEncoder().encode(permissionProfile),
          let value = String(data: data, encoding: .utf8)
    else {
        return ""
    }
    return value
}

func sqliteThreadName(_ metadata: ThreadMetadata) -> String? {
    metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty
}

func hasGuardianDefaultTitle(_ metadata: ThreadMetadata) -> Bool {
    metadata.title.trimmingCharacters(in: .whitespacesAndNewlines) == GUARDIAN_THREAD_TITLE
        && sessionSourceFromMetadataString(metadata.source).map(isGuardianReviewSource) == true
}

func distinctThreadMetadataTitle(_ metadata: ThreadMetadata) -> String? {
    let title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty { return nil }
    if metadata.firstUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines) == title {
        return nil
    }
    return title
}

func setThreadName(_ thread: inout StoredThread, name: String) {
    if thread.historyMode == .paginated || thread.preview.trimmingCharacters(in: .whitespacesAndNewlines) != name.trimmingCharacters(in: .whitespacesAndNewlines) {
        thread.name = name
    }
}

func gitInfoFromParts(
    sha: String?,
    branch: String?,
    originUrl: SanitizedGitUrl?
) -> GitInfo? {
    if sha == nil && branch == nil && originUrl == nil { return nil }
    return GitInfo(
        commitHash: sha.map(GitSha.init),
        branch: branch,
        repositoryUrl: originUrl
    )
}

func threadIdFromRolloutPath(_ path: String) -> ThreadId? {
    var fileName = (path as NSString).lastPathComponent
    if fileName.hasSuffix(".zst") {
        fileName = String(fileName.dropLast(4))
    }
    guard fileName.hasSuffix(".jsonl") else { return nil }
    let stem = String(fileName.dropLast(6))
    guard stem.count >= 37 else { return nil }
    let uuidStart = stem.count - 36
    let prefix = stem.prefix(uuidStart)
    guard prefix.hasSuffix("-") else { return nil }
    return try? ThreadId.fromString(String(stem.suffix(36)))
}

private func storedSection(from section: CodexState.ThreadSection) -> ThreadSection {
    ThreadSection(
        id: section.id,
        name: section.name,
        appearance: section.appearance.map {
            ThreadSectionAppearance(icon: $0.icon, color: $0.color)
        }
    )
}

private func parseLegacySandboxPolicy(_ value: String) -> SandboxPolicy? {
    if let data = value.data(using: .utf8),
       let policy = try? JSONDecoder().decode(SandboxPolicy.self, from: data)
    {
        return policy
    }
    if let data = try? JSONEncoder().encode(value),
       let policy = try? JSONDecoder().decode(SandboxPolicy.self, from: data)
    {
        return policy
    }
    switch value {
    case "danger-full-access":
        return .dangerFullAccess
    case "read-only":
        return .newReadOnlyPolicy()
    case "workspace-write":
        return .newWorkspaceWritePolicy()
    case "external-sandbox":
        return .externalSandbox(networkAccess: .restricted)
    default:
        return nil
    }
}

private func canonicalizePath(_ path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
        return url.resolvingSymlinksInPath().path
    }
    return url.standardizedFileURL.path
}

private func pathIsInside(_ path: String, root: String) -> Bool {
    let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
    return path == normalizedRoot || path.hasPrefix(normalizedRoot + "/")
}

private func collectOwnedRolloutPaths(root: String, threadId: ThreadId, into paths: inout [String]) {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: root) else { return }
    let needle = threadId.description
    while let relative = enumerator.nextObject() as? String {
        let path = (root as NSString).appendingPathComponent(relative)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            continue
        }
        if threadIdFromRolloutPath(path) == threadId || relative.contains(needle) {
            paths.append(path)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

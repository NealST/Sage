//
//  publish.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/publish.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Journal / staged-path / rewrite / sync helpers use FileManager. zstd
//  compress/decompress throw until the compression worker lands (same as
//  CodexRollout compression).
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

let MIGRATION_JOURNAL_DIRECTORY = "rollout-migrations"

public func migrationJournalPath(codexHome: String, threadId: ThreadId) -> String {
    ((codexHome as NSString)
        .appendingPathComponent(MIGRATION_JOURNAL_DIRECTORY) as NSString)
        .appendingPathComponent("\(threadId).pending")
}

public func pendingMigrationThreadIds(codexHome: String) throws -> Set<ThreadId> {
    let directory = (codexHome as NSString).appendingPathComponent(MIGRATION_JOURNAL_DIRECTORY)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        return []
    }
    let entries: [String]
    do {
        entries = try FileManager.default.contentsOfDirectory(atPath: directory)
    } catch {
        throw migrationError(error)
    }
    var threadIds = Set<ThreadId>()
    for name in entries {
        let path = (directory as NSString).appendingPathComponent(name)
        var isFileDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFileDirectory),
              !isFileDirectory.boolValue
        else {
            continue
        }
        guard name.hasSuffix(".pending") else { continue }
        let stem = String(name.dropLast(".pending".count))
        if let threadId = try? ThreadId.fromString(stem) {
            threadIds.insert(threadId)
        }
    }
    return threadIds
}

public func stagedRolloutPath(_ rolloutPath: String) throws -> String {
    try stagedPath(rolloutPath, suffix: "paginated")
}

func decompressedStagedRolloutPath(_ rolloutPath: String) throws -> String {
    try stagedPath(rolloutPath, suffix: "decompressed")
}

func compressedStagedRolloutPath(_ rolloutPath: String) throws -> String {
    try stagedPath(rolloutPath, suffix: "paginated.zst")
}

private func stagedPath(_ rolloutPath: String, suffix: String) throws -> String {
    let filename = (rolloutPath as NSString).lastPathComponent
    guard !filename.isEmpty, filename != "/", filename != "." else {
        throw migrationError("rollout path has no valid filename")
    }
    let parent = (rolloutPath as NSString).deletingLastPathComponent
    return (parent as NSString).appendingPathComponent(".\(filename).\(suffix).tmp")
}

func decompressRolloutToPath(compressedPath: String, plainPath: String) throws {
    _ = (compressedPath, plainPath)
    throw ThreadStoreError.unsupported(operation: "rollout_zstd")
}

func compressRolloutToPath(
    plainPath: String,
    compressedPath: String,
    permissions: [FileAttributeKey: Any],
    modifiedAt: Date?
) throws {
    _ = (plainPath, compressedPath, permissions, modifiedAt)
    throw ThreadStoreError.unsupported(operation: "rollout_zstd")
}

func rewrittenStagedRolloutPath(_ stagedPath: String) throws -> String {
    let filename = (stagedPath as NSString).lastPathComponent
    guard !filename.isEmpty, filename != "/", filename != "." else {
        throw migrationError("staged rollout path has no valid filename")
    }
    let parent = (stagedPath as NSString).deletingLastPathComponent
    return (parent as NSString).appendingPathComponent("\(filename).head.tmp")
}

func rewriteSubagentHistoryBoundary(stagedPath: String, boundary: UInt64) throws {
    let rewrittenPath = try rewrittenStagedRolloutPath(stagedPath)
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try FileManager.default.attributesOfItem(atPath: stagedPath)
    } catch {
        throw migrationError(error)
    }
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: stagedPath))
    } catch {
        throw migrationError(error)
    }
    guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else {
        throw migrationError("staged rollout head is not session metadata")
    }
    var head: RolloutLine
    do {
        head = try parseRolloutLineBytes(data[..<newline])
    } catch {
        throw migrationError(error)
    }
    guard case .sessionMeta(var sessionMeta) = head.item else {
        throw migrationError("staged rollout head is not session metadata")
    }
    sessionMeta.meta.subagentHistoryStartOrdinal = boundary
    head.item = .sessionMeta(sessionMeta)
    let encoded: Data
    do {
        encoded = Data(try encodeRolloutLineString(head).utf8) + Data([UInt8(ascii: "\n")])
    } catch {
        throw migrationError(error)
    }
    var output = encoded
    if newline + 1 < data.count {
        output.append(data[(newline + 1)...])
    }
    do {
        try output.write(to: URL(fileURLWithPath: rewrittenPath), options: .atomic)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: rewrittenPath)
        try FileManager.default.removeItem(atPath: stagedPath)
        try FileManager.default.moveItem(atPath: rewrittenPath, toPath: stagedPath)
    } catch {
        throw migrationError(error)
    }
}

func removeFileIfPresent(_ path: String) throws {
    if FileManager.default.fileExists(atPath: path) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw migrationError(error)
        }
    }
}

func writeMigrationJournal(_ path: String) throws {
    let parent = (path as NSString).deletingLastPathComponent
    guard !parent.isEmpty else {
        throw migrationError("rollout migration journal has no parent directory")
    }
    let parentAlreadyExists = FileManager.default.fileExists(atPath: parent)
    do {
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )
        if !parentAlreadyExists {
            try syncParentDirectory(parent)
        }
        FileManager.default.createFile(atPath: path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
        try syncParentDirectory(path)
    } catch {
        throw migrationError(error)
    }
}

func syncParentDirectory(_ path: String) throws {
    let parent = (path as NSString).deletingLastPathComponent
    guard !parent.isEmpty else {
        throw migrationError("rollout path has no parent directory")
    }
    let handle: FileHandle
    do {
        handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: parent))
        try handle.synchronize()
        try handle.close()
    } catch {
        throw migrationError(error)
    }
}

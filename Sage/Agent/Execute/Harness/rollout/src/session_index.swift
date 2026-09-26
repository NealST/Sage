//
//  session_index.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/session_index.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Append-only `session_index.jsonl`. Newest entry wins. Reverse scan uses
//  ReverseJsonlScanner. StateRuntime lookup is omitted (pass nil).
//

import CodexProtocol
import Foundation
import os

public let SESSION_INDEX_FILE = "session_index.jsonl"

private let sessionIndexLock = OSAllocatedUnfairLock(initialState: ())

public struct SessionIndexEntry: Codable, Equatable, Sendable {
    public var id: ThreadId
    public var threadName: String
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }

    public init(id: ThreadId, threadName: String, updatedAt: String) {
        self.id = id
        self.threadName = threadName
        self.updatedAt = updatedAt
    }
}

/// Append a thread name update to the session index.
public func appendThreadName(codexHome: String, threadId: ThreadId, name: String) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let entry = SessionIndexEntry(
        id: threadId,
        threadName: name,
        updatedAt: formatter.string(from: Date())
    )
    try appendSessionIndexEntry(codexHome: codexHome, entry: entry)
}

public func appendSessionIndexEntry(codexHome: String, entry: SessionIndexEntry) throws {
    try sessionIndexLock.withLock { _ in
        let path = sessionIndexPath(codexHome)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONEncoder().encode(entry)
        data.append(UInt8(ascii: "\n"))
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}

/// Remove all recorded names for a thread from the session index.
public func removeThreadNameEntries(codexHome: String, threadId: ThreadId) throws {
    try sessionIndexLock.withLock { _ in
        let path = sessionIndexPath(codexHome)
        guard FileManager.default.fileExists(atPath: path) else { return }
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        var remaining = ""
        var removed = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                remaining += "\n"
                continue
            }
            if let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: Data(trimmed.utf8)),
               entry.id == threadId
            {
                removed = true
                continue
            }
            remaining += String(line) + "\n"
        }
        guard removed else { return }
        let temp = path + ".tmp"
        try remaining.write(toFile: temp, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(
            URL(fileURLWithPath: path),
            withItemAt: URL(fileURLWithPath: temp)
        )
    }
}

public func findThreadNameById(codexHome: String, threadId: ThreadId) throws -> String? {
    try scanIndexFromEnd(codexHome: codexHome) { $0.id == threadId }?.threadName
}

public func findThreadNamesByIds(codexHome: String, threadIds: Set<ThreadId>) throws -> [ThreadId: String] {
    let path = sessionIndexPath(codexHome)
    guard !threadIds.isEmpty, FileManager.default.fileExists(atPath: path) else { return [:] }
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    var names: [ThreadId: String] = [:]
    for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: Data(trimmed.utf8))
        else { continue }
        let name = entry.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, threadIds.contains(entry.id) {
            names[entry.id] = name
        }
    }
    return names
}

public func findThreadMetaByNameStr(
    codexHome: String,
    name: String,
    stateDbCtx: Any? = nil
) throws -> (path: String, meta: SessionMetaLine)? {
    try findThreadMetaCandidatesByNameStr(
        codexHome: codexHome,
        name: name,
        stateDbCtx: stateDbCtx
    ).first
}

public func findThreadMetaCandidatesByNameStr(
    codexHome: String,
    name: String,
    stateDbCtx: Any? = nil,
    allowedSources: [SessionSource] = [],
    allowedModelProviders: [String] = []
) throws -> [(path: String, meta: SessionMetaLine)] {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
    var seen = Set<ThreadId>()
    var ids: [ThreadId] = []
    try scanIndexFromEndForEach(codexHome: codexHome) { entry in
        if seen.insert(entry.id).inserted, entry.threadName == name {
            ids.append(entry.id)
        }
        return nil
    }
    var candidates: [(Date, String, SessionMetaLine)] = []
    for threadId in ids {
        guard let path = try findThreadPathByIdStr(
            codexHome: codexHome, idStr: threadId.description, stateDbCtx: stateDbCtx),
              let sessionMeta = try? readSessionMetaLine(path: path)
        else { continue }
        if !allowedSources.isEmpty, !allowedSources.contains(sessionMeta.meta.source) { continue }
        if let provider = sessionMeta.meta.modelProvider,
           !allowedModelProviders.isEmpty,
           !allowedModelProviders.contains(provider)
        {
            continue
        }
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        candidates.append((modified, path, sessionMeta))
    }
    candidates.sort { $0.0 > $1.0 }
    return candidates.map { ($0.1, $0.2) }
}

func sessionIndexPath(_ codexHome: String) -> String {
    (codexHome as NSString).appendingPathComponent(SESSION_INDEX_FILE)
}

private func scanIndexFromEnd(
    codexHome: String,
    predicate: (SessionIndexEntry) -> Bool
) throws -> SessionIndexEntry? {
    try scanIndexFromEndForEach(codexHome: codexHome) { entry in
        predicate(entry) ? entry : nil
    }
}

@discardableResult
private func scanIndexFromEndForEach(
    codexHome: String,
    visit: (SessionIndexEntry) throws -> SessionIndexEntry?
) throws -> SessionIndexEntry? {
    let path = sessionIndexPath(codexHome)
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let scanner = try ReverseJsonlScanner(handle)
    while let outcome = try scanner.scanNext() as ScanOutcome<SessionIndexEntry>? {
        if case .parsed(let entry) = outcome, let hit = try visit(entry) {
            return hit
        }
    }
    return nil
}

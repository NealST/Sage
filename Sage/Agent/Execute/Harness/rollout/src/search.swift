//
//  search.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/search.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Ripgrep is optional (`rg` on PATH). Empty or invalid rg output falls
//  through to a FileManager `.jsonl` scan. Compressed `.jsonl.zst` search
//  is skipped until zstd lands.
//

import CodexHistory
import CodexProtocol
import Foundation

private let matchContextBeforeChars = 48
private let matchContextAfterChars = 96

/// Search matches keyed by the canonical `.jsonl` path for each rollout.
public typealias RolloutSearchMatches = [String: String?]

public func searchRolloutPaths(
    rgCommand: String = "rg",
    codexHome: String,
    archived: Bool,
    searchTerm: String
) throws -> Set<String> {
    Set(try searchRolloutMatches(
        rgCommand: rgCommand,
        codexHome: codexHome,
        archived: archived,
        searchTerm: searchTerm
    ).keys)
}

public func searchRolloutMatches(
    rgCommand: String = "rg",
    codexHome: String,
    archived: Bool,
    searchTerm: String
) throws -> RolloutSearchMatches {
    let root = (codexHome as NSString).appendingPathComponent(
        archived ? ARCHIVED_SESSIONS_SUBDIR : SESSIONS_SUBDIR)
    let jsonSearchTerm = jsonEscapedSearchTerm(searchTerm)
    if let plain = try ripgrepRolloutPaths(rgCommand: rgCommand, root: root, searchTerm: jsonSearchTerm),
       !plain.isEmpty
    {
        var matches: RolloutSearchMatches = [:]
        for path in plain { matches[path] = nil }
        return matches
    }
    return try scanRolloutMatches(root: root, jsonSearchTerm: jsonSearchTerm, searchTerm: searchTerm)
}

public func firstRolloutContentMatchSnippet(path: String, searchTerm: String) throws -> String? {
    var reader = try openRolloutLineReader(path: path)
    let jsonNeedle = jsonEscapedSearchTerm(searchTerm).lowercased()
    let needle = searchTerm.lowercased()
    while let line = reader.nextLine() {
        if line.lowercased().contains(jsonNeedle),
           let snippet = contentMatchSnippet(jsonlLine: line, searchTerm: needle)
        {
            return snippet
        }
    }
    return nil
}

private func ripgrepRolloutPaths(
    rgCommand: String,
    root: String,
    searchTerm: String
) throws -> Set<String>? {
    guard FileManager.default.fileExists(atPath: root) else { return [] }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        rgCommand, "-l", "--fixed-strings", "--ignore-case", "--no-ignore",
        "--glob", "*.jsonl", "--", searchTerm, root,
    ]
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        return nil
    }
    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    var matches = Set<String>()
    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
        let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (raw as NSString).isAbsolutePath
            ? raw : (root as NSString).appendingPathComponent(raw)
        guard path.hasSuffix(".jsonl"), FileManager.default.fileExists(atPath: path) else {
            continue
        }
        matches.insert(path)
    }
    return matches.isEmpty ? nil : matches
}

private func scanRolloutMatches(
    root: String,
    jsonSearchTerm: String,
    searchTerm: String
) throws -> RolloutSearchMatches {
    var matches: RolloutSearchMatches = [:]
    var dirs = [root]
    let jsonNeedle = jsonSearchTerm.lowercased()
    while let dir = dirs.popLast() {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for name in entries {
            let path = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                dirs.append(path)
                continue
            }
            guard let rollout = RolloutFile.fromPath(path) else { continue }
            if rollout.isCompressed { continue }
            if let snippet = try? firstRolloutContentMatchSnippet(path: path, searchTerm: searchTerm) {
                matches[path] = snippet
            } else if let text = try? String(contentsOfFile: path, encoding: .utf8),
                      text.lowercased().contains(jsonNeedle)
            {
                matches[path] = nil
            }
        }
    }
    return matches
}

private func jsonEscapedSearchTerm(_ searchTerm: String) -> String {
    let encoded = (try? JSONEncoder().encode(searchTerm)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    guard encoded.count >= 2 else { return searchTerm }
    return String(encoded.dropFirst().dropLast())
}

private func contentMatchSnippet(jsonlLine: String, searchTerm: String) -> String? {
    guard let rolloutLine = try? parseRolloutLine(jsonlLine.trimmingCharacters(in: .whitespacesAndNewlines)),
          let text = conversationTextFromItem(rolloutLine.item)
    else { return nil }
    return excerptAroundMatch(text, searchTerm: searchTerm)
}

private func conversationTextFromItem(_ item: RolloutItem) -> String? {
    switch item {
    case .eventMsg(.userMessage(let user)):
        let text = stripUserMessagePrefix(user.message)
        return text.isEmpty ? nil : text
    case .eventMsg(.agentMessage(let agent)):
        let text = agent.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    case .responseItem(let envelope):
        guard case .message(_, let role, let content, _, _) = envelope.item,
              role == "user" || role == "assistant"
        else { return nil }
        let text = content.compactMap(contentItemText).joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    default:
        return nil
    }
}

private func contentItemText(_ item: ContentItem) -> String? {
    switch item {
    case .inputText(let text), .outputText(let text): return text
    default: return nil
    }
}

private func excerptAroundMatch(_ text: String, searchTerm: String) -> String? {
    let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard let range = normalized.range(of: searchTerm, options: .caseInsensitive) else { return nil }
    let start = charStartBefore(normalized, byteIndex: range.lowerBound, charsBefore: matchContextBeforeChars)
    let end = charEndAfter(normalized, byteIndex: range.upperBound, charsAfter: matchContextAfterChars)
    let excerpt = normalized[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    if excerpt.isEmpty { return nil }
    var snippet = ""
    if start > normalized.startIndex { snippet += "... " }
    snippet += excerpt
    if end < normalized.endIndex { snippet += " ..." }
    return snippet
}

private func charStartBefore(_ text: String, byteIndex: String.Index, charsBefore: Int) -> String.Index {
    var index = byteIndex
    var remaining = charsBefore
    while remaining > 0, index > text.startIndex {
        index = text.index(before: index)
        remaining -= 1
    }
    return index
}

private func charEndAfter(_ text: String, byteIndex: String.Index, charsAfter: Int) -> String.Index {
    var index = byteIndex
    var remaining = charsAfter
    while remaining > 0, index < text.endIndex {
        index = text.index(after: index)
        remaining -= 1
    }
    return index
}

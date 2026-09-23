//
//  parser.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Parses & validates a patch into hunks. Does not apply them to disk.
//

import Foundation

public let BEGIN_PATCH_MARKER = "*** Begin Patch"
let END_PATCH_MARKER = "*** End Patch"
let ADD_FILE_MARKER = "*** Add File: "
let DELETE_FILE_MARKER = "*** Delete File: "
let UPDATE_FILE_MARKER = "*** Update File: "
let MOVE_TO_MARKER = "*** Move to: "
let EOF_MARKER = "*** End of File"
let CHANGE_CONTEXT_MARKER = "@@ "
let EMPTY_CHANGE_CONTEXT_MARKER = "@@"

/// Codex keeps this false so gpt-4.1 heredoc wrappers still parse.
let PARSE_IN_STRICT_MODE = false

public enum ParseError: Error, Equatable, LocalizedError {
    case invalidPatch(String)
    case invalidHunk(message: String, lineNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPatch(let message):
            return "invalid patch: \(message)"
        case .invalidHunk(let message, let lineNumber):
            return "invalid hunk at line \(lineNumber), \(message)"
        }
    }
}

public enum Hunk: Equatable {
    case addFile(path: String, contents: String)
    case deleteFile(path: String)
    case updateFile(path: String, movePath: String?, chunks: [UpdateFileChunk])

    func resolvePath(cwd: URL) -> URL {
        ApplyPatchPaths.resolve(path(), cwd: cwd)
    }

    public func resolveSourcePath(cwd: URL) -> URL {
        switch self {
        case .updateFile(let path, _, _):
            return ApplyPatchPaths.resolve(path, cwd: cwd)
        case .addFile, .deleteFile:
            return resolvePath(cwd: cwd)
        }
    }

    /// Path shown in summaries. Update-with-move uses the destination.
    public func path() -> String {
        switch self {
        case .addFile(let path, _):
            return path
        case .deleteFile(let path):
            return path
        case .updateFile(let path, let movePath, _):
            return movePath ?? path
        }
    }

    func sourcePath() -> String {
        switch self {
        case .addFile(let path, _), .deleteFile(let path), .updateFile(let path, _, _):
            return path
        }
    }
}

public struct UpdateFileChunk: Equatable {
    public var changeContext: String?
    public var oldLines: [String]
    public var newLines: [String]
    public var contextLineIndices: [(Int, Int)]
    public var isEndOfFile: Bool

    public init(
        changeContext: String? = nil,
        oldLines: [String] = [],
        newLines: [String] = [],
        contextLineIndices: [(Int, Int)] = [],
        isEndOfFile: Bool = false
    ) {
        self.changeContext = changeContext
        self.oldLines = oldLines
        self.newLines = newLines
        self.contextLineIndices = contextLineIndices
        self.isEndOfFile = isEndOfFile
    }

    public mutating func pushContextLine(_ line: String) {
        contextLineIndices.append((oldLines.count, newLines.count))
        oldLines.append(line)
        newLines.append(line)
    }

    public static func == (lhs: UpdateFileChunk, rhs: UpdateFileChunk) -> Bool {
        lhs.changeContext == rhs.changeContext
            && lhs.oldLines == rhs.oldLines
            && lhs.newLines == rhs.newLines
            && lhs.isEndOfFile == rhs.isEndOfFile
            && lhs.contextLineIndices.count == rhs.contextLineIndices.count
            && zip(lhs.contextLineIndices, rhs.contextLineIndices).allSatisfy { left, right in
                left.0 == right.0 && left.1 == right.1
            }
    }
}

public func parsePatch(_ patch: String) throws -> ApplyPatchArgs {
    try parsePatchText(patch, mode: PARSE_IN_STRICT_MODE ? .strict : .lenient)
}

public enum ParseMode {
    case strict
    case lenient
}

public func parsePatchText(_ patch: String, mode: ParseMode) throws -> ApplyPatchArgs {
    let lines = Array(patch.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    let patchLines = try checkPatchBoundaries(lines, mode: mode)
    let joined = patchLines.joined(separator: "\n")
    var parser = StreamingPatchParser()
    _ = try parser.pushDelta(joined)
    let hunks = try parser.finish()
    return ApplyPatchArgs(
        patch: joined,
        hunks: hunks,
        workdir: nil,
        environmentID: parser.environmentID
    )
}

private func checkPatchBoundaries(_ lines: [String], mode: ParseMode) throws -> [String] {
    switch mode {
    case .strict:
        return try checkPatchBoundariesStrict(lines)
    case .lenient:
        return try checkPatchBoundariesLenient(lines)
    }
}

private func checkPatchBoundariesStrict(_ lines: [String]) throws -> [String] {
    let first = lines.first
    let last = lines.last
    try checkStartAndEndLinesStrict(first: first, last: last)
    return lines
}

private func checkPatchBoundariesLenient(_ originalLines: [String]) throws -> [String] {
    do {
        return try checkPatchBoundariesStrict(originalLines)
    } catch let original as ParseError {
        guard originalLines.count >= 4,
              let first = originalLines.first,
              let last = originalLines.last,
              first == "<<EOF" || first == "<<'EOF'" || first == "<<\"EOF\"",
              last.hasSuffix("EOF")
        else {
            throw original
        }
        let inner = Array(originalLines[1..<(originalLines.count - 1)])
        return try checkPatchBoundariesStrict(inner)
    }
}

private func checkStartAndEndLinesStrict(first: String?, last: String?) throws {
    let firstLine = first?.trimmingCharacters(in: .whitespacesAndNewlines)
    let lastLine = last?.trimmingCharacters(in: .whitespacesAndNewlines)
    if firstLine == BEGIN_PATCH_MARKER, lastLine == END_PATCH_MARKER {
        return
    }
    if firstLine != BEGIN_PATCH_MARKER {
        throw ParseError.invalidPatch("The first line of the patch must be '*** Begin Patch'")
    }
    throw ParseError.invalidPatch("The last line of the patch must be '*** End Patch'")
}

public enum ApplyPatchPaths {
    public static func resolve(_ path: String, cwd: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return cwd.appendingPathComponent(path).standardizedFileURL
    }
}

extension String {
    func applyPatchTrimEnd() -> String {
        var end = endIndex
        while end > startIndex {
            let previous = index(before: end)
            if self[previous].isWhitespace {
                end = previous
            } else {
                break
            }
        }
        return String(self[..<end])
    }

    func applyPatchStripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

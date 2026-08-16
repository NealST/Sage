//
//  FileToolHelpers.swift
//  Sage
//

import Foundation


// MARK: - Shared file-tool helpers

/// Resolves copy/move destination: if `destination` is an existing directory, appends
/// `source.lastPathComponent`; refuses an existing final path; creates parent directories.
nonisolated enum FileTransferDestination {
    static func prepare(source: URL, destination: URL) throws -> URL {
        var destination = destination
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
            destination = destination.appendingPathComponent(source.lastPathComponent)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw ToolError.operationFailed(
                "Destination already exists: \(PathGuard.displayPath(destination.path)). Delete it first or choose a different name."
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return destination
    }
}

/// Streams UTF-8 text lines from a `FileHandle`, retaining leftover bytes across chunks
/// so multi-byte characters are never split at chunk boundaries (split on `0x0A`).
nonisolated enum UTF8LineStreamer {
    static let defaultChunkSize = 64 * 1024

    /// Invokes `body` once per line (no trailing newline). Return `false` from `body` to stop.
    /// When `strict` is true, invalid UTF-8 throws; otherwise streaming stops quietly.
    static func forEachLine(
        handle: FileHandle,
        chunkSize: Int = defaultChunkSize,
        strict: Bool,
        body: (String) throws -> Bool
    ) throws {
        var leftover = Data()
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            let isEOF = chunk.isEmpty

            let dataToProcess: Data
            if isEOF {
                if leftover.isEmpty { break }
                dataToProcess = leftover
                leftover = Data()
            } else {
                let combined = leftover + chunk
                guard let lastNewline = combined.lastIndex(of: 0x0A) else {
                    leftover = combined
                    continue
                }
                let splitAt = combined.index(after: lastNewline)
                dataToProcess = Data(combined[combined.startIndex..<splitAt])
                leftover = Data(combined[splitAt...])
            }

            guard let text = String(data: dataToProcess, encoding: .utf8) else {
                if strict {
                    throw ToolError.operationFailed("File is not valid UTF-8 text")
                }
                return
            }

            let lines = text.components(separatedBy: "\n")
            // Non-EOF data always ends at a newline, so the last split element is empty.
            let processLines = isEOF ? lines[...] : lines.dropLast()
            for line in processLines {
                if try !body(line) { return }
            }
            if isEOF { break }
        }
    }
}


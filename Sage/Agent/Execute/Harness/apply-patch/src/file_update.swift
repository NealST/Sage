//
//  file_update.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/file_update.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//

import Foundation

struct AppliedPatch {
    var originalContents: String
    var newContents: String
}

func deriveNewContentsFromChunks(
    path: URL,
    chunks: [UpdateFileChunk],
    updateFileMode: ApplyPatchFileUpdateMode,
    fileSystem: ApplyPatchFileSystem
) throws -> AppliedPatch {
    let originalContents: String
    do {
        originalContents = try fileSystem.readFileText(path)
    } catch {
        throw ApplyPatchError.io(
            context: "Failed to read file to update \(path.path)",
            message: error.localizedDescription
        )
    }
    let pathText = path.path
    let newContents: String
    switch updateFileMode {
    case .normalizeToLf:
        var originalLines = originalContents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if originalLines.last?.isEmpty == true {
            originalLines.removeLast()
        }
        let replacements = try computeReplacements(
            originalLines: originalLines,
            path: pathText,
            chunks: chunks,
            updateFileMode: updateFileMode
        )
        var newLines = applyReplacements(originalLines, replacements)
        if newLines.last?.isEmpty != true {
            newLines.append("")
        }
        newContents = newLines.joined(separator: "\n")
    case .preserveLineEndings:
        var sourceFile = SourceFile.parse(originalContents)
        let originalLines = sourceFile.lineTexts()
        let replacements = try computeReplacements(
            originalLines: originalLines,
            path: pathText,
            chunks: chunks,
            updateFileMode: updateFileMode
        )
        sourceFile.applyReplacements(replacements)
        newContents = sourceFile.contents()
    }
    return AppliedPatch(originalContents: originalContents, newContents: newContents)
}

func computeReplacements(
    originalLines: [String],
    path: String,
    chunks: [UpdateFileChunk],
    updateFileMode: ApplyPatchFileUpdateMode
) throws -> [Replacement] {
    var replacements: [Replacement] = []
    var lineIndex = 0

    for chunk in chunks {
        if let context = chunk.changeContext {
            if let index = seekSequence(
                lines: originalLines,
                pattern: [context],
                start: lineIndex,
                eof: false,
                updateFileMode: updateFileMode
            ) {
                lineIndex = index + 1
            } else {
                throw ApplyPatchError.computeReplacements("Failed to find context '\(context)' in \(path)")
            }
        }

        if chunk.oldLines.isEmpty {
            let insertionIndex: Int
            switch updateFileMode {
            case .normalizeToLf:
                insertionIndex = originalLines.last?.isEmpty == true
                    ? originalLines.count - 1
                    : originalLines.count
            case .preserveLineEndings:
                insertionIndex = originalLines.count
            }
            replacements.append((insertionIndex, 0, chunk.newLines))
            continue
        }

        var pattern = chunk.oldLines
        var found = seekSequence(
            lines: originalLines,
            pattern: pattern,
            start: lineIndex,
            eof: chunk.isEndOfFile,
            updateFileMode: updateFileMode
        )
        var newSlice = chunk.newLines
        if found == nil, pattern.last?.isEmpty == true {
            pattern = Array(pattern.dropLast())
            if newSlice.last?.isEmpty == true {
                newSlice = Array(newSlice.dropLast())
            }
            found = seekSequence(
                lines: originalLines,
                pattern: pattern,
                start: lineIndex,
                eof: chunk.isEndOfFile,
                updateFileMode: updateFileMode
            )
        }

        guard let startIndex = found else {
            throw ApplyPatchError.computeReplacements(
                "Failed to find expected lines in \(path):\n\(chunk.oldLines.joined(separator: "\n"))"
            )
        }

        switch updateFileMode {
        case .normalizeToLf:
            replacements.append((startIndex, pattern.count, newSlice))
        case .preserveLineEndings:
            var oldStart = 0
            var newStart = 0
            for (oldContext, newContext) in chunk.contextLineIndices {
                if oldContext >= pattern.count || newContext >= newSlice.count {
                    break
                }
                if oldStart != oldContext || newStart != newContext {
                    replacements.append((
                        startIndex + oldStart,
                        oldContext - oldStart,
                        Array(newSlice[newStart..<newContext])
                    ))
                }
                oldStart = oldContext + 1
                newStart = newContext + 1
            }
            if oldStart != pattern.count || newStart != newSlice.count {
                replacements.append((
                    startIndex + oldStart,
                    pattern.count - oldStart,
                    Array(newSlice[newStart...])
                ))
            }
        }
        lineIndex = startIndex + pattern.count
    }

    replacements.sort { $0.start < $1.start }
    return replacements
}

func applyReplacements(_ lines: [String], _ replacements: [Replacement]) -> [String] {
    var lines = lines
    for replacement in replacements.reversed() {
        var start = replacement.start
        for _ in 0..<replacement.oldCount where start < lines.count {
            lines.remove(at: start)
        }
        for (offset, line) in replacement.newLines.enumerated() {
            lines.insert(line, at: start + offset)
        }
    }
    return lines
}

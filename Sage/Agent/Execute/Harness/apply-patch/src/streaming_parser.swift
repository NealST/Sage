//
//  streaming_parser.swift
//  ApplyPatch
//
//  Port of codex-rs/apply-patch/src/streaming_parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import Foundation

let ENVIRONMENT_ID_MARKER = "*** Environment ID:"

struct StreamingPatchParser {
    private var lineBuffer = ""
    private var state = StreamingParserState()
    private var lineNumber = 0

    var environmentID: String? { state.environmentID }

    mutating func pushDelta(_ delta: String) throws -> [Hunk] {
        for character in delta {
            if character == "\n" {
                var line = lineBuffer
                lineBuffer = ""
                if line.hasSuffix("\r") {
                    line.removeLast()
                }
                lineNumber += 1
                try processLine(line)
            } else {
                lineBuffer.append(character)
            }
        }
        return state.hunks
    }

    mutating func finish() throws -> [Hunk] {
        if !lineBuffer.isEmpty {
            let line = lineBuffer
            lineBuffer = ""
            lineNumber += 1
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == END_PATCH_MARKER {
                try ensureUpdateHunkIsNotEmpty(line.trimmingCharacters(in: .whitespacesAndNewlines))
                state.mode = .endedPatch
            } else {
                try processLine(line)
            }
        }
        guard state.mode == .endedPatch else {
            throw ParseError.invalidPatch("The last line of the patch must be '*** End Patch'")
        }
        return state.hunks
    }

    private mutating func ensureUpdateHunkIsNotEmpty(_ line: String) throws {
        guard case .updateFile(let path, _, let chunks) = state.hunks.last else { return }
        if chunks.isEmpty, case .updateFile(let hunkLineNumber) = state.mode {
            throw ParseError.invalidHunk(
                message: "Update file hunk for path '\(path)' is empty",
                lineNumber: hunkLineNumber
            )
        }
        if let chunk = chunks.last, chunk.oldLines.isEmpty, chunk.newLines.isEmpty {
            if line == END_PATCH_MARKER {
                throw ParseError.invalidHunk(
                    message: "Update hunk does not contain any lines",
                    lineNumber: lineNumber
                )
            }
            throw ParseError.invalidHunk(
                message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: lineNumber
            )
        }
    }

    private mutating func handleHunkHeadersAndEndPatch(_ trimmed: String) throws -> Bool {
        if state.mode == .startedPatch, let rawID = trimmed.applyPatchStripPrefix(ENVIRONMENT_ID_MARKER) {
            if state.environmentID != nil {
                throw ParseError.invalidPatch(
                    "apply_patch environment_id cannot be specified more than once"
                )
            }
            let environmentID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            if environmentID.isEmpty {
                throw ParseError.invalidPatch("apply_patch environment_id cannot be empty")
            }
            state.environmentID = environmentID
            return true
        }
        if trimmed == END_PATCH_MARKER {
            try ensureUpdateHunkIsNotEmpty(trimmed)
            state.mode = .endedPatch
            return true
        }
        if let path = trimmed.applyPatchStripPrefix(ADD_FILE_MARKER) {
            try ensureUpdateHunkIsNotEmpty(trimmed)
            state.hunks.append(.addFile(path: path, contents: ""))
            state.mode = .addFile
            return true
        }
        if let path = trimmed.applyPatchStripPrefix(DELETE_FILE_MARKER) {
            try ensureUpdateHunkIsNotEmpty(trimmed)
            state.hunks.append(.deleteFile(path: path))
            state.mode = .deleteFile
            return true
        }
        if let path = trimmed.applyPatchStripPrefix(UPDATE_FILE_MARKER) {
            try ensureUpdateHunkIsNotEmpty(trimmed)
            state.hunks.append(.updateFile(path: path, movePath: nil, chunks: []))
            state.mode = .updateFile(hunkLineNumber: lineNumber)
            return true
        }
        return false
    }

    private mutating func processLine(_ line: String) throws {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.mode {
        case .notStarted:
            if trimmed == BEGIN_PATCH_MARKER {
                state.mode = .startedPatch
                return
            }
            throw ParseError.invalidPatch("The first line of the patch must be '*** Begin Patch'")

        case .startedPatch:
            if try handleHunkHeadersAndEndPatch(trimmed) { return }
            throw ParseError.invalidHunk(
                message: "'\(trimmed)' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'",
                lineNumber: lineNumber
            )

        case .addFile:
            if try handleHunkHeadersAndEndPatch(trimmed) { return }
            if let added = line.applyPatchStripPrefix("+"),
               case .addFile(let path, var contents) = state.hunks.last {
                contents.append(added)
                contents.append("\n")
                state.hunks[state.hunks.count - 1] = .addFile(path: path, contents: contents)
                return
            }
            throw ParseError.invalidHunk(
                message: "'\(trimmed)' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'",
                lineNumber: lineNumber
            )

        case .deleteFile:
            if try handleHunkHeadersAndEndPatch(trimmed) { return }
            throw ParseError.invalidHunk(
                message: "'\(trimmed)' is not a valid hunk header. Valid hunk headers: '*** Add File: {path}', '*** Delete File: {path}', '*** Update File: {path}'",
                lineNumber: lineNumber
            )

        case .updateFile(let hunkLineNumber):
            try processUpdateLine(line, hunkLineNumber: hunkLineNumber)

        case .endedPatch:
            if trimmed.isEmpty { return }
            throw ParseError.invalidPatch("The last line of the patch must be '*** End Patch'")
        }
    }

    private mutating func processUpdateLine(_ line: String, hunkLineNumber: Int) throws {
        let updateLine = line.applyPatchTrimEnd()
        if try handleHunkHeadersAndEndPatch(updateLine) { return }

        guard case .updateFile(let path, var movePath, var chunks) = state.hunks.last else {
            throw ParseError.invalidHunk(
                message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: lineNumber
            )
        }

        if chunks.last?.isEndOfFile == true {
            if updateLine.isEmpty {
                return
            }
            if updateLine != EMPTY_CHANGE_CONTEXT_MARKER,
               !updateLine.hasPrefix(CHANGE_CONTEXT_MARKER) {
                throw ParseError.invalidHunk(
                    message: "Expected update hunk to start with a @@ context marker, got: '\(line)'",
                    lineNumber: lineNumber
                )
            }
        }

        if chunks.isEmpty, movePath == nil, let dest = updateLine.applyPatchStripPrefix(MOVE_TO_MARKER) {
            movePath = dest
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if (updateLine == EMPTY_CHANGE_CONTEXT_MARKER || updateLine.hasPrefix(CHANGE_CONTEXT_MARKER)),
           let last = chunks.last, last.oldLines.isEmpty, last.newLines.isEmpty {
            throw ParseError.invalidHunk(
                message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
                lineNumber: lineNumber
            )
        }

        if updateLine == EMPTY_CHANGE_CONTEXT_MARKER {
            chunks.append(UpdateFileChunk())
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if let changeContext = updateLine.applyPatchStripPrefix(CHANGE_CONTEXT_MARKER) {
            var chunk = UpdateFileChunk()
            chunk.changeContext = changeContext
            chunks.append(chunk)
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if updateLine == EOF_MARKER {
            if let last = chunks.last, last.oldLines.isEmpty, last.newLines.isEmpty {
                throw ParseError.invalidHunk(
                    message: "Update hunk does not contain any lines",
                    lineNumber: lineNumber
                )
            }
            if !chunks.isEmpty {
                chunks[chunks.count - 1].isEndOfFile = true
            }
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if line.isEmpty {
            if chunks.isEmpty { chunks.append(UpdateFileChunk()) }
            chunks[chunks.count - 1].pushContextLine("")
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if let context = line.applyPatchStripPrefix(" ") {
            if chunks.isEmpty { chunks.append(UpdateFileChunk()) }
            chunks[chunks.count - 1].pushContextLine(context)
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if let added = line.applyPatchStripPrefix("+") {
            if chunks.isEmpty { chunks.append(UpdateFileChunk()) }
            chunks[chunks.count - 1].newLines.append(added)
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if let removed = line.applyPatchStripPrefix("-") {
            if chunks.isEmpty { chunks.append(UpdateFileChunk()) }
            chunks[chunks.count - 1].oldLines.append(removed)
            state.hunks[state.hunks.count - 1] = .updateFile(path: path, movePath: movePath, chunks: chunks)
            state.mode = .updateFile(hunkLineNumber: hunkLineNumber)
            return
        }

        if let last = chunks.last, !last.oldLines.isEmpty || !last.newLines.isEmpty {
            throw ParseError.invalidHunk(
                message: "Expected update hunk to start with a @@ context marker, got: '\(line)'",
                lineNumber: lineNumber
            )
        }

        throw ParseError.invalidHunk(
            message: "Unexpected line found in update hunk: '\(line)'. Every line should start with ' ' (context line), '+' (added line), or '-' (removed line)",
            lineNumber: lineNumber
        )
    }
}

private struct StreamingParserState {
    var mode: StreamingParserMode = .notStarted
    var hunks: [Hunk] = []
    var environmentID: String?
}

private enum StreamingParserMode: Equatable {
    case notStarted
    case startedPatch
    case addFile
    case deleteFile
    case updateFile(hunkLineNumber: Int)
    case endedPatch
}

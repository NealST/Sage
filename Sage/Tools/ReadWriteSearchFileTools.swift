//
//  ReadWriteSearchFileTools.swift
//  Sage
//

import Foundation

nonisolated struct ReadTextFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "read_text_file",
        description: """
            Read a UTF-8 text file inside the active sandbox (home ~/ or project root). \
            Returns raw file content (no line numbers added). \
            Full read is capped at ~100KB — for larger files, use line_start/line_end to read a section. \
            Use list_directory first to check file size if unsure.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("File path (must exist)"),
                "line_start": .intProperty("First line to read (1-based, inclusive). Omit to start from beginning."),
                "line_end": .intProperty("Last line to read (1-based, inclusive). Omit to read to end."),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable {
        let path: String
        let lineStart: Int?
        let lineEnd: Int?
    }

    private static let maxBytes = 100_000

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path, access: .read)
        try Self.assertReadableFile(at: url, path: args.path)
        if args.lineStart == nil && args.lineEnd == nil {
            return try Self.readEntireFile(at: url)
        }
        return try Self.readLineRange(at: url, path: args.path, start: args.lineStart, end: args.lineEnd)
    }

    static func assertReadableFile(at url: URL, path: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ToolError.operationFailed(
                "File does not exist: \(path). Use list_directory to verify the path."
            )
        }
        guard !isDir.boolValue else {
            throw ToolError.operationFailed(
                "Path is a directory, not a file: \(path). Use list_directory to browse directories."
            )
        }
    }

    static func readEntireFile(at url: URL) throws -> String {
        let data = try SafeFileIO.readData(at: url, maxBytes: maxBytes)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.operationFailed("File is not valid UTF-8 text")
        }
        return text
    }

    static func readLineRange(at url: URL, path: String, start: Int?, end: Int?) throws -> String {
        let handle = try SafeFileIO.openForReading(at: url)
        defer { try? handle.close() }
        let startLine = max((start ?? 1), 1)
        let endLine = end ?? Int.max
        guard startLine <= endLine else {
            throw ToolError.invalidArguments("line_start (\(startLine)) must be ≤ line_end (\(endLine))")
        }
        var currentLine = 1
        var result: [String] = []
        var totalBytes = 0
        var truncated = false
        try UTF8LineStreamer.forEachLine(handle: handle, strict: true) { line in
            if currentLine > endLine { return false }
            if currentLine >= startLine {
                result.append(line)
                totalBytes += line.utf8.count + 1
                if totalBytes > maxBytes {
                    truncated = true
                    return false
                }
            }
            currentLine += 1
            return true
        }
        if truncated {
            return result.joined(separator: "\n") + "\n… (truncated at \(maxBytes) bytes)"
        }
        if result.isEmpty {
            throw ToolError.invalidArguments(
                """
                Line range \(startLine)–\(endLine == Int.max ? "end" : String(endLine)) \
                is out of bounds (file has \(currentLine - 1) lines)
                """
            )
        }
        return result.joined(separator: "\n")
    }
}

nonisolated struct WriteTextFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "write_text_file",
        description: """
            Write UTF-8 text to a file inside the active sandbox (home ~/ or project root). \
            Creates parent folders if needed. \
            WARNING: Overwrites the file if it already exists — read it first if you need to preserve content. \
            Content must be the complete file — there is no append or patch mode.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("File path (will be created or overwritten)"),
                "content": .stringProperty("Complete file contents to write"),
            ],
            required: ["path", "content"]
        )
    )

    private struct Args: Decodable {
        let path: String
        let content: String
    }

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        let existed = FileManager.default.fileExists(atPath: url.path)
        // Capture before contents for UI diff; omit when missing/unreadable/non-UTF8.
        let before: String? = {
            guard existed else { return nil }
            guard let data = try? SafeFileIO.readData(at: url, maxBytes: 1_048_576) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }()
        try SafeFileIO.atomicWrite(Data(args.content.utf8), to: url)
        return WriteFileResultCodec.makeResult(
            path: PathGuard.displayPath(url.path),
            created: !existed,
            before: before,
            after: args.content
        )
    }
}

// MARK: - Search

nonisolated struct SearchFilesTool: AgentTool {
    let definition = ToolDefinition(
        name: "search_files",
        description: """
            Search for files by name pattern and optionally grep their contents. \
            Paths must stay inside the active sandbox (home ~/ in General, or the focused project root). \
            In a project, omit `path` (or pass ".") to search from the project root. \
            Symlinks that resolve outside the sandbox are skipped. \
            Returns up to 50 matches. Each result is one line: the file path, optionally followed by \
            ":line_number:matched_line" when content_pattern is used. \
            Use this instead of listing directories manually when looking for specific files.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty(
                    "Directory to search in (recursive). Optional in a focused project — defaults to the project root."
                ),
                "name_pattern": .stringProperty(
                    "Glob pattern for file names (e.g. '*.swift', 'README*'). Default '*' matches all."
                ),
                "content_pattern": .stringProperty(
                    "Optional regex pattern to search inside matching files. Only UTF-8 text files are searched."
                ),
                "include_hidden": .boolProperty("Include hidden files/directories. Default false."),
            ],
            required: []
        )
    )

    private struct Args: Decodable {
        let path: String?
        let namePattern: String?
        let contentPattern: String?
        let includeHidden: FlexibleBool?
    }

    private static let maxResults = 50
    private static let maxFileSize = 512_000 // skip files > 500KB for content search

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let effectivePath = try PathGuard.defaultExplorationPath(args.path)
        let rootURL = try PathGuard.resolveAllowed(effectivePath, access: .read)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ToolError.operationFailed(
                "Directory does not exist: \(effectivePath). Use list_directory to verify the path."
            )
        }
        let skipHidden = !(args.includeHidden?.value ?? false)
        let contentRegex = try Self.compileContentRegex(args.contentPattern)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: skipHidden ? [.skipsHiddenFiles] : []
        ) else {
            throw ToolError.operationFailed("Cannot enumerate directory: \(effectivePath)")
        }
        var results: [String] = []
        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if results.count >= Self.maxResults { break }
            try Self.collectMatch(
                fileURL,
                enumerator: enumerator,
                namePattern: args.namePattern ?? "*",
                contentRegex: contentRegex,
                into: &results
            )
        }

        if results.isEmpty {
            return "(no matches)"
        }

        var output = results.joined(separator: "\n")
        if results.count >= Self.maxResults {
            output += "\n… (showing first \(Self.maxResults) matches — narrow the path or pattern for more)"
        }
        return output
    }

    static func compileContentRegex(_ pattern: String?) throws -> NSRegularExpression? {
        guard let pattern, !pattern.isEmpty else { return nil }
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw ToolError.invalidArguments("Invalid regex pattern: \(error.localizedDescription)")
        }
    }

    static func collectMatch(
        _ fileURL: URL,
        enumerator: FileManager.DirectoryEnumerator,
        namePattern: String,
        contentRegex: NSRegularExpression?,
        into results: inout [String]
    ) throws {
        guard let allowed = PathGuard.resolveEnumeratedURL(fileURL, access: .read) else {
            enumerator.skipDescendants()
            return
        }
        let values = try? allowed.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return }
        guard globMatch(allowed.lastPathComponent, pattern: namePattern) else { return }
        if let regex = contentRegex {
            try appendContentMatches(allowed, fileSize: values?.fileSize ?? 0, regex: regex, into: &results)
        } else {
            results.append(PathGuard.displayPath(allowed.path))
        }
    }

    static func appendContentMatches(
        _ allowed: URL,
        fileSize: Int,
        regex: NSRegularExpression,
        into results: inout [String]
    ) throws {
        guard fileSize <= maxFileSize else { return }
        let handle = try SafeFileIO.openForReading(at: allowed)
        defer { try? handle.close() }
        var lineNumber = 0
        try UTF8LineStreamer.forEachLine(handle: handle, strict: false) { line in
            lineNumber += 1
            if results.count >= maxResults { return false }
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                results.append("\(PathGuard.displayPath(allowed.path)):\(lineNumber):\(line)")
            }
            return results.count < maxResults
        }
    }

    /// Simple glob matching: supports * (any chars) and ? (single char).
    static func globMatch(_ string: String, pattern: String) -> Bool {
        let pred = NSPredicate(format: "SELF LIKE[c] %@", pattern)
        return pred.evaluate(with: string)
    }
}

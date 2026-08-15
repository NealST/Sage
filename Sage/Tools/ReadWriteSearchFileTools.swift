//
//  ReadWriteSearchFileTools.swift
//  Sage
//

import Foundation

struct ReadTextFileTool: AgentTool {
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

        enum CodingKeys: String, CodingKey {
            case path
            case lineStart = "line_start"
            case lineEnd = "line_end"
        }
    }

    private static let maxBytes = 100_000

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path, access: .read)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ToolError.operationFailed(
                "File does not exist: \(args.path). Use list_directory to verify the path."
            )
        }
        guard !isDir.boolValue else {
            throw ToolError.operationFailed(
                "Path is a directory, not a file: \(args.path). Use list_directory to browse directories."
            )
        }

        // Full file read (no line range)
        if args.lineStart == nil && args.lineEnd == nil {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs[.size] as? Int) ?? 0
            guard fileSize <= Self.maxBytes else {
                throw ToolError.operationFailed(
                    "File too large (\(fileSize) bytes). Use line_start/line_end to read a section."
                )
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ToolError.operationFailed("File is not valid UTF-8 text")
            }
            return text
        }

        // Partial read: stream lines with UTF-8 safe chunk handling
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw ToolError.operationFailed("Cannot open file: \(args.path)")
        }
        defer { handle.closeFile() }

        let startLine = max((args.lineStart ?? 1), 1)
        let endLine = args.lineEnd ?? Int.max

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
                if totalBytes > Self.maxBytes {
                    truncated = true
                    return false
                }
            }
            currentLine += 1
            return true
        }

        if truncated {
            return result.joined(separator: "\n") + "\n… (truncated at \(Self.maxBytes) bytes)"
        }

        if result.isEmpty {
            throw ToolError.invalidArguments(
                "Line range \(startLine)–\(endLine == Int.max ? "end" : String(endLine)) is out of bounds (file has \(currentLine - 1) lines)"
            )
        }

        return result.joined(separator: "\n")
    }
}

struct WriteTextFileTool: AgentTool {
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

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        let existed = FileManager.default.fileExists(atPath: url.path)
        // Capture before contents for UI diff; omit when missing/unreadable/non-UTF8.
        let before: String? = {
            guard existed else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try args.content.write(to: url, atomically: true, encoding: .utf8)
        return WriteFileResultCodec.makeResult(
            path: PathGuard.displayPath(url.path),
            created: !existed,
            before: before,
            after: args.content
        )
    }
}

// MARK: - Search

struct SearchFilesTool: AgentTool {
    let definition = ToolDefinition(
        name: "search_files",
        description: """
            Search for files by name pattern and optionally grep their contents. \
            Paths must stay inside the active sandbox (home ~/ in General, or the focused project root). \
            In a project, omit `path` (or pass ".") to search from the project root. \
            Returns up to 50 matches. Each result is one line: the file path, optionally followed by \
            ":line_number:matched_line" when content_pattern is used. \
            Use this instead of listing directories manually when looking for specific files.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty(
                    "Directory to search in (recursive). Optional in a focused project — defaults to the project root."
                ),
                "name_pattern": .stringProperty("Glob pattern for file names (e.g. '*.swift', 'README*'). Default '*' matches all."),
                "content_pattern": .stringProperty("Optional regex pattern to search inside matching files. Only UTF-8 text files are searched."),
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

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let effectivePath = try PathGuard.defaultExplorationPath(args.path)
        let rootURL = try PathGuard.resolveAllowed(effectivePath, access: .read)

        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ToolError.operationFailed(
                "Directory does not exist: \(effectivePath). Use list_directory to verify the path."
            )
        }

        let namePattern = args.namePattern ?? "*"
        let skipHidden = !(args.includeHidden?.value ?? false)

        // Compile content regex if provided
        let contentRegex: NSRegularExpression?
        if let pattern = args.contentPattern, !pattern.isEmpty {
            do {
                contentRegex = try NSRegularExpression(pattern: pattern, options: [])
            } catch {
                throw ToolError.invalidArguments(
                    "Invalid regex pattern: \(error.localizedDescription)"
                )
            }
        } else {
            contentRegex = nil
        }

        var results: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: skipHidden ? [.skipsHiddenFiles] : []
        ) else {
            throw ToolError.operationFailed("Cannot enumerate directory: \(effectivePath)")
        }

        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if results.count >= Self.maxResults { break }

            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])

            // Skip directories for matching (but enumerator still recurses into them)
            guard values?.isRegularFile == true else { continue }

            // Match file name against glob pattern
            let fileName = fileURL.lastPathComponent
            guard globMatch(fileName, pattern: namePattern) else { continue }

            if let regex = contentRegex {
                // Content search — skip large or binary files
                let fileSize = values?.fileSize ?? 0
                guard fileSize <= Self.maxFileSize else { continue }
                guard let handle = FileHandle(forReadingAtPath: fileURL.path) else { continue }
                defer { handle.closeFile() }

                // Stream lines to avoid loading entire file into memory
                var lineNumber = 0
                try UTF8LineStreamer.forEachLine(handle: handle, strict: false) { line in
                    lineNumber += 1
                    if results.count >= Self.maxResults { return false }
                    let range = NSRange(line.startIndex..., in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        results.append("\(PathGuard.displayPath(fileURL.path)):\(lineNumber):\(line)")
                    }
                    return results.count < Self.maxResults
                }
            } else {
                // Name-only search
                results.append(PathGuard.displayPath(fileURL.path))
            }
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

    /// Simple glob matching: supports * (any chars) and ? (single char).
    private func globMatch(_ string: String, pattern: String) -> Bool {
        let pred = NSPredicate(format: "SELF LIKE[c] %@", pattern)
        return pred.evaluate(with: string)
    }
}

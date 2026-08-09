//
//  FileTools.swift
//  Sage
//

import Foundation

struct ListDirectoryTool: AgentTool {
    let definition = ToolDefinition(
        name: "list_directory",
        description: """
            List files and folders in a directory. Paths must stay inside the active sandbox \
            (home ~/ in General, or the focused project root). Relative paths resolve against the project root when focused.
            Output format: one entry per line as "kind\\tsize\\tpath" (kind is "dir" or "file", size in bytes or "-" for dirs).
            Recursive listing indents child entries with spaces. Capped at 500 entries.
            Use depth=1 (default) for a quick overview, increase up to 5 for deeper exploration.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Absolute or ~ path to the directory"),
                "depth": .intProperty("Recursion depth (1 = immediate children only, default 1, max 5)"),
                "include_hidden": .boolProperty("Include hidden files/directories. Default false."),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable {
        let path: String
        let depth: Int?
        let includeHidden: FlexibleBool?
    }

    private static let maxEntries = 500

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.operationFailed("Directory does not exist: \(args.path)")
        }

        // Validate it's actually a directory
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard isDir.boolValue else {
            throw ToolError.operationFailed(
                "Path is a file, not a directory: \(args.path). Use read_text_file to read file contents."
            )
        }

        let requestedDepth = args.depth ?? 1
        let maxDepth = min(max(requestedDepth, 1), 5)
        let skipHidden = !(args.includeHidden?.value ?? false)
        var lines: [String] = []
        var truncated = false
        listRecursive(url: url, depth: maxDepth, currentDepth: 0, skipHidden: skipHidden, lines: &lines, truncated: &truncated)

        var result = lines.isEmpty ? "(empty directory)" : lines.joined(separator: "\n")
        if requestedDepth != maxDepth {
            result += "\n(note: depth clamped to \(maxDepth), requested \(requestedDepth))"
        }
        if truncated {
            result += "\n… (truncated at \(Self.maxEntries) entries — narrow the path or reduce depth to see more)"
        }
        return result
    }

    private func listRecursive(url: URL, depth: Int, currentDepth: Int, skipHidden: Bool, lines: inout [String], truncated: inout Bool) {
        guard currentDepth < depth, !truncated else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: skipHidden ? [.skipsHiddenFiles] : []
        ) else { return }

        let sorted = items.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        for item in sorted {
            guard !truncated else { return }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory == true
            let kind = isDir ? "dir" : "file"
            let size = values?.fileSize.map(String.init) ?? "-"
            let indent = String(repeating: "  ", count: currentDepth)
            lines.append("\(indent)\(kind)\t\(size)\t\(item.path)")

            if lines.count >= Self.maxEntries {
                truncated = true
                return
            }
            if isDir {
                listRecursive(url: item, depth: depth, currentDepth: currentDepth + 1, skipHidden: skipHidden, lines: &lines, truncated: &truncated)
            }
        }
    }
}

struct MoveFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "move_file",
        description: """
            Move a file or folder to a new location. Both source and destination must be under ~/. \
            If destination is an existing directory, the source is moved into it. \
            To rename in place, use rename_file instead.
            """,
        parameters: .schemaObject(
            properties: [
                "source": .stringProperty("Source path (must exist)"),
                "destination": .stringProperty("Destination path or directory"),
            ],
            required: ["source", "destination"]
        )
    )

    private struct Args: Decodable {
        let source: String
        let destination: String
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.source)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ToolError.operationFailed(
                "Source does not exist: \(args.source). Use list_directory to verify the path."
            )
        }
        var destination = try PathGuard.resolveAllowed(args.destination)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
            destination = destination.appendingPathComponent(source.lastPathComponent)
        }
        // Check if final destination already exists
        if FileManager.default.fileExists(atPath: destination.path) {
            throw ToolError.operationFailed(
                "Destination already exists: \(destination.path). Delete it first or choose a different name."
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        return "[OK] Moved to \(destination.path)"
    }
}

struct RenameFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "rename_file",
        description: """
            Rename a file or folder in its current directory (does not move it). Path must be under ~/. \
            To move to a different directory, use move_file instead.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Current path (must exist)"),
                "new_name": .stringProperty("New file or folder name (just the name, not a full path)"),
            ],
            required: ["path", "new_name"]
        )
    )

    private struct Args: Decodable {
        let path: String
        let newName: String

        enum CodingKeys: String, CodingKey {
            case path
            case newName = "new_name"
        }
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ToolError.operationFailed(
                "File does not exist: \(args.path). Use list_directory to verify the path."
            )
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(args.newName)
        _ = try PathGuard.resolveAllowed(destination.path)
        try FileManager.default.moveItem(at: source, to: destination)
        return "[OK] Renamed to \(destination.path)"
    }
}

struct CreateDirectoryTool: AgentTool {
    let definition = ToolDefinition(
        name: "create_directory",
        description: "Create a directory (and any missing parent directories) inside the active sandbox (home ~/ or the focused project root). Safe to call if the directory already exists.",
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Directory path to create"),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable { let path: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "[OK] Created \(url.path)"
    }
}

struct DeleteFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "delete_file",
        description: """
            Delete a file or an empty directory under ~/. \
            Non-empty directories cannot be deleted — remove their contents first. \
            This operation is irreversible.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Path to the file or empty directory to delete (must exist)"),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable { let path: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.operationFailed(
                "File does not exist: \(args.path). Use list_directory to verify the path."
            )
        }
        // Safety: refuse to delete non-empty directories
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            // Exclude .DS_Store from emptiness check — it's auto-generated by Finder
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
                throw ToolError.operationFailed(
                    "Cannot read directory contents: \(args.path). Check permissions."
                )
            }
            let meaningful = contents.filter { $0 != ".DS_Store" }
            if !meaningful.isEmpty {
                throw ToolError.operationFailed(
                    "Directory is not empty (\(meaningful.count) items). Remove contents first."
                )
            }
        }
        try FileManager.default.removeItem(at: url)
        return "[OK] Deleted \(url.path)"
    }
}

struct CopyFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "copy_file",
        description: """
            Copy a file or folder to a new location. Both paths must be under ~/. \
            If destination is an existing directory, the source is copied into it. \
            Fails if the destination file already exists.
            """,
        parameters: .schemaObject(
            properties: [
                "source": .stringProperty("Source path (must exist)"),
                "destination": .stringProperty("Destination path or directory"),
            ],
            required: ["source", "destination"]
        )
    )

    private struct Args: Decodable {
        let source: String
        let destination: String
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.source)
        var destination = try PathGuard.resolveAllowed(args.destination)

        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ToolError.operationFailed(
                "Source does not exist: \(args.source). Use list_directory to verify the path."
            )
        }

        // If destination is an existing directory, copy into it
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
            destination = destination.appendingPathComponent(source.lastPathComponent)
        }

        // Check if final destination already exists
        if FileManager.default.fileExists(atPath: destination.path) {
            throw ToolError.operationFailed(
                "Destination already exists: \(destination.path). Delete it first or choose a different name."
            )
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return "[OK] Copied to \(destination.path)"
    }
}

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
        let url = try PathGuard.resolveAllowed(args.path)

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
        let bufferSize = 64 * 1024
        // Keep raw bytes for leftover to avoid splitting multi-byte UTF-8 characters
        var leftoverData = Data()

        while true {
            let chunk = handle.readData(ofLength: bufferSize)
            let isEOF = chunk.isEmpty

            if isEOF {
                if leftoverData.isEmpty { break }
                // Process remaining data at EOF
                guard let text = String(data: leftoverData, encoding: .utf8) else {
                    throw ToolError.operationFailed("File is not valid UTF-8 text")
                }
                leftoverData = Data()
                let segments = text.components(separatedBy: "\n")
                for line in segments {
                    if currentLine > endLine { break }
                    if currentLine >= startLine {
                        result.append(line)
                        totalBytes += line.utf8.count + 1
                        if totalBytes > Self.maxBytes {
                            return result.joined(separator: "\n") + "\n… (truncated at \(Self.maxBytes) bytes)"
                        }
                    }
                    currentLine += 1
                }
                break
            }

            // Combine leftover bytes with new chunk
            var combined = leftoverData + chunk

            // Find the last newline byte to ensure we only decode complete lines
            // This prevents splitting multi-byte UTF-8 characters at chunk boundaries
            guard let lastNewline = combined.lastIndex(of: 0x0A) else {
                // No newline in this chunk — accumulate and continue
                leftoverData = combined
                continue
            }

            // Split: decodable portion up to (including) last newline, remainder is leftover
            let decodableEnd = combined.index(after: lastNewline)
            let decodable = combined[combined.startIndex..<decodableEnd]
            leftoverData = Data(combined[decodableEnd...])

            guard let text = String(data: decodable, encoding: .utf8) else {
                throw ToolError.operationFailed("File is not valid UTF-8 text")
            }

            // Process lines (drop last empty element from trailing \n split)
            let segments = text.components(separatedBy: "\n")
            // The last element is always "" because we split at the last \n
            let linesToProcess = segments.dropLast()

            for line in linesToProcess {
                if currentLine > endLine { break }
                if currentLine >= startLine {
                    result.append(line)
                    totalBytes += line.utf8.count + 1
                    if totalBytes > Self.maxBytes {
                        return result.joined(separator: "\n") + "\n… (truncated at \(Self.maxBytes) bytes)"
                    }
                }
                currentLine += 1
            }

            if currentLine > endLine { break }
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
            path: url.path,
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
            Search for files by name pattern and optionally grep their contents. Path must be under ~/. \
            Returns up to 50 matches. Each result is one line: the file path, optionally followed by \
            ":line_number:matched_line" when content_pattern is used. \
            Use this instead of listing directories manually when looking for specific files.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Directory to search in (recursive)"),
                "name_pattern": .stringProperty("Glob pattern for file names (e.g. '*.swift', 'README*'). Default '*' matches all."),
                "content_pattern": .stringProperty("Optional regex pattern to search inside matching files. Only UTF-8 text files are searched."),
                "include_hidden": .boolProperty("Include hidden files/directories. Default false."),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable {
        let path: String
        let namePattern: String?
        let contentPattern: String?
        let includeHidden: FlexibleBool?
    }

    private static let maxResults = 50
    private static let maxFileSize = 512_000 // skip files > 500KB for content search

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let rootURL = try PathGuard.resolveAllowed(args.path)

        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw ToolError.operationFailed(
                "Directory does not exist: \(args.path). Use list_directory to verify the path."
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
            throw ToolError.operationFailed("Cannot enumerate directory: \(args.path)")
        }

        for case let fileURL as URL in enumerator {
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
                var leftover = Data()
                let chunkSize = 64 * 1024

                lineLoop: while results.count < Self.maxResults {
                    let chunk = handle.readData(ofLength: chunkSize)
                    let isEOF = chunk.isEmpty

                    let dataToProcess: Data
                    if isEOF {
                        if leftover.isEmpty { break }
                        dataToProcess = leftover
                        leftover = Data()
                    } else {
                        let combined = leftover + chunk
                        if let lastNL = combined.lastIndex(of: 0x0A) {
                            let splitAt = combined.index(after: lastNL)
                            dataToProcess = Data(combined[combined.startIndex..<splitAt])
                            leftover = Data(combined[splitAt...])
                        } else {
                            leftover = combined
                            continue
                        }
                    }

                    guard let text = String(data: dataToProcess, encoding: .utf8) else { break }
                    let lines = text.components(separatedBy: "\n")
                    // Last element is empty when data ends with \n
                    let processLines = isEOF ? lines : lines.dropLast()
                    for line in processLines {
                        lineNumber += 1
                        if results.count >= Self.maxResults { break lineLoop }
                        let range = NSRange(line.startIndex..., in: line)
                        if regex.firstMatch(in: line, range: range) != nil {
                            results.append("\(fileURL.path):\(lineNumber):\(line)")
                        }
                    }

                    if isEOF { break }
                }
            } else {
                // Name-only search
                results.append(fileURL.path)
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

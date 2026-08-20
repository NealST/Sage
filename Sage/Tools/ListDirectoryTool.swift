//
//  ListDirectoryTool.swift
//  Sage
//

import Foundation

nonisolated struct ListDirectoryTool: AgentTool {
    let definition = ToolDefinition(
        name: "list_directory",
        description: """
            List files and folders in a directory. Paths must stay inside the active sandbox \
            (home ~/ in General, or the focused project root). Relative paths resolve against the project root when focused. \
            In a project, omit `path` (or pass ".") to list the project root. \
            Symlinks that resolve outside the sandbox are skipped. \
            Output format: one entry per line as "kind\\tsize\\tpath" (kind is "dir" or "file", size in bytes or "-" for dirs). \
            Recursive listing indents child entries with spaces. Capped at 500 entries. \
            Use depth=1 (default) for a quick overview, increase up to 5 for deeper exploration.
            """,
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty(
                    "Directory to list. Optional in a focused project — defaults to the project root."
                ),
                "depth": .intProperty("Recursion depth (1 = immediate children only, default 1, max 5)"),
                "include_hidden": .boolProperty("Include hidden files/directories. Default false."),
            ],
            required: []
        )
    )

    private struct Args: Decodable {
        let path: String?
        let depth: Int?
        let includeHidden: FlexibleBool?
    }

    private static let maxEntries = 500

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let effectivePath = try PathGuard.defaultExplorationPath(args.path)
        let url = try PathGuard.resolveAllowed(effectivePath, access: .read)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolError.operationFailed("Directory does not exist: \(effectivePath)")
        }

        // Validate it's actually a directory
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard isDir.boolValue else {
            throw ToolError.operationFailed(
                "Path is a file, not a directory: \(effectivePath). Use read_text_file to read file contents."
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
            if lines.count >= Self.maxEntries {
                truncated = true
                return
            }
            guard let allowed = PathGuard.resolveEnumeratedURL(item, access: .read) else {
                continue
            }
            let values = try? allowed.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory == true
            let kind = isDirectory ? "dir" : "file"
            let size = isDirectory ? "-" : "\(values?.fileSize ?? 0)"
            let indent = String(repeating: "  ", count: currentDepth)
            lines.append("\(indent)\(kind)\t\(size)\t\(PathGuard.displayPath(allowed.path))")
            if isDirectory {
                listRecursive(
                    url: allowed,
                    depth: depth,
                    currentDepth: currentDepth + 1,
                    skipHidden: skipHidden,
                    lines: &lines,
                    truncated: &truncated
                )
            }
        }
    }
}

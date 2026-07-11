//
//  FileTools.swift
//  Sage
//

import Foundation

private func decodeArgs<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw ToolError.invalidArguments("Arguments are not UTF-8")
    }
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw ToolError.invalidArguments(error.localizedDescription)
    }
}

struct ListDirectoryTool: AgentTool {
    let definition = ToolDefinition(
        name: "list_directory",
        description: "List files and folders in a directory under the user's home.",
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Absolute or ~ path to the directory"),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable { let path: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let lines = try items.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { item -> String in
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let kind = values.isDirectory == true ? "dir" : "file"
                let size = values.fileSize.map(String.init) ?? "-"
                return "\(kind)\t\(size)\t\(item.path)"
            }
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }
}

struct MoveFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "move_file",
        description: "Move a file or folder to a new location under the user's home.",
        parameters: .schemaObject(
            properties: [
                "source": .stringProperty("Source path"),
                "destination": .stringProperty("Destination path (file or directory)"),
            ],
            required: ["source", "destination"]
        )
    )

    private struct Args: Decodable {
        let source: String
        let destination: String
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.source)
        var destination = try PathGuard.resolveAllowed(args.destination)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
            destination = destination.appendingPathComponent(source.lastPathComponent)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        return "Moved to \(destination.path)"
    }
}

struct RenameFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "rename_file",
        description: "Rename a file or folder in place under the user's home.",
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Current path"),
                "new_name": .stringProperty("New file or folder name (not a full path)"),
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
        let args = try decodeArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.path)
        let destination = source.deletingLastPathComponent().appendingPathComponent(args.newName)
        _ = try PathGuard.resolveAllowed(destination.path)
        try FileManager.default.moveItem(at: source, to: destination)
        return "Renamed to \(destination.path)"
    }
}

struct CreateDirectoryTool: AgentTool {
    let definition = ToolDefinition(
        name: "create_directory",
        description: "Create a directory (and parents) under the user's home.",
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("Directory path to create"),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable { let path: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "Created \(url.path)"
    }
}

struct ReadTextFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "read_text_file",
        description: "Read a UTF-8 text file under the user's home (max ~100KB).",
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("File path"),
            ],
            required: ["path"]
        )
    )

    private struct Args: Decodable { let path: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        let data = try Data(contentsOf: url)
        guard data.count <= 100_000 else {
            throw ToolError.operationFailed("File too large to read in MVP (\(data.count) bytes)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.operationFailed("File is not valid UTF-8 text")
        }
        return text
    }
}

struct WriteTextFileTool: AgentTool {
    let definition = ToolDefinition(
        name: "write_text_file",
        description: "Write UTF-8 text to a file under the user's home. Creates parent folders.",
        parameters: .schemaObject(
            properties: [
                "path": .stringProperty("File path"),
                "content": .stringProperty("Full file contents"),
            ],
            required: ["path", "content"]
        )
    )

    private struct Args: Decodable {
        let path: String
        let content: String
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeArgs(argumentsJSON, as: Args.self)
        let url = try PathGuard.resolveAllowed(args.path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try args.content.write(to: url, atomically: true, encoding: .utf8)
        return "Wrote \(url.path) (\(args.content.utf8.count) bytes)"
    }
}

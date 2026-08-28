//
//  MoveRenameCopyFileTools.swift
//  Sage
//

import Foundation

nonisolated struct MoveFileTool: AgentTool {
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

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.source)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ToolError.operationFailed(
                "Source does not exist: \(args.source). Use list_directory to verify the path."
            )
        }
        let destination = try FileTransferDestination.prepare(
            source: source,
            destination: try PathGuard.resolveAllowed(args.destination)
        )
        try SafeFileIO.moveItem(at: source, to: destination)
        return "[OK] Moved to \(PathGuard.displayPath(destination.path))"
    }
}

nonisolated struct RenameFileTool: AgentTool {
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
    }

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ToolError.operationFailed(
                "File does not exist: \(args.path). Use list_directory to verify the path."
            )
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(args.newName)
        _ = try PathGuard.resolveAllowed(destination.path)
        try SafeFileIO.moveItem(at: source, to: destination)
        return "[OK] Renamed to \(PathGuard.displayPath(destination.path))"
    }
}

nonisolated struct CopyFileTool: AgentTool {
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

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let source = try PathGuard.resolveAllowed(args.source)
        let destination = try PathGuard.resolveAllowed(args.destination)

        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ToolError.operationFailed(
                "Source does not exist: \(args.source). Use list_directory to verify the path."
            )
        }

        let finalDestination = try FileTransferDestination.prepare(
            source: source,
            destination: destination
        )
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        if values.isRegularFile == true {
            try SafeFileIO.copyRegularFile(at: source, to: finalDestination)
        } else {
            // Directory trees are revalidated per enumerated child by their
            // dedicated copy implementation in a future hardening pass.
            try FileManager.default.copyItem(at: source, to: finalDestination)
        }
        return "[OK] Copied to \(PathGuard.displayPath(finalDestination.path))"
    }
}

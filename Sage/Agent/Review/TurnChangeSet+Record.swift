//
//  TurnChangeSet+Record.swift
//  Sage
//

import Foundation

enum TurnChangeSetRecording {
    private static let fileTools: Set<String> = [
        "write_text_file",
        "delete_file",
        "move_file",
        "rename_file",
        "copy_file",
        "create_directory",
    ]

    static func apply(
        toolName: String,
        argumentsJSON: String,
        result: String,
        succeeded: Bool = true,
        to book: inout WorkspaceChangeBook
    ) {
        if fileTools.contains(toolName) {
            if succeeded {
                applyFileTool(
                    toolName: toolName,
                    argumentsJSON: argumentsJSON,
                    result: result,
                    to: &book
                )
            } else {
                book.recordAction(toolName: toolName, succeeded: false)
            }
            return
        }
        guard ToolDefinition.requiresConfirmation(forToolNamed: toolName) else { return }
        book.recordAction(toolName: toolName, succeeded: succeeded)
    }

    private static func applyFileTool(
        toolName: String,
        argumentsJSON: String,
        result: String,
        to book: inout WorkspaceChangeBook
    ) {
        switch toolName {
        case "write_text_file":
            applyWrite(result: result, to: &book)

        case "delete_file":
            applyDelete(argumentsJSON: argumentsJSON, result: result, to: &book)

        case "move_file", "rename_file":
            applyMove(toolName: toolName, argumentsJSON: argumentsJSON, result: result, to: &book)

        case "copy_file":
            if let path = displayPath(from: result, prefix: "[OK] Copied to ") {
                book.applyCopied(path: path)
            }

        case "create_directory":
            if let path = displayPath(from: result, prefix: "[OK] Created ") {
                book.applyDirectory(path: path)
            }

        default:
            break
        }
    }

    private static func applyWrite(result: String, to book: inout WorkspaceChangeBook) {
        guard let payload = WriteFileResultCodec.payload(in: result) else { return }
        book.applyWrite(
            path: payload.path,
            before: payload.before,
            after: payload.after,
            created: payload.created
        )
    }

    private static func applyDelete(
        argumentsJSON: String,
        result: String,
        to book: inout WorkspaceChangeBook
    ) {
        let path = displayPath(from: result, prefix: "[OK] Deleted ")
            ?? ToolCallPresentation.extractArg(argumentsJSON, key: "path")
        guard let path else { return }
        book.applyDelete(path: path)
    }

    private static func applyMove(
        toolName: String,
        argumentsJSON: String,
        result: String,
        to book: inout WorkspaceChangeBook
    ) {
        let sourceKey = toolName == "rename_file" ? "path" : "source"
        guard let rawSource = ToolCallPresentation.extractArg(argumentsJSON, key: sourceKey) else {
            return
        }
        let source = PathGuard.displayPath(rawSource)
        let prefix = toolName == "rename_file" ? "[OK] Renamed to " : "[OK] Moved to "
        let destination = displayPath(from: result, prefix: prefix)
        guard let destination, source != destination else { return }
        book.applyMove(from: source, to: destination)
    }

    private static func displayPath(from result: String, prefix: String) -> String? {
        guard result.hasPrefix(prefix) else { return nil }
        let path = String(result.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

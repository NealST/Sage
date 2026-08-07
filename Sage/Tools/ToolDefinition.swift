//
//  ToolDefinition.swift
//  Sage
//

import Foundation

struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
}

protocol AgentTool: Sendable {
    var definition: ToolDefinition { get }
    func call(argumentsJSON: String) async throws -> String
}

enum ToolError: LocalizedError {
    case invalidArguments(String)
    case pathNotAllowed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let detail):
            return "Invalid arguments: \(detail)"
        case .pathNotAllowed(let path):
            return "Path not allowed: \(path). Only paths under the user's home directory (~/) are accessible."
        case .operationFailed(let detail):
            return detail
        }
    }
}

enum PathGuard {
    /// Cached resolved home path to avoid repeated symlink resolution on every call.
    private static let resolvedHomePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.resolvingSymlinksInPath().path
    }()

    /// Only allow paths whose resolved physical location is under the user's home directory.
    /// Resolves symlinks to prevent escaping the home sandbox via symbolic links.
    static func resolveAllowed(_ raw: String) throws -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        // Resolve symlinks to get the true physical path
        let resolved = url.resolvingSymlinksInPath()
        let path = resolved.path
        guard path == resolvedHomePath || path.hasPrefix(resolvedHomePath + "/") else {
            throw ToolError.pathNotAllowed(raw)
        }
        return url
    }
}

/// Shared argument decoder for all tools.
/// Uses `.convertFromSnakeCase` so tool Args structs can use camelCase properties
/// without manually defining CodingKeys for every snake_case JSON parameter.
func decodeToolArgs<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw ToolError.invalidArguments("Arguments are not UTF-8")
    }
    do {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    } catch {
        throw ToolError.invalidArguments(error.localizedDescription)
    }
}

/// Maximum characters a tool result may return before truncation.
private let toolResultMaxChars = 50_000

/// Truncates a tool result string if it exceeds the global cap.
func capToolResult(_ result: String) -> String {
    guard result.count > toolResultMaxChars else { return result }
    return String(result.prefix(toolResultMaxChars)) + "\n… (result truncated at \(toolResultMaxChars) characters)"
}

/// Default timeout for tool execution (30 seconds).
let toolExecutionTimeout: Duration = .seconds(30)

struct ToolRegistry: Sendable {
    private let tools: [String: any AgentTool]

    init(tools: [any AgentTool]) {
        var map: [String: any AgentTool] = [:]
        for tool in tools {
            map[tool.definition.name] = tool
        }
        self.tools = map
    }

    var definitions: [ToolDefinition] {
        tools.values.map(\.definition).sorted { $0.name < $1.name }
    }

    func tool(named name: String) -> (any AgentTool)? {
        tools[name]
    }

    static func makeDefault() -> ToolRegistry {
        ToolRegistry(tools: [
            // File operations
            ListDirectoryTool(),
            SearchFilesTool(),
            ReadTextFileTool(),
            WriteTextFileTool(),
            MoveFileTool(),
            CopyFileTool(),
            RenameFileTool(),
            DeleteFileTool(),
            CreateDirectoryTool(),
            // Shell
            RunShellCommandTool(),
            // Clipboard
            GetClipboardTool(),
            SetClipboardTool(),
            // Accessibility
            GetSelectedTextTool(),
            TypeTextTool(),
            GetFrontmostAppTool(),
            GetScreenInfoTool(),
            // System
            OpenApplicationTool(),
            OpenURLTool(),
            NotifyTool(),
            GetSystemVolumeTool(),
            SetSystemVolumeTool(),
            ToggleAppearanceTool(),
            CreateReminderTool(),
            TakeScreenshotTool(),
        ])
    }
}

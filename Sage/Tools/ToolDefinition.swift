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
        case .invalidArguments(let detail): return "Invalid arguments: \(detail)"
        case .pathNotAllowed(let path): return "Path not allowed: \(path)"
        case .operationFailed(let detail): return detail
        }
    }
}

enum PathGuard {
    /// Only allow paths under the user's home directory.
    static func resolveAllowed(_ raw: String) throws -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let homePath = home.path
        let path = url.path
        guard path == homePath || path.hasPrefix(homePath + "/") else {
            throw ToolError.pathNotAllowed(raw)
        }
        return url
    }
}

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
            ListDirectoryTool(),
            MoveFileTool(),
            RenameFileTool(),
            CreateDirectoryTool(),
            ReadTextFileTool(),
            WriteTextFileTool(),
            GetClipboardTool(),
            SetClipboardTool(),
            OpenApplicationTool(),
            OpenURLTool(),
            NotifyTool(),
        ])
    }
}

//
//  ToolDefinition.swift
//  Sage
//

import Foundation

nonisolated struct ToolDefinition: Sendable {
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
    case pathNotAllowed(String, policy: PathGuard.Policy)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let detail):
            return "Invalid arguments: \(detail)"
        case .pathNotAllowed(let path, let policy):
            return "Path not allowed: \(path). \(policy.boundaryDescription)"
        case .operationFailed(let detail):
            return detail
        }
    }
}

enum PathGuard: Sendable {
    /// Active sandbox for the current tool call (set by AgentRuntime via TaskLocal).
    @TaskLocal
    static var policy: Policy = .home

    /// Sandbox policy for file/shell path resolution.
    enum Policy: Sendable, Equatable {
        /// General mode — paths must resolve under the user's home directory.
        case home
        /// Project mode — paths must resolve under `root` (and still under home).
        case project(root: URL)

        var boundaryDescription: String {
            switch self {
            case .home:
                return "Only paths under the user's home directory (~/) are accessible."
            case .project(let root):
                return "Only paths under the active project root (\(root.path)) are accessible."
            }
        }

        var defaultWorkingDirectory: URL {
            switch self {
            case .home:
                return FileManager.default.homeDirectoryForCurrentUser
            case .project(let root):
                return root
            }
        }
    }

    /// Cached resolved home path to avoid repeated symlink resolution on every call.
    private static let resolvedHomePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.resolvingSymlinksInPath().path
    }()

    /// Resolve and validate a path under the current `TaskLocal` policy.
    nonisolated static func resolveAllowed(_ raw: String) throws -> URL {
        try resolveAllowed(raw, policy: policy)
    }

    /// Resolve and validate a path under an explicit policy.
    nonisolated static func resolveAllowed(_ raw: String, policy: Policy) throws -> URL {
        let candidate = try makeCandidateURL(raw, policy: policy)
        let resolved = candidate.resolvingSymlinksInPath()
        let path = resolved.path

        guard isInsideHome(path) else {
            throw ToolError.pathNotAllowed(raw, policy: policy)
        }

        switch policy {
        case .home:
            // Return the resolved URL so symlink escapes cannot write outside ~.
            return resolved
        case .project(let root):
            let rootPath = root.resolvingSymlinksInPath().path
            guard path == rootPath || path.hasPrefix(rootPath + "/") else {
                throw ToolError.pathNotAllowed(raw, policy: policy)
            }
            return resolved
        }
    }

    /// Validate a directory as a project root (exists, directory, under ~).
    /// Returns the standardized absolute path string used as `ProjectRecord.rootPath`.
    @discardableResult
    nonisolated static func validateProjectRoot(_ url: URL) throws -> URL {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            throw ToolError.operationFailed(
                "Project root must be an existing directory: \(url.path)"
            )
        }
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        guard isInsideHome(resolved.path) else {
            throw ToolError.pathNotAllowed(url.path, policy: .home)
        }
        return resolved
    }

    // MARK: - Internals

    nonisolated private static func makeCandidateURL(_ raw: String, policy: Policy) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidArguments("Path cannot be empty.")
        }

        switch policy {
        case .home:
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        case .project(let root):
            if trimmed.hasPrefix("~") || trimmed.hasPrefix("/") {
                let expanded = (trimmed as NSString).expandingTildeInPath
                return URL(fileURLWithPath: expanded).standardizedFileURL
            }
            // Relative paths anchor at the project root.
            return root.appendingPathComponent(trimmed).standardizedFileURL
        }
    }

    nonisolated private static func isInsideHome(_ resolvedPath: String) -> Bool {
        resolvedPath == resolvedHomePath || resolvedPath.hasPrefix(resolvedHomePath + "/")
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

/// Accepts JSON booleans, 0/1 integers, and common string forms (`"true"` / `"1"`).
/// Models frequently emit any of these for flag-like tool parameters.
nonisolated struct FlexibleBool: Decodable, Sendable, Equatable {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            value = int != 0
            return
        }
        if let double = try? container.decode(Double.self) {
            value = double != 0
            return
        }
        if let string = try? container.decode(String.self) {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "y":
                value = true
                return
            case "false", "0", "no", "n":
                value = false
                return
            default:
                break
            }
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected boolean, integer 0/1, or true/false string"
            )
        )
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
            ListDirectoryTool(),
            MoveFileTool(),
            RenameFileTool(),
            CreateDirectoryTool(),
            DeleteFileTool(),
            CopyFileTool(),
            ReadTextFileTool(),
            WriteTextFileTool(),
            SearchFilesTool(),
            RunShellCommandTool(),
            GetClipboardTool(),
            SetClipboardTool(),
            GetSelectedTextTool(),
            TypeTextTool(),
            GetScreenInfoTool(),
            GetFrontmostAppTool(),
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

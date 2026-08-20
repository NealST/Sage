//
//  ToolDefinition.swift
//  Sage
//

import Foundation

nonisolated struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
    /// When false, the runtime may run the tool in a ReAct loop without a plan card.
    let requiresConfirmation: Bool

    nonisolated init(
        name: String,
        description: String,
        parameters: JSONValue,
        requiresConfirmation: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.requiresConfirmation = requiresConfirmation
            ?? !Self.observationToolNames.contains(name)
    }

    /// Reads and context loads only — no lasting change to the user's Mac.
    nonisolated static let observationToolNames: Set<String> = [
        "list_directory",
        "read_text_file",
        "search_files",
        "get_clipboard",
        "get_selected_text",
        "get_screen_info",
        "get_frontmost_app",
        "get_system_volume",
        "load_skill",
        "load_skill_resource",
        "recall_task_transcript",
        "manage_todo_list",
        "explore_subagent",
    ]

    nonisolated static func requiresConfirmation(forToolNamed name: String) -> Bool {
        if MCPToolGroupTool.isGroupTool(name) { return false }
        return !observationToolNames.contains(name)
    }
}

nonisolated protocol AgentTool: Sendable {
    var definition: ToolDefinition { get }
    func call(argumentsJSON: String) async throws -> String
}

nonisolated enum ToolError: LocalizedError {
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

nonisolated enum PathGuard: Sendable {
    /// Active sandbox for the current tool call (set by AgentRuntime via TaskLocal).
    @TaskLocal
    static var policy: Policy = .home

    /// Additional **read-only** paths beyond the primary policy (e.g. activated skill dirs).
    /// Never consulted for write / mutate / shell-cwd resolution.
    @TaskLocal
    static var readAllowlist: [String] = []

    /// Whether a path is being resolved for reading or for mutation / cwd.
    enum Access: Sendable, Equatable {
        case read
        case write
    }

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

    /// Resolve under the current `TaskLocal` policy.
    /// Defaults to `.write` so allowlisted skill dirs cannot be mutated by accident.
    nonisolated static func resolveAllowed(
        _ raw: String,
        access: Access = .write
    ) throws -> URL {
        try resolveAllowed(raw, policy: policy, access: access)
    }

    /// Resolve under an explicit policy.
    nonisolated static func resolveAllowed(
        _ raw: String,
        policy: Policy,
        access: Access = .write
    ) throws -> URL {
        let candidate = try makeCandidateURL(raw, policy: policy)
        let resolved = candidate.resolvingSymlinksInPath()
        let path = resolved.path

        guard isInsideHome(path) else {
            throw ToolError.pathNotAllowed(raw, policy: policy)
        }

        switch policy {
        case .home:
            return resolved
        case .project(let root):
            let rootPath = root.resolvingSymlinksInPath().path
            if path == rootPath || path.hasPrefix(rootPath + "/") {
                return resolved
            }
            // Skill directories (and similar) are read-only extras — never for writes/shell cwd.
            if access == .read, isInReadAllowlist(path) {
                return resolved
            }
            throw ToolError.pathNotAllowed(raw, policy: policy)
        }
    }

    /// Resolved URL when `url` stays inside the current sandbox for `access`.
    /// Directory walks use this so symlink targets outside the project or home are skipped.
    nonisolated static func resolveEnumeratedURL(_ url: URL, access: Access = .read) -> URL? {
        try? resolveAllowed(url.path, access: access)
    }

    /// Check if a resolved path falls under any read-allowlisted directory.
    nonisolated private static func isInReadAllowlist(_ resolvedPath: String) -> Bool {
        for allowed in readAllowlist {
            if resolvedPath == allowed || resolvedPath.hasPrefix(allowed + "/") {
                return true
            }
        }
        return false
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

    /// Formats a filesystem path for tool results and UI.
    /// - Project: relative to root when inside (`.` for the root itself); otherwise tilde / absolute.
    /// - Home: tilde-shortened under `~`; otherwise absolute.
    nonisolated static func displayPath(_ path: String, policy: Policy = policy) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded: String
        switch policy {
        case .project(let root) where !trimmed.hasPrefix("~") && !trimmed.hasPrefix("/"):
            expanded = root.appendingPathComponent(trimmed).path
        default:
            expanded = (trimmed as NSString).expandingTildeInPath
        }
        let resolved = URL(fileURLWithPath: expanded)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        switch policy {
        case .project(let root):
            let rootPath = root.resolvingSymlinksInPath().path
            if resolved == rootPath { return "." }
            if resolved.hasPrefix(rootPath + "/") {
                return String(resolved.dropFirst(rootPath.count + 1))
            }
            return homeDisplayPath(resolved)
        case .home:
            return homeDisplayPath(resolved)
        }
    }

    /// Resolves a display path (project-relative, `~/…`, or absolute) for Finder / Quick Look.
    nonisolated static func fileURL(forDisplayPath path: String, policy: Policy = policy) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = try? resolveAllowed(trimmed, policy: policy, access: .read) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    nonisolated private static func homeDisplayPath(_ absolute: String) -> String {
        if absolute == resolvedHomePath { return "~" }
        if absolute.hasPrefix(resolvedHomePath + "/") {
            return "~" + absolute.dropFirst(resolvedHomePath.count)
        }
        return absolute
    }

    /// Resolves an optional exploration path: project mode may omit/`""` → `"."` (project root);
    /// General mode still requires an explicit path.
    nonisolated static func defaultExplorationPath(_ raw: String?) throws -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        switch policy {
        case .project:
            return "."
        case .home:
            throw ToolError.invalidArguments(
                "path is required in General mode. Pass an absolute or ~/ path."
            )
        }
    }
}

/// Shared argument decoder for all tools.
/// Uses `.convertFromSnakeCase` so tool Args structs can use camelCase properties
/// without manually defining CodingKeys for every snake_case JSON parameter.
///
/// Do not map `CodingKeys` back to the original snake_case names (`line_start`).
/// After conversion the decoder looks up `lineStart`; `lineStart = "line_start"`
/// silently drops the field. `*ID` properties are the exception: conversion yields
/// `fromEventId`, not `fromEventID`, so those keys must be `"fromEventId"`.
nonisolated func decodeToolArgs<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
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
nonisolated private let toolResultMaxChars = 50_000

/// Truncates a tool result string if it exceeds the global cap.
nonisolated func capToolResult(_ result: String) -> String {
    guard result.count > toolResultMaxChars else { return result }
    return String(result.prefix(toolResultMaxChars)) + "\n… (result truncated at \(toolResultMaxChars) characters)"
}

/// Default timeout for tool execution (30 seconds).
nonisolated let toolExecutionTimeout: Duration = .seconds(30)

nonisolated struct ToolRegistry: Sendable {
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

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
    @TaskLocal static var policy: Policy = .home

    /// Additional **read-only** paths beyond the primary policy (e.g. activated skill dirs).
    /// Never consulted for write / mutate / shell-cwd resolution.
    @TaskLocal static var readAllowlist: [String] = []

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
    static let resolvedHomePath: String = {
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
}

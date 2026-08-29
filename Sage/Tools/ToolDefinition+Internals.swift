//
//  ToolDefinition+Internals.swift
//  Sage
//

import Foundation

extension PathGuard {
    // MARK: - Internals

    nonisolated static func makeCandidateURL(_ raw: String, policy: Policy) throws -> URL {
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

    nonisolated static func isInsideHome(_ resolvedPath: String) -> Bool {
        resolvedPath == resolvedHomePath || resolvedPath.hasPrefix(resolvedHomePath + "/")
    }

    nonisolated static func assertSensitiveReadAllowed(_ url: URL) throws {
        guard isSensitiveReadAllowed(url) else {
            throw ToolError.operationFailed(
                "Reading this protected location requires sensitive-read authorization."
            )
        }
    }

    nonisolated static func isSensitiveReadAllowed(_ url: URL) -> Bool {
        guard let protectedRoot = SensitiveResourcePolicy.containingRoot(for: url) else {
            return true
        }
        let protectedPath = protectedRoot.standardizedFileURL.resolvingSymlinksInPath().path
        return sensitiveReadAllowlist.contains { authorizedRoot in
            protectedPath == authorizedRoot || protectedPath.hasPrefix(authorizedRoot + "/")
        }
    }

    nonisolated static func assertWriteAllowed(_ url: URL) throws {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let allowed = writeAllowlist.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
        guard allowed else {
            throw ToolError.operationFailed(
                "The resolved destination is outside this invocation's authorized write scope."
            )
        }
    }

    nonisolated static func isProtectedWritePath(_ resolvedPath: String, policy: Policy) -> Bool {
        let protectedNames = [".git", ".sage", ".agents"]
        let components = URL(fileURLWithPath: resolvedPath).standardizedFileURL.pathComponents
        return protectedNames.contains { components.contains($0) }
            && isInsidePolicy(resolvedPath, policy: policy)
    }

    private static func isInsidePolicy(_ path: String, policy: Policy) -> Bool {
        switch policy {
        case .home:
            return isInsideHome(path)

        case .project(let root):
            let rootPath = root.resolvingSymlinksInPath().path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
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
    let tools: [String: any AgentTool]

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

    static func makeDefault() -> Self {
        Self(tools: [
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

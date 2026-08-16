//
//  SkillToolExecutor.swift
//  Sage
//
//  Skill tool execution, isolated from AgentRuntime.
//

import Foundation

/// Host surface for skill tool execution (activation, catalog, project scope).
@MainActor
protocol SkillToolHost: AnyObject {
    var activatedSkillNames: Set<String> { get }
    var enabledSkills: [SkillRecord] { get }
    /// All skills including disabled — used for enhance lookup.
    var catalogSkills: [SkillRecord] { get }
    var focusedProjectRoot: URL? { get }
    func broadcastSkillsCatalogChange() async
}

/// Create vs enhance for `save_skill` tool arguments.
nonisolated enum SaveSkillAction: String, Decodable, Sendable {
    case create
    case enhance
}

/// Skill tool execution (schemas live in `SkillToolDefinitions.swift`).
@MainActor
enum SkillToolExecutor {
    nonisolated static func isSkillTool(_ name: String) -> Bool {
        SkillToolPolicy.skillToolNames.contains(name)
    }

    static func execute(name: String, argumentsJSON: String, host: SkillToolHost) async throws -> String {
        switch name {
        case "load_skill":
            return try await executeLoadSkill(argumentsJSON: argumentsJSON, host: host)
        case "load_skill_resource":
            return try await executeLoadSkillResource(argumentsJSON: argumentsJSON, host: host)
        case "run_skill_script":
            return try await executeRunSkillScript(argumentsJSON: argumentsJSON, host: host)
        case "save_skill":
            return try await executeSaveSkill(argumentsJSON: argumentsJSON, host: host)
        default:
            throw ToolError.operationFailed("Unknown skill tool: \(name)")
        }
    }

    /// Builds the structured `<skill_content>` block for a skill record.
    static func buildSkillContent(for skill: SkillRecord) async -> String {
        let body = await SkillRegistry.shared.readBody(for: skill)
        let skillDir = URL(fileURLWithPath: skill.path).deletingLastPathComponent().path
        var content = "<skill_content name=\"\(skill.name)\">\n"
        content += body

        let listing = await SkillRegistry.shared.listResources(for: skill)
        let resources = listing.paths
        let hasScripts = resources.contains { $0.hasPrefix("scripts/") }

        if !resources.isEmpty {
            content += "\n\nSkill directory: \(skillDir)"
            content += "\nUse `load_skill_resource` to read any resource file by relative path."
            if hasScripts {
                content += "\nUse `run_skill_script` to execute scripts in the scripts/ directory."
            }
            content += "\n\n<skill_resources>"
            for resource in resources {
                content += "\n  <file>\(resource)</file>"
            }
            if listing.truncated {
                content += "\n  <note>Resource list truncated; more files exist under the skill directory.</note>"
            }
            content += "\n</skill_resources>"
        } else {
            content += "\n\nSkill directory: \(skillDir)"
        }

        content += "\n</skill_content>"
        return ContextBudget.capSkillContent(content, skillName: skill.name)
    }

    /// Parses `load_skill` tool args for post-commit activation bookkeeping.
    static func loadSkillName(from argumentsJSON: String) -> String? {
        struct Args: Decodable { let name: String }
        return try? decodeToolArgs(argumentsJSON, as: Args.self).name
    }

    /// Safe JSON arguments for auto `load_skill` (handles names with quotes).
    static func loadSkillArgumentsJSON(name: String) -> String {
        let payload: [String: String] = ["name": name]
        if let data = try? JSONEncoder().encode(payload),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"name\":\"\"}"
    }

    /// Computes read-allowlisted directories from activated skills.
    nonisolated static func readAllowlist(activatedSkillNames: Set<String>, enabledSkills: [SkillRecord]) -> [String] {
        guard !activatedSkillNames.isEmpty else { return [] }
        return activatedSkillNames.compactMap { name in
            guard let skill = enabledSkills.first(where: { $0.name == name }) else { return nil }
            return URL(fileURLWithPath: skill.path)
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .path
        }
    }

    // MARK: - Private helpers

    /// Validates a relative path stays inside `skillDir` (normalize slashes, reject `..` /
    /// absolute paths, resolve symlinks, require `hasPrefix` of the skill directory).
    private static func resolvePathWithinSkillDirectory(
        relativePath: String,
        skillDir: URL,
        pathNoun: String,
        escapeMessage: String
    ) throws -> URL {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !normalizedPath.contains("..") else {
            throw ToolError.operationFailed(
                "\(pathNoun) must not contain '..'. Use a relative path within the skill directory."
            )
        }
        guard !normalizedPath.hasPrefix("/") else {
            throw ToolError.operationFailed(
                "\(pathNoun) must be relative to the skill directory, not absolute."
            )
        }

        let fileURL = skillDir.appendingPathComponent(normalizedPath).standardizedFileURL
        let resolvedPath = fileURL.resolvingSymlinksInPath().path
        let resolvedSkillDir = skillDir.resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix(resolvedSkillDir + "/") else {
            throw ToolError.operationFailed(escapeMessage)
        }
        return fileURL
    }

    private static func executeLoadSkill(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable { let name: String }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        // Deduplication: don't re-inject a skill already loaded in this task.
        if host.activatedSkillNames.contains(args.name) {
            return "Skill '\(args.name)' is already loaded in this session. Its instructions are active."
        }

        guard let skill = host.enabledSkills.first(where: { $0.name == args.name }) else {
            throw ToolError.operationFailed(
                "Skill '\(args.name)' not found or not enabled. Available skills: \(host.enabledSkills.map(\.name).joined(separator: ", "))"
            )
        }

        let body = await SkillRegistry.shared.readBody(for: skill)
        guard !body.isEmpty else {
            throw ToolError.operationFailed("Skill '\(args.name)' has no content.")
        }

        // Activation is marked by the caller only after a successful commit, so a failed
        // persist cannot leave "already loaded" with no protected body in the transcript.
        return await buildSkillContent(for: skill)
    }

    private static func executeLoadSkillResource(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable {
            let skillName: String
            let path: String
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        guard host.activatedSkillNames.contains(args.skillName) else {
            throw ToolError.operationFailed(
                "Skill '\(args.skillName)' is not activated in this session. Use load_skill first."
            )
        }

        guard let skill = host.enabledSkills.first(where: { $0.name == args.skillName }) else {
            throw ToolError.operationFailed("Skill '\(args.skillName)' not found.")
        }

        let skillDir = URL(fileURLWithPath: skill.path).deletingLastPathComponent()
        let fileURL = try resolvePathWithinSkillDirectory(
            relativePath: args.path,
            skillDir: skillDir,
            pathNoun: "Path",
            escapeMessage: "Resolved path escapes the skill directory."
        )

        struct ResourceRead: Sendable {
            var exists: Bool
            var fileSize: Int
            var text: String?
        }

        let read = try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return ResourceRead(exists: false, fileSize: 0, text: nil)
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attrs[.size] as? Int) ?? 0
            let data = try Data(contentsOf: fileURL)
            return ResourceRead(
                exists: true,
                fileSize: fileSize,
                text: String(data: data, encoding: .utf8)
            )
        }.value

        guard read.exists else {
            let listing = await SkillRegistry.shared.listResources(for: skill)
            var msg = "File not found: \(args.path)"
            if !listing.paths.isEmpty {
                msg += "\n\nAvailable resources:\n" + listing.paths.map { "  \($0)" }.joined(separator: "\n")
            }
            if listing.truncated {
                msg += "\n  (list truncated; more files may exist)"
            }
            throw ToolError.operationFailed(msg)
        }

        guard let text = read.text else {
            throw ToolError.operationFailed("Resource file is not valid UTF-8 text: \(args.path)")
        }

        var result = ""
        if read.fileSize > 100_000 {
            result += "⚠️ Warning: Resource file is large (\(read.fileSize) bytes). This may consume significant context.\n\n"
        }
        result += "<skill_resource skill=\"\(args.skillName)\" path=\"\(args.path)\">\n\(text)\n</skill_resource>"
        return result
    }

    private static func executeRunSkillScript(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable {
            let skillName: String
            let scriptPath: String
            let arguments: String?
            let interpreter: String?
            let timeoutSeconds: Int?
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        guard host.activatedSkillNames.contains(args.skillName) else {
            throw ToolError.operationFailed(
                "Skill '\(args.skillName)' is not activated in this session. Use load_skill first."
            )
        }

        guard let skill = host.enabledSkills.first(where: { $0.name == args.skillName }) else {
            throw ToolError.operationFailed("Skill '\(args.skillName)' not found.")
        }

        let skillDir = URL(fileURLWithPath: skill.path).deletingLastPathComponent()
        let scriptURL = try resolvePathWithinSkillDirectory(
            relativePath: args.scriptPath,
            skillDir: skillDir,
            pathNoun: "Script path",
            escapeMessage: "Resolved script path escapes the skill directory."
        )

        let scriptExists = await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: scriptURL.path)
        }.value
        guard scriptExists else {
            throw ToolError.operationFailed(
                "Script not found: \(args.scriptPath) in skill '\(args.skillName)'."
            )
        }

        let argv = try scriptArgvTokens(from: args.arguments)
        let timeout = max(args.timeoutSeconds ?? 30, 1)

        // Launch without a shell so arguments cannot inject metacharacters via `zsh -c`.
        let launchExecutable: URL
        let launchArguments: [String]
        if let interpreter = args.interpreter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !interpreter.isEmpty {
            guard !interpreter.contains("/"),
                  !interpreter.contains(".."),
                  interpreter.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
            else {
                throw ToolError.invalidArguments(
                    "Interpreter must be a simple command name (e.g. python3, node, bash)."
                )
            }
            launchExecutable = URL(fileURLWithPath: "/usr/bin/env")
            launchArguments = [interpreter, scriptURL.path] + argv
        } else {
            // Ensure executable permission (file I/O off MainActor).
            try await Task.detached(priority: .utility) {
                let attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
                let perms = (attrs[.posixPermissions] as? Int) ?? 0
                if perms & 0o111 == 0 {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: perms | 0o755],
                        ofItemAtPath: scriptURL.path
                    )
                }
            }.value
            launchExecutable = scriptURL
            launchArguments = argv
        }

        let run = try await ProcessRunner.run(
            executable: launchExecutable,
            arguments: launchArguments,
            currentDirectory: skillDir,
            timeout: .seconds(timeout)
        )

        var result = ""
        if run.timedOut {
            result += "⚠️ Script terminated: exceeded timeout of \(timeout)s.\n"
        }
        result += "[exit \(run.exitCode)]\n"
        if run.output.utf8.count > 50_000 {
            result += "⚠️ Warning: Script output is large (\(run.output.utf8.count) bytes). This may consume significant context.\n\n"
        }
        result += run.output
        return result
    }

    /// Splits script arguments into argv tokens without shell expansion.
    private static func scriptArgvTokens(from raw: String?) throws -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }

        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for char in raw {
            switch char {
            case "\"":
                inQuotes.toggle()
            case " " where !inQuotes:
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            default:
                current.append(char)
            }
        }
        if inQuotes {
            throw ToolError.invalidArguments("Unclosed quote in script arguments.")
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        let forbidden = CharacterSet(charactersIn: ";|&$`\n\r")
        for token in tokens {
            if token.rangeOfCharacter(from: forbidden) != nil {
                throw ToolError.operationFailed(
                    "Blocked: script arguments contain shell metacharacters."
                )
            }
        }
        return tokens
    }

    private static func executeSaveSkill(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable {
            let action: SaveSkillAction
            let name: String
            let description: String
            let body: String
            let scope: SkillScope?
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        // Validate description length (spec: max 1024 chars).
        guard args.description.count <= 1024 else {
            throw ToolError.invalidArguments(
                "Description exceeds 1024 characters (\(args.description.count)). Shorten it."
            )
        }

        // Validate body is not excessively large.
        let bodyLines = args.body.components(separatedBy: "\n").count
        if bodyLines > 600 {
            throw ToolError.invalidArguments(
                "Body has \(bodyLines) lines — exceeds the recommended 500-line limit. "
                + "Move detailed reference material to separate files in references/."
            )
        }

        switch args.action {
        case .create:
            let scope = try resolveSaveSkillScope(args.scope, host: host)
            if host.catalogSkills.contains(where: { $0.name == args.name }) {
                throw ToolError.operationFailed(
                    "Skill '\(args.name)' already exists in this workspace. Use action 'enhance' instead."
                )
            }
            let path = try await SkillWriter.createSkill(
                name: args.name,
                description: args.description,
                body: args.body,
                scope: scope,
                projectRoot: host.focusedProjectRoot
            )
            await host.broadcastSkillsCatalogChange()
            return "[OK] Created \(scope.catalogLabel) skill '\(args.name)' at \(path)"

        case .enhance:
            guard let existing = host.catalogSkills.first(where: { $0.name == args.name }) else {
                let available = host.enabledSkills.map(\.name).joined(separator: ", ")
                throw ToolError.operationFailed(
                    "Skill '\(args.name)' not found. Available skills: \(available.isEmpty ? "none" : available)"
                )
            }
            let path = try await SkillWriter.enhanceSkill(
                existingRecord: existing,
                description: args.description,
                body: args.body
            )
            await host.broadcastSkillsCatalogChange()
            return "[OK] Enhanced \(existing.scope.catalogLabel) skill '\(args.name)' at \(path)"
        }
    }

    /// Resolves create scope the same way as the banner: project when focused (unless
    /// explicitly global), otherwise global only.
    private static func resolveSaveSkillScope(_ scope: SkillScope?, host: SkillToolHost) throws -> SkillScope {
        switch scope {
        case nil:
            return host.focusedProjectRoot != nil ? .project : .global
        case .project:
            guard host.focusedProjectRoot != nil else {
                throw ToolError.invalidArguments(
                    "scope 'project' requires a focused project. Use 'global', or open a project first."
                )
            }
            return .project
        case .global:
            return .global
        }
    }
}

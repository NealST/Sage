//
//  SkillToolExecutor+Helpers.swift
//  Sage
//

import Foundation

extension SkillToolExecutor {
    // MARK: - Private helpers

    /// Validates a relative path stays inside `skillDir` (normalize slashes, reject `..` /
    /// absolute paths, resolve symlinks, require `hasPrefix` of the skill directory).
    static func resolvePathWithinSkillDirectory(
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

    static func executeLoadSkill(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable {
            let name: String
            let mode: String?
            let task: String?
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        // Deduplication: don't re-inject a skill already loaded in this task.
        if args.mode != "fork", host.activatedSkillNames.contains(args.name) {
            return "Skill '\(args.name)' is already loaded in this session. Its instructions are active."
        }

        guard let skill = host.enabledSkills.first(where: { $0.name == args.name }) else {
            throw ToolError.operationFailed(
                """
                Skill '\(args.name)' not found or not enabled. \
                Available skills: \(host.enabledSkills.map(\.name).joined(separator: ", "))
                """
            )
        }

        let body = await SkillRegistry.shared.readBody(for: skill)
        guard !body.isEmpty else {
            throw ToolError.operationFailed("Skill '\(args.name)' has no content.")
        }

        if args.mode == "fork" {
            let task = args.task?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            guard let task else {
                throw ToolError.invalidArguments("task is required when load_skill mode is 'fork'.")
            }
            let instructions = await buildSkillContent(for: skill)
            return try await host.runExploreSubagent(
                task: task,
                context: "Use skill '\(skill.name)' for this investigation.",
                instructions: instructions,
                activatedSkillNames: [skill.name]
            )
        }

        // Activation is marked by the caller only after a successful commit, so a failed
        // persist cannot leave "already loaded" with no protected body in the transcript.
        return await buildSkillContent(for: skill)
    }

    static func executeLoadSkillResource(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable {
            let skillName: String
            let path: String
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let skill = try requireActivatedSkill(named: args.skillName, host: host)
        let skillDir = URL(fileURLWithPath: skill.path).deletingLastPathComponent()
        let fileURL = try resolvePathWithinSkillDirectory(
            relativePath: args.path,
            skillDir: skillDir,
            pathNoun: "Path",
            escapeMessage: "Resolved path escapes the skill directory."
        )
        let read = try await readSkillResource(at: fileURL)
        guard read.exists else {
            throw ToolError.operationFailed(await missingResourceMessage(args.path, skill: skill))
        }
        guard let text = read.text else {
            throw ToolError.operationFailed("Resource file is not valid UTF-8 text: \(args.path)")
        }
        var result = ""
        if read.fileSize > 100_000 {
            result += """
            ⚠️ Warning: Resource file is large (\(read.fileSize) bytes). \
            This may consume significant context.\n\n
            """
        }
        result += "<skill_resource skill=\"\(args.skillName)\" path=\"\(args.path)\">\n\(text)\n</skill_resource>"
        return result
    }

    static func requireActivatedSkill(named name: String, host: SkillToolHost) throws -> SkillRecord {
        guard host.activatedSkillNames.contains(name) else {
            throw ToolError.operationFailed(
                "Skill '\(name)' is not activated in this session. Use load_skill first."
            )
        }
        guard let skill = host.enabledSkills.first(where: { $0.name == name }) else {
            throw ToolError.operationFailed("Skill '\(name)' not found.")
        }
        return skill
    }

    struct ResourceRead: Sendable {
        var exists: Bool
        var fileSize: Int
        var text: String?
    }

    static func readSkillResource(at fileURL: URL) async throws -> ResourceRead {
        try await Task.detached(priority: .utility) {
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
    }

    static func missingResourceMessage(_ path: String, skill: SkillRecord) async -> String {
        let listing = await SkillRegistry.shared.listResources(for: skill)
        var msg = "File not found: \(path)"
        if !listing.paths.isEmpty {
            msg += "\n\nAvailable resources:\n" + listing.paths.map { "  \($0)" }.joined(separator: "\n")
        }
        if listing.truncated {
            msg += "\n  (list truncated; more files may exist)"
        }
        return msg
    }

    static func executeRunSkillScript(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        struct Args: Decodable {
            let skillName: String
            let scriptPath: String
            let arguments: String?
            let interpreter: String?
            let timeoutSeconds: Int?
        }
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let skill = try requireActivatedSkill(named: args.skillName, host: host)
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
        let launch = try await scriptLaunch(scriptURL: scriptURL, interpreter: args.interpreter, argv: argv)
        let secretEnvironment = try SkillSecretStore.environment(for: skill)
        let configuration = ExecutionSandboxConfiguration.skillScript(
            policy: PathGuard.policy,
            skillDirectory: skillDir
        )
        let invocation = ExecutionSandbox.wrap(
            executable: launch.executable,
            arguments: launch.arguments,
            configuration: configuration,
            auditComponent: "skill_script"
        )
        let run = try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: skillDir,
            timeout: .seconds(timeout),
            environment: ChildProcessEnvironment.sanitized(overrides: secretEnvironment)
        )
        return formatScriptRun(
            run,
            timeout: timeout,
            secretValues: Array(secretEnvironment.values)
        )
    }

    static func scriptLaunch(
        scriptURL: URL,
        interpreter: String?,
        argv: [String]
    ) async throws -> (executable: URL, arguments: [String]) {
        if let interpreter = interpreter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !interpreter.isEmpty {
            guard !interpreter.contains("/"),
                  !interpreter.contains(".."),
                  interpreter.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
            else {
                throw ToolError.invalidArguments(
                    "Interpreter must be a simple command name (e.g. python3, node, bash)."
                )
            }
            return (URL(fileURLWithPath: "/usr/bin/env"), [interpreter, scriptURL.path] + argv)
        }
        let isExecutable = try await Task.detached(priority: .utility) {
            let attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
            let perms = (attrs[.posixPermissions] as? Int) ?? 0
            return perms & 0o111 != 0
        }.value
        guard isExecutable else {
            throw ToolError.operationFailed(
                "Script is not executable. Provide an interpreter such as bash, python3, or node."
            )
        }
        return (scriptURL, argv)
    }

    static func formatScriptRun(
        _ run: ProcessRunResult,
        timeout: Int,
        secretValues: [String] = []
    ) -> String {
        var result = ""
        if run.timedOut {
            result += "⚠️ Script terminated: exceeded timeout of \(timeout)s.\n"
        }
        result += "[exit \(run.exitCode)]\n"
        if run.output.utf8.count > 50_000 {
            result += """
            ⚠️ Warning: Script output is large (\(run.output.utf8.count) bytes). \
            This may consume significant context.\n\n
            """
        }
        result += Array(Set(secretValues))
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .reduce(run.output) { output, secret in
                output.replacingOccurrences(of: secret, with: "[REDACTED]")
            }
        return result
    }

    /// Splits script arguments into argv tokens without shell expansion.
    static func scriptArgvTokens(from raw: String?) throws -> [String] {
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
        for token in tokens where token.rangeOfCharacter(from: forbidden) != nil {
            throw ToolError.operationFailed(
                "Blocked: script arguments contain shell metacharacters."
            )
        }
        return tokens
    }
}

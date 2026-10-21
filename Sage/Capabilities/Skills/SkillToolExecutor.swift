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
    func executeToolInvocation(name: String, argumentsJSON: String) async throws -> String
    func runExploreSubagent(
        task: String,
        context: String?,
        instructions: String?,
        activatedSkillNames: Set<String>
    ) async throws -> String
    /// Evidence for a child call if this session already approved the same requirement.
    func inheritedAuthorizationEvidence(
        name: String,
        argumentsJSON: String
    ) -> ToolInvocationAuthorizationEvidence?
}

extension SkillToolHost {
    func inheritedAuthorizationEvidence(
        name: String,
        argumentsJSON: String
    ) -> ToolInvocationAuthorizationEvidence? {
        nil
    }
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
    nonisolated static func loadSkillName(from argumentsJSON: String) -> String? {
        struct Args: Decodable {
            let name: String
            let mode: String?
        }
        guard let args = try? decodeToolArgs(argumentsJSON, as: Args.self),
              args.mode != "fork"
        else { return nil }
        return args.name
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
}

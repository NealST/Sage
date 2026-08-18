//
//  SkillToolPolicy.swift
//  Sage
//
//  Enforces frontmatter `allowed-tools` for activated skills.
//

import Foundation

nonisolated enum SkillToolPolicy {
    /// Progressive-disclosure skill tools — always callable when a restriction applies.
    /// `run_skill_script` and `save_skill` must be listed explicitly in `allowed-tools`.
    static let progressiveDisclosureToolNames: Set<String> = [
        "load_skill",
        "load_skill_resource",
    ]

    /// Built-in skill tools (for tests and catalog copy).
    static let skillToolNames: Set<String> = progressiveDisclosureToolNames.union([
        "run_skill_script",
        "save_skill",
    ])

    /// Common frontmatter shorthand → registry tool names.
    private static let aliases: [String: String] = [
        "shell": "run_shell_command",
        "bash": "run_shell_command",
        "sh": "run_shell_command",
        "run_shell": "run_shell_command",
        "read": "read_text_file",
        "read_file": "read_text_file",
        "write": "write_text_file",
        "write_file": "write_text_file",
        "list": "list_directory",
        "ls": "list_directory",
        "search": "search_files",
        "grep": "search_files",
        "find": "search_files",
        "delete": "delete_file",
        "rm": "delete_file",
        "mkdir": "create_directory",
        "clipboard": "get_clipboard",
        "notify": "notify",
    ]

    /// Maps author-facing `allowed-tools` tokens onto registry tool names.
    static func canonicalizeToolName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let key = trimmed.lowercased()
        return aliases[key] ?? trimmed
    }

    /// Union of `allowed-tools` from activated skills that declare a restriction.
    /// Returns `nil` when no activated skill restricts tools.
    static func restrictedToolNames(
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord]
    ) -> Set<String>? {
        let activated = enabledSkills.filter { activatedSkillNames.contains($0.name) }
        let declared = activated.flatMap(\.allowedToolNames)
        guard !declared.isEmpty else { return nil }
        return Set(declared).union(progressiveDisclosureToolNames)
    }

    static func assertToolAllowed(
        _ name: String,
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord]
    ) throws {
        guard let allowed = restrictedToolNames(
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills
        ) else { return }
        guard allowed.contains(name) || name == RecallTaskTranscriptTool.name else {
            throw ToolError.operationFailed(
                "Tool '\(name)' is not permitted by the activated skill allowed-tools list."
            )
        }
    }

    static func filterDefinitions(
        _ definitions: [ToolDefinition],
        activatedSkillNames: Set<String>,
        enabledSkills: [SkillRecord]
    ) -> [ToolDefinition] {
        guard let allowed = restrictedToolNames(
            activatedSkillNames: activatedSkillNames,
            enabledSkills: enabledSkills
        ) else { return definitions }
        return definitions.filter {
            allowed.contains($0.name) || $0.name == RecallTaskTranscriptTool.name
        }
    }
}

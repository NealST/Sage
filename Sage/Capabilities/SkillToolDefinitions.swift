//
//  SkillToolDefinitions.swift
//  Sage
//
//  Skill tool JSON schemas exposed to the model.
//

import Foundation

extension SkillToolExecutor {
    /// Tool definition for `load_skill` — exposed to the cloud model when skills are deferred.
    static let loadSkillDefinition = ToolDefinition(
        name: "load_skill",
        description: "Load a skill's full content by name. Use this when a skill from the Available Skills list is relevant to the user's request. Returns the skill's complete instructions.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("The exact name of the skill to load (from the Available Skills list)."),
                ]),
            ]),
            "required": .array([.string("name")]),
        ])
    )

    /// Tool definition for `load_skill_resource` — available when any skill is activated.
    static let loadSkillResourceDefinition = ToolDefinition(
        name: "load_skill_resource",
        description: """
            Load a reference or resource file from an activated skill's directory. \
            Use this to progressively read documentation, templates, or data files \
            bundled with a skill (e.g. files in references/, assets/). \
            The skill must have been activated via load_skill or a slash command first.
            """,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "skill_name": .object([
                    "type": .string("string"),
                    "description": .string("Name of the activated skill that owns the resource."),
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Relative path to the resource file within the skill directory (e.g. 'references/REFERENCE.md')."),
                ]),
            ]),
            "required": .array([.string("skill_name"), .string("path")]),
        ])
    )

    /// Tool definition for `run_skill_script` — available when any skill is activated.
    static let runSkillScriptDefinition = ToolDefinition(
        name: "run_skill_script",
        description: """
            Execute a script bundled with an activated skill. \
            The script path is relative to the skill's root directory (e.g. 'scripts/extract.py'). \
            Scripts run with the skill directory as working directory. \
            Supports any executable script — specify an interpreter or ensure the script has a shebang.
            """,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "skill_name": .object([
                    "type": .string("string"),
                    "description": .string("Name of the activated skill that owns the script."),
                ]),
                "script_path": .object([
                    "type": .string("string"),
                    "description": .string("Relative path to the script within the skill directory (e.g. 'scripts/extract.py')."),
                ]),
                "arguments": .object([
                    "type": .string("string"),
                    "description": .string("Optional space-separated arguments to pass to the script."),
                ]),
                "interpreter": .object([
                    "type": .string("string"),
                    "description": .string("Optional interpreter (e.g. 'python3', 'node', 'bash'). If omitted, the script is executed directly."),
                ]),
                "timeout_seconds": .object([
                    "type": .string("integer"),
                    "description": .string("Timeout in seconds (default 30). The script is terminated if it exceeds this limit."),
                ]),
            ]),
            "required": .array([.string("skill_name"), .string("script_path")]),
        ])
    )

    /// Tool definition for `save_skill` — allows the agent to create or enhance skills
    /// based on reusable experience identified during conversation.
    static let saveSkillDefinition = ToolDefinition(
        name: "save_skill",
        description: """
            Create a new skill or enhance an existing one to persist reusable experience as long-term memory. \
            Use this when the user explicitly asks to save/remember an experience. \
            Scope matches the product tips: "project" saves under the current project (only used there); \
            "global" saves everywhere. When a project is focused, prefer "project" for project-specific \
            knowledge; when none is focused, only "global" is valid. Enhance keeps the existing skill's location.
            """,
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "description": .string("Whether to create a new skill or enhance an existing one."),
                    "enum": .array([.string("create"), .string("enhance")]),
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Kebab-case skill name (1-64 chars, lowercase alphanumeric and hyphens). For 'enhance', must match an existing skill name."),
                ]),
                "description": .object([
                    "type": .string("string"),
                    "description": .string(SkillAuthoring.descriptionGuidelines),
                ]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string(
                        "Full SKILL.md content in markdown. Follow these guidelines: "
                        + SkillAuthoring.bodyGuidelines
                    ),
                ]),
                "scope": .object([
                    "type": .string("string"),
                    "description": .string("""
                        Where to save a NEW skill. "project" = This Project (current project only). \
                        "global" = Everywhere (all workspaces). Defaults to "project" when a project \
                        is focused, otherwise "global". Ignored for enhance.
                        """),
                    "enum": .array([.string("project"), .string("global")]),
                ]),
            ]),
            "required": .array([.string("action"), .string("name"), .string("description"), .string("body")]),
        ])
    )
}

//
//  ToolAuthorization.swift
//  Sage
//
//  Resource-oriented, just-in-time authorization for tool invocations.
//

import Foundation

nonisolated enum ToolAuthorizationPolicy {
    private static let readToolNames: Set<String> = [
        "list_directory",
        "read_text_file",
        "search_files",
    ]

    private static let writeToolNames: Set<String> = [
        "copy_file",
        "create_directory",
        "delete_file",
        "edit_text_file",
        "move_file",
        "rename_file",
        "write_text_file",
    ]

    static func requirement(
        name: String,
        argumentsJSON: String,
        policy: PathGuard.Policy,
        skills: [SkillRecord] = [],
        mcpTools: [MCPToolInfo] = []
    ) -> ToolAuthorizationRequirement? {
        let arguments = decodeObject(argumentsJSON)
        if readToolNames.contains(name) {
            return sensitiveReadRequirement(name: name, arguments: arguments, policy: policy)
        }
        if writeToolNames.contains(name) {
            return fileWriteRequirement(name: name, arguments: arguments, policy: policy)
        }
        if name == "run_shell_command" {
            return shellRequirement(arguments: arguments, policy: policy)
        }
        if name == "run_skill_script" {
            return skillSecretRequirement(arguments: arguments, skills: skills)
        }
        if name == "save_skill" {
            return saveSkillWriteRequirement(
                arguments: arguments,
                policy: policy,
                skills: skills
            )
        }
        if name.hasPrefix("mcp__"),
           let tool = mcpTools.first(where: { $0.qualifiedName == name }) {
            return mcpRequirement(tool: tool, arguments: arguments, policy: policy)
        }
        return nil
    }

    private static func sensitiveReadRequirement(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement? {
        guard let rawPath = arguments["path"] as? String,
              let url = try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read) else {
            return nil
        }
        let roots: [URL]
        if name == "search_files"
            || name == "list_directory" && (arguments["depth"] as? Int ?? 1) > 1 {
            roots = SensitiveResourcePolicy.intersectingRoots(for: url)
        } else {
            roots = SensitiveResourcePolicy.containingRoot(for: url).map { [$0] } ?? []
        }
        guard !roots.isEmpty else { return nil }
        return ToolAuthorizationRequirement(
            resources: [
                ToolAuthorizationResource(
                    capability: .sensitiveRead,
                    roots: roots.map(normalized).sorted()
                ),
            ],
            principal: "native-file-tools"
        )
    }

    private static func fileWriteRequirement(
        name: String,
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement {
        let resources = fileWriteResources(name: name, arguments: arguments, policy: policy)
        return ToolAuthorizationRequirement(
            resources: resources,
            principal: "native-file-tools"
        )
    }

    private static func shellRequirement(
        arguments: [String: Any],
        policy: PathGuard.Policy
    ) -> ToolAuthorizationRequirement? {
        var resources: [ToolAuthorizationResource] = []
        let rawDirectory = arguments["working_directory"] as? String
        let resolvedDirectory = rawDirectory.flatMap { rawPath in
            try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read)
        }
        let directory = resolvedDirectory ?? policy.defaultWorkingDirectory
        let hasInvalidDirectory = rawDirectory != nil && resolvedDirectory == nil
        if boolValue(arguments["allow_writes"]) {
            resources.append(
                ToolAuthorizationResource(
                    capability: .localWrite,
                    roots: hasInvalidDirectory ? [] : [normalized(directory)]
                )
            )
        }
        if boolValue(arguments["allow_network"]) {
            resources.append(ToolAuthorizationResource(capability: .network, roots: []))
        }
        if boolValue(arguments["allow_protected_metadata_writes"]) {
            resources.append(
                ToolAuthorizationResource(
                    capability: .protectedMetadataWrite,
                    roots: hasInvalidDirectory ? [] : [normalized(directory)]
                )
            )
        }
        if let rawPath = arguments["sensitive_read_path"] as? String,
           let url = try? PathGuard.resolveAllowed(rawPath, policy: policy, access: .read),
           let sensitiveRoot = SensitiveResourcePolicy.containingRoot(for: url) {
            resources.append(
                ToolAuthorizationResource(
                    capability: .sensitiveRead,
                    roots: [normalized(sensitiveRoot)]
                )
            )
        }
        guard !resources.isEmpty else { return nil }
        return ToolAuthorizationRequirement(
            resources: resources,
            principal: "shell"
        )
    }

    private static func skillSecretRequirement(
        arguments: [String: Any],
        skills: [SkillRecord]
    ) -> ToolAuthorizationRequirement? {
        guard let skillName = arguments["skill_name"] as? String,
              let skill = skills.first(where: { $0.name == skillName }),
              let scriptPath = arguments["script_path"] as? String,
              !skill.requiredSecretNames.isEmpty else {
            return nil
        }
        return ToolAuthorizationRequirement(
            resources: [
                ToolAuthorizationResource(
                    capability: .secretUse,
                    roots: skill.requiredSecretNames.sorted()
                ),
            ],
            principal: "skill:\(skill.id):\(skillExecutionFingerprint(skill, scriptPath: scriptPath))"
        )
    }

    private static func saveSkillWriteRequirement(
        arguments: [String: Any],
        policy: PathGuard.Policy,
        skills: [SkillRecord]
    ) -> ToolAuthorizationRequirement {
        let name = arguments["name"] as? String ?? "unknown-skill"
        let action = arguments["action"] as? String
        let root: URL
        if action == "enhance",
           let existing = skills.first(where: { $0.name == name }) {
            root = URL(fileURLWithPath: existing.path).deletingLastPathComponent()
        } else if arguments["scope"] as? String == "global" || isHomePolicy(policy) {
            root = SkillPaths.userSkillsDirectory()
                .appendingPathComponent(name, isDirectory: true)
        } else {
            root = SkillPaths.projectSageSkillsDirectory(
                root: policy.defaultWorkingDirectory
            )
            .appendingPathComponent(name, isDirectory: true)
        }
        return ToolAuthorizationRequirement(
            resources: [
                ToolAuthorizationResource(
                    capability: .localWrite,
                    roots: [normalized(root)]
                ),
            ],
            principal: "skill-writer"
        )
    }

    private static func decodeObject(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        return (value as? NSNumber)?.boolValue ?? false
    }
}

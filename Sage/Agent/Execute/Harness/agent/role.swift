//
//  role.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/role.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Built-in role text and `spawn_tool_spec.build` are faithful.
//  `apply_role_to_config` waits on Config / ConfigLayerStack.
//  Explorer TOML is empty upstream, so locked-settings notes stay empty
//  unless a caller-supplied config file parses a model or effort.
//

import CodexAgentRoles
import CodexProtocol
import Foundation

public let DEFAULT_ROLE_NAME = "default"
let AGENT_TYPE_UNAVAILABLE_ERROR = "agent type is currently not available"

public func applyRoleToConfig(roleName: String?) async throws {
    throw CodexErr.unsupportedOperation(
        "apply_role_to_config waits on Config / ConfigLayerStack"
    )
}

public func resolveRoleConfig(
    roleName: String,
    userDefined: [String: AgentRoleConfig] = [:]
) -> AgentRoleConfig? {
    userDefined[roleName] ?? builtInRoleConfigs()[roleName]
}

public enum SpawnToolSpec {
    public static func build(userDefinedAgentRoles: [String: AgentRoleConfig]) -> String {
        buildFromConfigs(builtInRoles: builtInRoleConfigs(), userDefinedRoles: userDefinedAgentRoles)
    }

    static func buildFromConfigs(
        builtInRoles: [String: AgentRoleConfig],
        userDefinedRoles: [String: AgentRoleConfig]
    ) -> String {
        var seen = Set<String>()
        var formattedRoles: [String] = []
        for (name, declaration) in userDefinedRoles.sorted(by: { $0.key < $1.key }) {
            if seen.insert(name).inserted {
                formattedRoles.append(formatRole(name, declaration))
            }
        }
        for (name, declaration) in builtInRoles.sorted(by: { $0.key < $1.key }) {
            if seen.insert(name).inserted {
                formattedRoles.append(formatRole(name, declaration))
            }
        }
        return "Available roles:\n\(formattedRoles.joined(separator: "\n"))"
    }
}

func formatRole(_ name: String, _ declaration: AgentRoleConfig) -> String {
    guard let description = declaration.description else {
        return "\(name): no description"
    }
    let lockedSettingsNote: String
    if let configFile = declaration.configFile,
       let contents = builtInConfigFileContents(configFile)
        ?? (try? String(contentsOfFile: configFile, encoding: .utf8)),
       let roleToml = try? parseTomlDocument(contents).asTable()
    {
        let model = roleToml["model"]?.asString()
        let reasoningEffort = roleToml["model_reasoning_effort"]?.asString()
        switch (model, reasoningEffort) {
        case let (model?, reasoningEffort?):
            lockedSettingsNote =
                "\n- This role's model is set to `\(model)` and its reasoning effort is set to `\(reasoningEffort)`. These settings cannot be changed."
        case let (model?, nil):
            lockedSettingsNote =
                "\n- This role's model is set to `\(model)` and cannot be changed."
        case let (nil, reasoningEffort?):
            lockedSettingsNote =
                "\n- This role's reasoning effort is set to `\(reasoningEffort)` and cannot be changed."
        case (nil, nil):
            lockedSettingsNote = ""
        }
    } else {
        lockedSettingsNote = ""
    }
    return "\(name): {\n\(description)\(lockedSettingsNote)\n}"
}

func builtInRoleConfigs() -> [String: AgentRoleConfig] {
    [
        DEFAULT_ROLE_NAME: AgentRoleConfig(
            description: "Default agent.",
            configFile: nil,
            nicknameCandidates: nil
        ),
        "explorer": AgentRoleConfig(
            description: """
            Use `explorer` for specific codebase questions.
            Explorers are fast and authoritative.
            They must be used to ask specific, well-scoped questions on the codebase.
            Rules:
            - In order to avoid redundant work, you should avoid exploring the same problem that explorers have already covered. Typically, you should trust the explorer results without additional verification. You are still allowed to inspect the code yourself to gain the needed context!
            - You are encouraged to spawn up multiple explorers in parallel when you have multiple distinct questions to ask about the codebase that can be answered independently. This allows you to get more information faster without waiting for one question to finish before asking the next. While waiting for the explorer results, you can continue working on other local tasks that do not depend on those results. This parallelism is a key advantage of delegation, so use it whenever you have multiple questions to ask.
            - Reuse existing explorers for related questions.
            """,
            configFile: "explorer.toml",
            nicknameCandidates: nil
        ),
        "worker": AgentRoleConfig(
            description: """
            Use for execution and production work.
            Typical tasks:
            - Implement part of a feature
            - Fix tests or bugs
            - Split large refactors into independent chunks
            Rules:
            - Explicitly assign **ownership** of the task (files / responsibility). When the subtask involves code changes, you should clearly specify which files or modules the worker is responsible for. This helps avoid merge conflicts and ensures accountability. For example, you can say "Worker 1 is responsible for updating the authentication module, while Worker 2 will handle the database layer." By defining clear ownership, you can delegate more effectively and reduce coordination overhead.
            - Always tell workers they are **not alone in the codebase**, and they should not revert the edits made by others, and they should adjust their implementation to accommodate the changes made by others. This is important because there may be multiple workers making changes in parallel, and they need to be aware of each other's work to avoid conflicts and ensure a cohesive final product.
            """,
            configFile: nil,
            nicknameCandidates: nil
        ),
    ]
}

func builtInConfigFileContents(_ path: String) -> String? {
    switch path {
    case "explorer.toml":
        return ""
    case "awaiter.toml":
        return ""
    default:
        return nil
    }
}

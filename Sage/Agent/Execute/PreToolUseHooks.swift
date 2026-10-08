//
//  PreToolUseHooks.swift
//  Sage
//
//  HUD allow / ask / deny types. Loading and matching live on `HookRuntime`.
//

import Foundation

nonisolated struct PreToolUseApproval: Sendable, Equatable {
    var reason: String
    var identity: String
}

nonisolated enum PreToolUseDecision: Sendable, Equatable {
    case allow
    case ask(PreToolUseApproval)
    case deny(String)
}

nonisolated struct PreToolUseHookRule: Codable, Sendable, Equatable {
    enum Action: String, Codable, Sendable {
        case allow
        case ask
        case deny
    }

    var tool: String
    var action: Action
    var argumentEquals: [String: String]?
    var argumentContains: [String: String]?
    var reason: String?

    private enum CodingKeys: String, CodingKey {
        case tool, action, reason
        case argumentEquals = "argument_equals"
        case argumentContains = "argument_contains"
    }
}

nonisolated struct PreToolUseHookConfig: Codable, Sendable, Equatable {
    var preToolUse: [PreToolUseHookRule]

    private enum CodingKeys: String, CodingKey {
        case preToolUse = "pre_tool_use"
    }
}

actor PreToolUseHookEvaluator {
    static let shared = PreToolUseHookEvaluator()

    func evaluate(
        toolName: String,
        argumentsJSON: String,
        projectRoot: URL?,
        activatedSkills: [SkillRecord]
    ) -> PreToolUseDecision {
        HookRuntime.preToolUseDecision(
            tool: toolName,
            argumentsJSON: argumentsJSON,
            projectRoot: projectRoot,
            activatedSkills: activatedSkills
        )
    }
}

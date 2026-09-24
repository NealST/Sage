//
//  hook_runtime.swift
//  Sage
//
//  Port of codex-rs/core/src/hook_runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  The same events Codex runs around a turn: session start, prompt submit,
//  pre-tool, permission request, post-tool, stop, compact, session end.
//  Rules live in `.sage/hooks.json`. A deny stops the turn. `continue`
//  injects context. A second Stop hook does not fire while one is active.
//

import Foundation

struct HookRuntimeOutcome: Equatable {
    var shouldStop: Bool
    var additionalContexts: [String]

    static let proceed = HookRuntimeOutcome(shouldStop: false, additionalContexts: [])
}

enum HookEvent: String {
    case sessionStart = "session_start"
    case userPromptSubmit = "user_prompt_submit"
    case preToolUse = "pre_tool_use"
    case permissionRequest = "permission_request"
    case postToolUse = "post_tool_use"
    case stop
    case preCompact = "pre_compact"
    case postCompact = "post_compact"
    case sessionEnd = "session_end"
}

enum HookRuntime {
    private struct Config: Decodable {
        var sessionStart: [Rule]?
        var userPromptSubmit: [Rule]?
        var preToolUse: [Rule]?
        var permissionRequest: [Rule]?
        var postToolUse: [Rule]?
        var stop: [Rule]?
        var preCompact: [Rule]?
        var postCompact: [Rule]?
        var sessionEnd: [Rule]?

        enum CodingKeys: String, CodingKey {
            case sessionStart = "session_start"
            case userPromptSubmit = "user_prompt_submit"
            case preToolUse = "pre_tool_use"
            case permissionRequest = "permission_request"
            case postToolUse = "post_tool_use"
            case stop
            case preCompact = "pre_compact"
            case postCompact = "post_compact"
            case sessionEnd = "session_end"
        }

        func rules(for event: HookEvent) -> [Rule] {
            switch event {
            case .sessionStart: return sessionStart ?? []
            case .userPromptSubmit: return userPromptSubmit ?? []
            case .preToolUse: return preToolUse ?? []
            case .permissionRequest: return permissionRequest ?? []
            case .postToolUse: return postToolUse ?? []
            case .stop: return stop ?? []
            case .preCompact: return preCompact ?? []
            case .postCompact: return postCompact ?? []
            case .sessionEnd: return sessionEnd ?? []
            }
        }
    }

    private struct Rule: Decodable {
        var action: String
        var reason: String?
        var tool: String?
        var command: String?
    }

    static func sessionStartDenial(projectRoot: URL?) -> String? {
        denial(event: .sessionStart, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func userPromptSubmit(_ prompt: String, projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .userPromptSubmit, projectRoot: projectRoot, tool: nil, command: prompt)
    }

    static func preToolUse(tool: String, command: String?, projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .preToolUse, projectRoot: projectRoot, tool: tool, command: command)
    }

    static func permissionRequest(tool: String, projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .permissionRequest, projectRoot: projectRoot, tool: tool, command: nil)
    }

    static func postToolUse(tool: String, projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .postToolUse, projectRoot: projectRoot, tool: tool, command: nil)
    }

    static func preCompact(projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .preCompact, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func postCompact(projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .postCompact, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func sessionEnd(projectRoot: URL?) -> HookRuntimeOutcome {
        outcome(event: .sessionEnd, projectRoot: projectRoot, tool: nil, command: nil)
    }

    /// Codex Stop hook can hand a prompt back and sample once more.
    /// `alreadyActive` matches `stop_hook_active`: a continuation does not block again.
    static func stopContinuation(projectRoot: URL?, alreadyActive: Bool) -> String? {
        if alreadyActive { return nil }
        let result = outcome(event: .stop, projectRoot: projectRoot, tool: nil, command: nil)
        if result.shouldStop { return nil }
        return result.additionalContexts.first
    }

    private static func denial(
        event: HookEvent,
        projectRoot: URL?,
        tool: String?,
        command: String?
    ) -> String? {
        let result = outcome(event: event, projectRoot: projectRoot, tool: tool, command: command)
        return result.shouldStop ? result.additionalContexts.first ?? "Hook denied this turn." : nil
    }

    private static func outcome(
        event: HookEvent,
        projectRoot: URL?,
        tool: String?,
        command: String?
    ) -> HookRuntimeOutcome {
        let matching = rules(projectRoot: projectRoot)?.rules(for: event).filter {
            matches($0, tool: tool, command: command)
        } ?? []
        if let deny = matching.first(where: { $0.action == "deny" }) {
            return HookRuntimeOutcome(
                shouldStop: true,
                additionalContexts: [deny.reason ?? "Hook denied this turn."]
            )
        }
        let contexts = matching.compactMap { rule -> String? in
            guard rule.action == "continue" || rule.action == "allow" else { return nil }
            return rule.reason
        }
        return HookRuntimeOutcome(shouldStop: false, additionalContexts: contexts)
    }

    private static func matches(_ rule: Rule, tool: String?, command: String?) -> Bool {
        if let expected = rule.tool, expected != tool { return false }
        if let needle = rule.command {
            guard let command, command.contains(needle) else { return false }
        }
        return true
    }

    private static func rules(projectRoot: URL?) -> Config? {
        guard let projectRoot else { return nil }
        let url = projectRoot
            .appendingPathComponent(".sage", isDirectory: true)
            .appendingPathComponent("hooks.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }
}

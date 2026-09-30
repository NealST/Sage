//
//  hook_runtime.swift
//  Sage
//
//  Port of codex-rs/core/src/hook_runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The same events Codex runs around a turn: session start, prompt submit,
//  pre-tool, permission request, post-tool, stop, interrupt, compact,
//  session end. Rules live in `.sage/hooks.json`. A deny stops the turn.
//  `continue` injects context. A second Stop hook does not fire while one
//  is active. `run` executes a local command via CommandHookRuntime and
//  parses Codex hook JSON. MCP hook execution stays out.
//

import CodexHooks
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
    case interrupt
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
        var interrupt: [Rule]?
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
            case interrupt
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
            case .interrupt: return interrupt ?? []
            case .preCompact: return preCompact ?? []
            case .postCompact: return postCompact ?? []
            case .sessionEnd: return sessionEnd ?? []
            }
        }
    }

    private struct Rule: Decodable {
        var action: String?
        var reason: String?
        var tool: String?
        var command: String?
        var run: String?
        var timeoutSec: UInt64?
        var argumentEquals: [String: String]?
        var argumentContains: [String: String]?

        enum CodingKeys: String, CodingKey {
            case action, reason, tool, command, run
            case timeoutSec = "timeout_sec"
            case argumentEquals = "argument_equals"
            case argumentContains = "argument_contains"
        }
    }

    static func sessionStart(projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .sessionStart, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func sessionStartDenial(projectRoot: URL?) async -> String? {
        denial(from: await sessionStart(projectRoot: projectRoot))
    }

    static func userPromptSubmit(_ prompt: String, projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .userPromptSubmit, projectRoot: projectRoot, tool: nil, command: prompt)
    }

    static func preToolUse(
        tool: String,
        command: String?,
        projectRoot: URL?,
        argumentsJSON: String? = nil
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .preToolUse,
            projectRoot: projectRoot,
            tool: tool,
            command: command,
            argumentsJSON: argumentsJSON ?? command
        )
    }

    static func permissionRequest(tool: String, projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .permissionRequest, projectRoot: projectRoot, tool: tool, command: nil)
    }

    static func postToolUse(tool: String, projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .postToolUse, projectRoot: projectRoot, tool: tool, command: nil)
    }

    static func preCompact(projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .preCompact, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func postCompact(projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .postCompact, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func interrupt(projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .interrupt, projectRoot: projectRoot, tool: nil, command: nil)
    }

    static func sessionEnd(projectRoot: URL?) async -> HookRuntimeOutcome {
        await outcome(event: .sessionEnd, projectRoot: projectRoot, tool: nil, command: nil)
    }

    /// Codex Stop hook can hand a prompt back and sample once more.
    /// `alreadyActive` matches `stop_hook_active`: a continuation does not block again.
    static func stopContinuation(projectRoot: URL?, alreadyActive: Bool) async -> String? {
        if alreadyActive { return nil }
        let result = await outcome(event: .stop, projectRoot: projectRoot, tool: nil, command: nil)
        if result.shouldStop { return nil }
        return result.additionalContexts.first
    }

    private static func denial(from result: HookRuntimeOutcome) -> String? {
        result.shouldStop ? result.additionalContexts.first ?? "Hook denied this turn." : nil
    }

    private static func outcome(
        event: HookEvent,
        projectRoot: URL?,
        tool: String?,
        command: String?,
        argumentsJSON: String? = nil
    ) async -> HookRuntimeOutcome {
        let matching = rules(projectRoot: projectRoot)?.rules(for: event).filter {
            matches($0, tool: tool, command: command, argumentsJSON: argumentsJSON)
        } ?? []
        if let deny = matching.first(where: { $0.action == "deny" }) {
            return HookRuntimeOutcome(
                shouldStop: true,
                additionalContexts: [deny.reason ?? "Hook denied this turn."]
            )
        }
        var contexts = matching.compactMap { rule -> String? in
            guard rule.action == "continue" || rule.action == "allow" else { return nil }
            return rule.reason
        }
        let scripts = matching.compactMap(\.run)
        guard !scripts.isEmpty, let projectRoot else {
            return HookRuntimeOutcome(shouldStop: false, additionalContexts: contexts)
        }
        let runtime = CommandHookRuntime(
            shell: CommandShell(program: "/bin/sh", args: ["-c"]),
            environment: ProcessInfo.processInfo.environment.map { ($0.key, $0.value) }
        )
        let inputJSON = hookInputJSON(
            event: event,
            tool: tool,
            command: command,
            argumentsJSON: argumentsJSON
        )
        for rule in matching {
            guard let script = rule.run else { continue }
            let result = await runtime.runLocalCommand(
                script,
                inputJSON: inputJSON,
                cwd: projectRoot.path,
                timeoutSec: rule.timeoutSec ?? 10
            )
            let parsed = parseScriptOutcome(event: event, result: result)
            if parsed.shouldStop {
                return parsed
            }
            contexts.append(contentsOf: parsed.additionalContexts)
        }
        return HookRuntimeOutcome(shouldStop: false, additionalContexts: contexts)
    }

    private static func matches(
        _ rule: Rule,
        tool: String?,
        command: String?,
        argumentsJSON: String?
    ) -> Bool {
        if let expected = rule.tool {
            guard let tool, wildcardMatch(pattern: expected, value: tool) else { return false }
        }
        if let needle = rule.command {
            guard let command, command.contains(needle) else { return false }
        }
        if rule.argumentEquals != nil || rule.argumentContains != nil {
            guard let argumentsJSON,
                  let data = argumentsJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            if let argumentEquals = rule.argumentEquals {
                for (key, expected) in argumentEquals {
                    guard stringValue(object[key]) == expected else { return false }
                }
            }
            if let argumentContains = rule.argumentContains {
                for (key, expected) in argumentContains {
                    guard stringValue(object[key])?.contains(expected) == true else { return false }
                }
            }
        }
        return true
    }

    private static func wildcardMatch(pattern: String, value: String) -> Bool {
        if pattern == value { return true }
        var expression = NSRegularExpression.escapedPattern(for: pattern)
        expression = expression.replacingOccurrences(of: "\\*", with: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(expression)$") else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
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

func hookInputJSON(
    event: HookEvent,
    tool: String?,
    command: String?,
    argumentsJSON: String?
) -> String {
    var object: [String: Any] = ["event": event.rawValue]
    if let tool { object["tool_name"] = tool }
    if let command { object["command"] = command }
    if let argumentsJSON,
       let data = argumentsJSON.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data)
    {
        object["tool_input"] = parsed
    } else if let argumentsJSON {
        object["arguments"] = argumentsJSON
    }
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return text
}

func parseScriptOutcome(event: HookEvent, result: HandlerRunResult) -> HookRuntimeOutcome {
    let stdout = result.stdout
    switch event {
    case .userPromptSubmit:
        if let parsed = parseUserPromptSubmit(stdout) {
            if parsed.shouldBlock {
                return .stop(parsed.reason ?? parsed.universal.systemMessage)
            }
            return .proceeding(parsed.additionalContext, parsed.universal.systemMessage)
        }
    case .preToolUse:
        if let parsed = parsePreToolUse(stdout) {
            if let reason = parsed.blockReason {
                return .stop(reason)
            }
            return .proceeding(parsed.additionalContext, parsed.universal.systemMessage)
        }
    case .permissionRequest:
        if let parsed = parsePermissionRequest(stdout) {
            if case .deny(let message) = parsed.decision {
                return .stop(message)
            }
            return .proceeding(parsed.universal.systemMessage)
        }
    case .postToolUse:
        if let parsed = parsePostToolUse(stdout) {
            if parsed.shouldBlock {
                return .stop(parsed.reason ?? parsed.universal.systemMessage)
            }
            return .proceeding(parsed.additionalContext, parsed.universal.systemMessage)
        }
    case .sessionStart:
        if let parsed = parseSessionStart(stdout) {
            if !parsed.universal.continueProcessing {
                return .stop(parsed.universal.stopReason ?? parsed.universal.systemMessage)
            }
            return .proceeding(parsed.additionalContext, parsed.universal.systemMessage)
        }
    case .stop:
        if let parsed = parseStop(stdout) {
            if parsed.shouldBlock {
                return .stop(parsed.reason ?? parsed.universal.systemMessage)
            }
            return .proceeding(parsed.reason, parsed.universal.systemMessage)
        }
    case .interrupt:
        if let parsed = parseInterrupt(stdout) {
            return .proceeding(parsed.systemMessage)
        }
    case .preCompact:
        if let parsed = parsePreCompact(stdout) {
            if !parsed.universal.continueProcessing {
                return .stop(parsed.universal.stopReason ?? parsed.universal.systemMessage)
            }
            return .proceeding(parsed.universal.systemMessage)
        }
    case .postCompact:
        if let parsed = parsePostCompact(stdout) {
            if !parsed.universal.continueProcessing {
                return .stop(parsed.universal.stopReason ?? parsed.universal.systemMessage)
            }
            return .proceeding(parsed.universal.systemMessage)
        }
    case .sessionEnd:
        break
    }
    if let universal = parseUniversalHookOutput(stdout) {
        if !universal.continueProcessing {
            return .stop(universal.stopReason ?? universal.systemMessage)
        }
        return .proceeding(universal.systemMessage)
    }
    if looksLikeJSON(stdout) {
        return .proceed
    }
    let fallback = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.exitCode != 0 {
        let error = result.error ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .proceeding(fallback.isEmpty ? error : fallback)
    }
    return fallback.isEmpty ? .proceed : .proceeding(fallback)
}

private extension HookRuntimeOutcome {
    static func stop(_ reason: String?) -> HookRuntimeOutcome {
        HookRuntimeOutcome(
            shouldStop: true,
            additionalContexts: [reason ?? "Hook denied this turn."]
        )
    }

    static func proceeding(_ texts: String?...) -> HookRuntimeOutcome {
        HookRuntimeOutcome(
            shouldStop: false,
            additionalContexts: texts.compactMap {
                let trimmed = $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        )
    }
}

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
//  session end. Rules live in `.sage/hooks.json` and skill `hooks.json`.
//  A deny stops the turn. `ask` is HUD-only (`preToolUseDecision`).
//  `continue` injects context. A second Stop hook does not fire while one
//  is active. `run` executes a local command via CommandHookRuntime and
//  parses Codex hook JSON. SessionStart stdin carries rust `source`;
//  UserPromptSubmit stdin carries prompt plus turn fields.
//  Pre/PostCompact stdin carries rust `trigger` (auto / manual).
//  Interrupt / SessionEnd / Stop stdin carry rust turn fields;
//  SessionEnd reason is rust `other`; Stop sends `stop_hook_active`.
//  Pre/PostToolUse and PermissionRequest stdin carry rust tool + turn fields.
//  AfterAgent is rust `run_legacy_after_agent_hook` (notify argv / tests).
//  MCP hook execution stays out.
//

import CodexCore
import CodexHooks
import CodexProtocol
import CodexUtils
import CryptoKit
import Foundation

struct HookRuntimeOutcome: Equatable {
    var shouldStop: Bool
    var additionalContexts: [String]
    var updatedInput: String? = nil
    var feedbackMessage: String? = nil

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
        var sessionStart: [Rule]? = nil
        var userPromptSubmit: [Rule]? = nil
        var preToolUse: [Rule]? = nil
        var permissionRequest: [Rule]? = nil
        var postToolUse: [Rule]? = nil
        var stop: [Rule]? = nil
        var interrupt: [Rule]? = nil
        var preCompact: [Rule]? = nil
        var postCompact: [Rule]? = nil
        var sessionEnd: [Rule]? = nil

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

    static func sessionStart(
        projectRoot: URL?,
        source: SessionStartSource = .startup,
        sessionId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default"
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .sessionStart,
            projectRoot: projectRoot,
            tool: nil,
            command: nil,
            sessionStart: SessionStartHookInput(
                source: source,
                sessionId: sessionId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode
            )
        )
    }

    static func sessionStartDenial(
        projectRoot: URL?,
        source: SessionStartSource = .startup
    ) async -> String? {
        denial(from: await sessionStart(projectRoot: projectRoot, source: source))
    }

    static func userPromptSubmit(
        _ prompt: String,
        projectRoot: URL?,
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default"
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .userPromptSubmit,
            projectRoot: projectRoot,
            tool: nil,
            command: prompt,
            userPromptSubmit: UserPromptSubmitHookInput(
                prompt: prompt,
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode
            )
        )
    }

    static func preToolUse(
        tool: String,
        command: String?,
        projectRoot: URL?,
        argumentsJSON: String? = nil,
        activatedSkills: [SkillRecord] = [],
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default",
        toolUseId: String = ""
    ) async -> HookRuntimeOutcome {
        let payload = argumentsJSON ?? command
        return await outcome(
            event: .preToolUse,
            projectRoot: projectRoot,
            tool: tool,
            command: command,
            argumentsJSON: payload,
            activatedSkills: activatedSkills,
            toolUse: ToolUseHookInput(
                eventName: "PreToolUse",
                toolName: tool,
                toolInput: payload ?? "",
                toolUseId: toolUseId,
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode
            )
        )
    }

    /// Declarative HUD decision. Does not run `run` scripts; those stay on `preToolUse`.
    static func preToolUseDecision(
        tool: String,
        argumentsJSON: String,
        projectRoot: URL?,
        activatedSkills: [SkillRecord] = []
    ) -> PreToolUseDecision {
        switch loadConfigs(projectRoot: projectRoot, activatedSkills: activatedSkills) {
        case .invalid(let message):
            return .deny(message)

        case .files(let files):
            var matching: [(rule: Rule, source: URL)] = []
            for (url, config) in files {
                matching.append(contentsOf: config.rules(for: .preToolUse).compactMap { rule in
                    matches(rule, tool: tool, command: nil, argumentsJSON: argumentsJSON)
                        ? (rule, url)
                        : nil
                })
            }
            if let denied = matching.first(where: { $0.rule.action == "deny" }) {
                return .deny(hudMessage(for: denied.rule, source: denied.source))
            }
            if let asked = matching.first(where: { $0.rule.action == "ask" }) {
                return .ask(
                    PreToolUseApproval(
                        reason: hudMessage(for: asked.rule, source: asked.source),
                        identity: approvalIdentity(rule: asked.rule, source: asked.source)
                    )
                )
            }
            return .allow
        }
    }

    static func permissionRequest(
        tool: String,
        projectRoot: URL?,
        argumentsJSON: String? = nil,
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default"
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .permissionRequest,
            projectRoot: projectRoot,
            tool: tool,
            command: argumentsJSON,
            argumentsJSON: argumentsJSON,
            permissionRequest: ToolUseHookInput(
                eventName: "PermissionRequest",
                toolName: tool,
                toolInput: argumentsJSON ?? "",
                toolUseId: "",
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode
            )
        )
    }

    static func postToolUse(
        tool: String,
        projectRoot: URL?,
        argumentsJSON: String? = nil,
        activatedSkills: [SkillRecord] = [],
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default",
        toolUseId: String = "",
        toolResponse: String? = nil
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .postToolUse,
            projectRoot: projectRoot,
            tool: tool,
            command: argumentsJSON,
            argumentsJSON: argumentsJSON,
            activatedSkills: activatedSkills,
            toolUse: ToolUseHookInput(
                eventName: "PostToolUse",
                toolName: tool,
                toolInput: argumentsJSON ?? "",
                toolUseId: toolUseId,
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode,
                toolResponse: toolResponse
            )
        )
    }

    static func preCompact(
        projectRoot: URL?,
        trigger: CompactHookTrigger = .auto,
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = ""
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .preCompact,
            projectRoot: projectRoot,
            tool: nil,
            command: trigger.rawValue,
            compact: CompactHookInput(
                eventName: "PreCompact",
                trigger: trigger,
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model
            )
        )
    }

    static func postCompact(
        projectRoot: URL?,
        trigger: CompactHookTrigger = .auto,
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = ""
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .postCompact,
            projectRoot: projectRoot,
            tool: nil,
            command: trigger.rawValue,
            compact: CompactHookInput(
                eventName: "PostCompact",
                trigger: trigger,
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model
            )
        )
    }

    static func interrupt(
        projectRoot: URL?,
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default"
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .interrupt,
            projectRoot: projectRoot,
            tool: nil,
            command: nil,
            interrupt: InterruptHookInput(
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode
            )
        )
    }

    static func sessionEnd(
        projectRoot: URL?,
        sessionId: String = "",
        cwd: String? = nil,
        reason: SessionEndHookReason = .other
    ) async -> HookRuntimeOutcome {
        await outcome(
            event: .sessionEnd,
            projectRoot: projectRoot,
            tool: nil,
            command: reason.rawValue,
            sessionEnd: SessionEndHookInput(
                sessionId: sessionId,
                cwd: cwd ?? projectRoot?.path ?? "",
                reason: reason
            )
        )
    }

    /// Codex Stop hook can hand a prompt back and sample once more.
    /// `alreadyActive` matches `stop_hook_active`: a continuation does not block again.
    static func stopContinuation(
        projectRoot: URL?,
        alreadyActive: Bool,
        sessionId: String = "",
        turnId: String = "",
        cwd: String? = nil,
        model: String = "",
        permissionMode: String = "default",
        lastAssistantMessage: String? = nil
    ) async -> String? {
        if alreadyActive { return nil }
        let result = await outcome(
            event: .stop,
            projectRoot: projectRoot,
            tool: nil,
            command: nil,
            stop: StopHookInput(
                sessionId: sessionId,
                turnId: turnId,
                cwd: cwd ?? projectRoot?.path ?? "",
                model: model,
                permissionMode: permissionMode,
                stopHookActive: alreadyActive,
                lastAssistantMessage: lastAssistantMessage
            )
        )
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
        argumentsJSON: String? = nil,
        activatedSkills: [SkillRecord] = [],
        sessionStart: SessionStartHookInput? = nil,
        userPromptSubmit: UserPromptSubmitHookInput? = nil,
        compact: CompactHookInput? = nil,
        interrupt: InterruptHookInput? = nil,
        sessionEnd: SessionEndHookInput? = nil,
        stop: StopHookInput? = nil,
        toolUse: ToolUseHookInput? = nil,
        permissionRequest: ToolUseHookInput? = nil
    ) async -> HookRuntimeOutcome {
        let files: [(URL, Config)]
        switch loadConfigs(projectRoot: projectRoot, activatedSkills: activatedSkills) {
        case .invalid(let message):
            return HookRuntimeOutcome(shouldStop: true, additionalContexts: [message])

        case .files(let loaded):
            files = loaded
        }
        let matching = files.flatMap { _, config in
            config.rules(for: event).filter {
                matches($0, tool: tool, command: command, argumentsJSON: argumentsJSON)
            }
        }
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
        let inputJSON = if let sessionStart, event == .sessionStart {
            sessionStartInputJSON(sessionStart)
        } else if let userPromptSubmit, event == .userPromptSubmit {
            userPromptSubmitInputJSON(userPromptSubmit)
        } else if let compact, event == .preCompact || event == .postCompact {
            compactHookInputJSON(compact)
        } else if let interrupt, event == .interrupt {
            interruptHookInputJSON(interrupt)
        } else if let sessionEnd, event == .sessionEnd {
            sessionEndHookInputJSON(sessionEnd)
        } else if let stop, event == .stop {
            stopHookInputJSON(stop)
        } else if let toolUse, event == .preToolUse || event == .postToolUse {
            toolUseHookInputJSON(toolUse)
        } else if let permissionRequest, event == .permissionRequest {
            toolUseHookInputJSON(permissionRequest)
        } else {
            hookInputJSON(
                event: event,
                tool: tool,
                command: command,
                argumentsJSON: argumentsJSON
            )
        }
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

    private enum LoadedHooks {
        case files([(URL, Config)])
        case invalid(String)
    }

    private enum CachedConfig {
        case decoded(Config)
        case invalid(String)
    }

    private struct CachedFile {
        var digest: String
        var result: CachedConfig
    }

    private static let cacheLock = NSLock()
    private static var fileCache: [URL: CachedFile] = [:]

    private static func hookURLs(
        projectRoot: URL?,
        activatedSkills: [SkillRecord]
    ) -> [URL] {
        var urls: [URL] = []
        if let projectRoot {
            urls.append(
                projectRoot
                    .appendingPathComponent(".sage", isDirectory: true)
                    .appendingPathComponent("hooks.json")
            )
        }
        urls.append(contentsOf: activatedSkills.map { skill in
            URL(fileURLWithPath: skill.path)
                .deletingLastPathComponent()
                .appendingPathComponent("hooks.json")
        })
        return Array(Set(urls.map(\.standardizedFileURL)))
            .sorted { $0.path < $1.path }
    }

    private static func loadConfigs(
        projectRoot: URL?,
        activatedSkills: [SkillRecord]
    ) -> LoadedHooks {
        var loaded: [(URL, Config)] = []
        for url in hookURLs(projectRoot: projectRoot, activatedSkills: activatedSkills) {
            switch config(at: url) {
            case .decoded(let config):
                loaded.append((url, config))

            case .invalid(let message):
                return .invalid(message)
            }
        }
        return .files(loaded)
    }

    private static func config(at url: URL) -> CachedConfig {
        guard let data = try? Data(contentsOf: url) else {
            cacheLock.lock()
            fileCache.removeValue(forKey: url)
            cacheLock.unlock()
            return .decoded(Config())
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        cacheLock.lock()
        if let cached = fileCache[url], cached.digest == digest {
            let result = cached.result
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        let result: CachedConfig
        do {
            result = .decoded(try JSONDecoder().decode(Config.self, from: data))
        } catch {
            result = .invalid(
                "Invalid PreToolUse hook config at \(url.path): \(error.localizedDescription)"
            )
        }
        cacheLock.lock()
        fileCache[url] = CachedFile(digest: digest, result: result)
        cacheLock.unlock()
        return result
    }

    private static func hudMessage(for rule: Rule, source: URL) -> String {
        let reason = rule.reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "Matched PreToolUse rule '\(rule.tool ?? "*")'."
        return "\(reason) [\(source.lastPathComponent)]"
    }

    private static func approvalIdentity(rule: Rule, source: URL) -> String {
        let encodedRule = (try? JSONEncoder().encode(hudRule(rule))) ?? Data()
        var payload = Data(source.standardizedFileURL.path.utf8)
        payload.append(0)
        payload.append(encodedRule)
        if let content = try? Data(contentsOf: source) {
            payload.append(0)
            payload.append(content)
        }
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private static func hudRule(_ rule: Rule) -> PreToolUseHookRule {
        PreToolUseHookRule(
            tool: rule.tool ?? "*",
            action: PreToolUseHookRule.Action(rawValue: rule.action ?? "allow") ?? .allow,
            argumentEquals: rule.argumentEquals,
            argumentContains: rule.argumentContains,
            reason: rule.reason
        )
    }
}

struct SessionStartHookInput: Equatable, Sendable {
    var source: SessionStartSource
    var sessionId: String
    var cwd: String
    var model: String
    var permissionMode: String
}

struct UserPromptSubmitHookInput: Equatable, Sendable {
    var prompt: String
    var sessionId: String
    var turnId: String
    var cwd: String
    var model: String
    var permissionMode: String
}

enum CompactHookTrigger: String, Equatable, Sendable {
    case auto
    case manual
}

struct CompactHookInput: Equatable, Sendable {
    var eventName: String
    var trigger: CompactHookTrigger
    var sessionId: String
    var turnId: String
    var cwd: String
    var model: String
}

enum SessionEndHookReason: String, Equatable, Sendable {
    case other
}

struct InterruptHookInput: Equatable, Sendable {
    var sessionId: String
    var turnId: String
    var cwd: String
    var model: String
    var permissionMode: String
}

struct SessionEndHookInput: Equatable, Sendable {
    var sessionId: String
    var cwd: String
    var reason: SessionEndHookReason
}

struct StopHookInput: Equatable, Sendable {
    var sessionId: String
    var turnId: String
    var cwd: String
    var model: String
    var permissionMode: String
    var stopHookActive: Bool
    var lastAssistantMessage: String?
}

struct ToolUseHookInput: Equatable, Sendable {
    var eventName: String
    var toolName: String
    var toolInput: String
    var toolUseId: String
    var sessionId: String
    var turnId: String
    var cwd: String
    var model: String
    var permissionMode: String
    var toolResponse: String? = nil
}

func interruptHookInputJSON(_ input: InterruptHookInput) -> String {
    hookStdinJSON([
        "session_id": input.sessionId,
        "turn_id": input.turnId,
        "transcript_path": NSNull(),
        "cwd": input.cwd,
        "hook_event_name": "Interrupt",
        "model": input.model,
        "permission_mode": input.permissionMode,
    ])
}

func sessionEndHookInputJSON(_ input: SessionEndHookInput) -> String {
    hookStdinJSON([
        "session_id": input.sessionId,
        "transcript_path": NSNull(),
        "cwd": input.cwd,
        "hook_event_name": "SessionEnd",
        "reason": input.reason.rawValue,
    ])
}

func stopHookInputJSON(_ input: StopHookInput) -> String {
    hookStdinJSON([
        "session_id": input.sessionId,
        "turn_id": input.turnId,
        "transcript_path": NSNull(),
        "cwd": input.cwd,
        "hook_event_name": "Stop",
        "model": input.model,
        "permission_mode": input.permissionMode,
        "stop_hook_active": input.stopHookActive,
        "last_assistant_message": input.lastAssistantMessage ?? NSNull(),
    ])
}

func toolUseHookInputJSON(_ input: ToolUseHookInput) -> String {
    var object: [String: Any] = [
        "session_id": input.sessionId,
        "turn_id": input.turnId,
        "transcript_path": NSNull(),
        "cwd": input.cwd,
        "hook_event_name": input.eventName,
        "model": input.model,
        "permission_mode": input.permissionMode,
        "tool_name": input.toolName,
        "tool_input": hookJSONValue(from: input.toolInput),
    ]
    if input.eventName != "PermissionRequest" {
        object["tool_use_id"] = input.toolUseId
    }
    if input.eventName == "PostToolUse" {
        object["tool_response"] = hookJSONValue(from: input.toolResponse ?? "")
    }
    return hookStdinJSON(object)
}

func hookJSONValue(from text: String) -> Any {
    if let data = text.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data)
    {
        return parsed
    }
    if text.isEmpty {
        return [String: Any]()
    }
    return text
}

func hookStdinJSON(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return text
}

func compactHookInputJSON(_ input: CompactHookInput) -> String {
    let object: [String: Any] = [
        "session_id": input.sessionId,
        "turn_id": input.turnId,
        "transcript_path": NSNull(),
        "cwd": input.cwd,
        "hook_event_name": input.eventName,
        "model": input.model,
        "trigger": input.trigger.rawValue,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return text
}

func userPromptSubmitInputJSON(_ input: UserPromptSubmitHookInput) -> String {
    let object: [String: Any] = [
        "session_id": input.sessionId,
        "turn_id": input.turnId,
        "transcript_path": NSNull(),
        "cwd": input.cwd,
        "hook_event_name": "UserPromptSubmit",
        "model": input.model,
        "permission_mode": input.permissionMode,
        "prompt": input.prompt,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return text
}

func sessionStartInputJSON(_ input: SessionStartHookInput) -> String {
    SessionStartCommandInput(
        sessionId: input.sessionId,
        transcriptPath: nil,
        cwd: input.cwd,
        model: input.model,
        permissionMode: input.permissionMode,
        source: input.source.asStr()
    ).encodedJSON()
}

func hookPermissionMode(_ approvalPolicy: CodexProtocol.AskForApproval) -> String {
    switch approvalPolicy {
    case .never:
        return "bypassPermissions"
    case .unlessTrusted, .onRequest, .granular:
        return "default"
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
            var outcome = HookRuntimeOutcome.proceeding(
                parsed.additionalContext,
                parsed.universal.systemMessage
            )
            if let updated = parsed.updatedInput {
                outcome.updatedInput = updated.encodedString()
            }
            return outcome
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
            var outcome = HookRuntimeOutcome.proceeding(parsed.additionalContext)
            let feedback = parsed.universal.systemMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let feedback, !feedback.isEmpty {
                outcome.feedbackMessage = feedback
            }
            return outcome
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

/// rust `run_legacy_after_agent_hook`. Returns true when a hook aborts
/// turn completion (runTurn then returns nil).
func runLegacyAfterAgentHook(
    sess: Session,
    turnContext: TurnContext,
    input: [ResponseItem],
    lastAssistantMessage: String?
) async -> Bool {
    let inputMessages = input.compactMap { item -> String? in
        guard case .userMessage(let user) = parseTurnItem(item) else { return nil }
        return user.message()
    }
    let cwd = (try? AbsolutePathBuf.fromAbsolutePath(turnContext.cwd))
        ?? (try? AbsolutePathBuf.fromAbsolutePath("/tmp"))
        ?? AbsolutePathBuf.resolvePathAgainstBase("/tmp", basePath: "/")
    var abortMessage: String?
    for hookOutcome in await sess.hooks().dispatch(
        HookPayload(
            sessionId: sess.threadId,
            cwd: cwd,
            client: nil,
            triggeredAt: Date(),
            hookEvent: .afterAgent(
                HookEventAfterAgent(
                    threadId: sess.threadId,
                    turnId: turnContext.subId,
                    inputMessages: inputMessages,
                    lastAssistantMessage: lastAssistantMessage
                )
            )
        )
    ) {
        let error: (any Error)?
        let shouldAbort: Bool
        switch hookOutcome.result {
        case .success:
            continue
        case .failedContinue(let err):
            error = err
            shouldAbort = false
        case .failedAbort(let err):
            error = err
            shouldAbort = true
        }
        _ = error
        if shouldAbort, abortMessage == nil {
            abortMessage = "after_agent hook '\(hookOutcome.hookName)' failed and aborted turn completion: \(error?.localizedDescription ?? "")"
        }
    }
    guard let message = abortMessage else { return false }
    sess.sendEvent(
        turnContext,
        .error(ErrorEvent(message: message, errorInfo: .other))
    )
    return true
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

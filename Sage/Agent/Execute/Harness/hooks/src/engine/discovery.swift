//
//  discovery.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/discovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Result type, hooks.json parse, append_matcher_groups, timeout/hash/trust
//  normalization, and folder discovery are ported. Config-layer TOML walks,
//  managed-requirement handlers, and plugin executable hooks wait on
//  ConfigLayerStack / the plugin crate. HooksFile / HookEventsToml /
//  MatcherGroup / HookHandlerConfig are inlined from the config crate
//  (not a harness Port-of file). Trust identity hashes canonical JSON
//  rather than TOML (`version_for_toml`); tests assert the `sha256:`
//  prefix and inequality across limits.
//

import CodexProtocol
import CodexUtils
import CryptoKit
import Foundation

public struct DiscoveredHandlers: Equatable, Sendable {
    public var handlers: [ConfiguredHandler]
    public var hookEntries: [HookListEntry]
    public var warnings: [String]
    public var requiredLoadErrors: [String]

    public init(
        handlers: [ConfiguredHandler] = [],
        hookEntries: [HookListEntry] = [],
        warnings: [String] = [],
        requiredLoadErrors: [String] = []
    ) {
        self.handlers = handlers
        self.hookEntries = hookEntries
        self.warnings = warnings
        self.requiredLoadErrors = requiredLoadErrors
    }
}

// MARK: - Inlined config crate wire types (`codex_config::hook_config`)

struct HooksFile: Equatable, Sendable {
    var description: String?
    var hooks: HookEventsToml
}

struct HookEventsToml: Equatable, Sendable {
    var preToolUse: [MatcherGroup] = []
    var permissionRequest: [MatcherGroup] = []
    var postToolUse: [MatcherGroup] = []
    var preCompact: [MatcherGroup] = []
    var postCompact: [MatcherGroup] = []
    var sessionStart: [MatcherGroup] = []
    var sessionEnd: [MatcherGroup] = []
    var userPromptSubmit: [MatcherGroup] = []
    var subagentStart: [MatcherGroup] = []
    var subagentStop: [MatcherGroup] = []
    var stop: [MatcherGroup] = []
    var interrupt: [MatcherGroup] = []

    var isEmpty: Bool {
        preToolUse.isEmpty
            && permissionRequest.isEmpty
            && postToolUse.isEmpty
            && preCompact.isEmpty
            && postCompact.isEmpty
            && sessionStart.isEmpty
            && sessionEnd.isEmpty
            && userPromptSubmit.isEmpty
            && subagentStart.isEmpty
            && subagentStop.isEmpty
            && stop.isEmpty
            && interrupt.isEmpty
    }

    func matcherGroups() -> [(HookEventName, [MatcherGroup])] {
        [
            (.preToolUse, preToolUse),
            (.permissionRequest, permissionRequest),
            (.postToolUse, postToolUse),
            (.preCompact, preCompact),
            (.postCompact, postCompact),
            (.sessionStart, sessionStart),
            (.sessionEnd, sessionEnd),
            (.userPromptSubmit, userPromptSubmit),
            (.subagentStart, subagentStart),
            (.subagentStop, subagentStop),
            (.stop, stop),
            (.interrupt, interrupt),
        ]
    }
}

struct MatcherGroup: Equatable, Sendable {
    var matcher: String?
    var hooks: [HookHandlerConfig]
}

enum HookHandlerConfig: Equatable, Sendable {
    case command(
        command: String,
        commandWindows: String?,
        timeoutSec: UInt64?,
        isAsync: Bool,
        statusMessage: String?,
        additionalContextLimit: Int?
    )
    case mcpTool(
        server: String,
        tool: String,
        input: [String: JSONValue],
        timeoutSec: UInt64?,
        statusMessage: String?
    )
    case prompt
    case agent
}

struct HooksFileParseError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

enum HookRequirement {
    case required
    case optional
}

struct HookHandlerSource {
    var path: AbsolutePathBuf
    var keySource: String
    var source: HookSource
    var isManaged: Bool
    var requirement: HookRequirement
    var bypassHookTrust: Bool
    var hookStates: [String: HookStateToml]
    var env: [String: String]
    var pluginId: String?

    mutating func recordLoadFailure(_ warning: String, warnings: inout [String], requiredLoadErrors: inout [String]) {
        if case .required = requirement {
            requiredLoadErrors.append(warning)
        }
        warnings.append(warning)
    }
}

struct HookDiscoveryPolicy {
    var allowManagedHooksOnly: Bool
    var bypassHookTrust: Bool

    func allows(_ source: HookHandlerSource) -> Bool {
        !allowManagedHooksOnly || source.isManaged
    }
}

struct NormalizedHandler {
    var config: HookHandlerConfig
    var kind: ConfiguredHandlerKind
    var timeoutSec: UInt64
    var statusMessage: String?
    var additionalContextLimit: Int?
}

public func discoverHandlers(
    hooksJsonFolders: [AbsolutePathBuf] = [],
    hookStates: [String: HookStateToml] = [:],
    pluginHookSources: [PluginHookSource] = [],
    pluginHookLoadWarnings: [String] = [],
    bypassHookTrust: Bool = false
) -> DiscoveredHandlers {
    _ = pluginHookSources
    var handlers: [ConfiguredHandler] = []
    var hookEntries: [HookListEntry] = []
    var warnings = pluginHookLoadWarnings
    var requiredLoadErrors: [String] = []
    var displayOrder: Int64 = 0
    var visitedFolders: Set<String> = []
    let policy = HookDiscoveryPolicy(
        allowManagedHooksOnly: false,
        bypassHookTrust: bypassHookTrust
    )

    for folder in hooksJsonFolders {
        if !visitedFolders.insert(folder.path).inserted { continue }
        guard let (sourcePath, events) = loadHooksJson(folder, warnings: &warnings) else {
            continue
        }
        var source = HookHandlerSource(
            path: sourcePath,
            keySource: sourcePath.display,
            source: .user,
            isManaged: false,
            requirement: .optional,
            bypassHookTrust: policy.bypassHookTrust,
            hookStates: hookStates,
            env: [:],
            pluginId: nil
        )
        appendHookEvents(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            hookEvents: events,
            policy: policy
        )
    }

    return DiscoveredHandlers(
        handlers: handlers,
        hookEntries: hookEntries,
        warnings: warnings,
        requiredLoadErrors: requiredLoadErrors
    )
}

func loadHooksJson(
    _ configFolder: AbsolutePathBuf,
    warnings: inout [String]
) -> (AbsolutePathBuf, HookEventsToml)? {
    let sourcePath = configFolder.join("hooks.json")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: sourcePath.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
    else {
        return nil
    }

    let contents: String
    do {
        contents = try String(contentsOfFile: sourcePath.path, encoding: .utf8)
    } catch {
        warnings.append("failed to read hooks config \(sourcePath.display): \(error)")
        return nil
    }

    let parsed: HooksFile
    do {
        parsed = try parseHooksFile(contents)
    } catch {
        warnings.append("failed to parse hooks config \(sourcePath.display): \(error)")
        return nil
    }

    return parsed.hooks.isEmpty ? nil : (sourcePath, parsed.hooks)
}

func parseHooksFile(_ contents: String) throws -> HooksFile {
    guard let data = contents.data(using: .utf8),
          let value = try? JSONDecoder().decode(JSONValue.self, from: data),
          let object = value.objectValue
    else {
        throw HooksFileParseError(message: "hooks file is not a JSON object")
    }
    guard rejectUnknownHookFields(object, ["description", "hooks"]) else {
        throw HooksFileParseError(message: "unknown field in hooks file")
    }
    let description: String?
    if let raw = object["description"] {
        switch raw {
        case .null:
            description = nil
        case .string(let text):
            description = text
        default:
            throw HooksFileParseError(message: "description must be a string")
        }
    } else {
        description = nil
    }
    let hooks: HookEventsToml
    if let raw = object["hooks"] {
        guard let events = raw.objectValue else {
            throw HooksFileParseError(message: "hooks must be an object")
        }
        hooks = try parseHookEventsToml(events)
    } else {
        hooks = HookEventsToml()
    }
    return HooksFile(description: description, hooks: hooks)
}

func parseHookEventsToml(_ object: [String: JSONValue]) throws -> HookEventsToml {
    var events = HookEventsToml()
    for (key, value) in object {
        guard let eventName = hookEventNameFromWire(key) else { continue }
        guard let groups = try parseMatcherGroups(value) else {
            throw HooksFileParseError(message: "invalid matcher groups for \(key)")
        }
        switch eventName {
        case .preToolUse: events.preToolUse = groups
        case .permissionRequest: events.permissionRequest = groups
        case .postToolUse: events.postToolUse = groups
        case .preCompact: events.preCompact = groups
        case .postCompact: events.postCompact = groups
        case .sessionStart: events.sessionStart = groups
        case .sessionEnd: events.sessionEnd = groups
        case .userPromptSubmit: events.userPromptSubmit = groups
        case .subagentStart: events.subagentStart = groups
        case .subagentStop: events.subagentStop = groups
        case .stop: events.stop = groups
        case .interrupt: events.interrupt = groups
        }
    }
    return events
}

func hookEventNameFromWire(_ raw: String) -> HookEventName? {
    switch raw {
    case "PreToolUse": return .preToolUse
    case "PermissionRequest": return .permissionRequest
    case "PostToolUse": return .postToolUse
    case "PreCompact": return .preCompact
    case "PostCompact": return .postCompact
    case "SessionStart": return .sessionStart
    case "SessionEnd": return .sessionEnd
    case "UserPromptSubmit": return .userPromptSubmit
    case "SubagentStart": return .subagentStart
    case "SubagentStop": return .subagentStop
    case "Stop": return .stop
    case "Interrupt": return .interrupt
    default: return nil
    }
}

func parseMatcherGroups(_ value: JSONValue) throws -> [MatcherGroup]? {
    guard let items = value.arrayValue else { return nil }
    return try items.map { item in
        guard let object = item.objectValue,
              let group = try parseMatcherGroup(object)
        else {
            throw HooksFileParseError(message: "matcher group must be an object")
        }
        return group
    }
}

func parseMatcherGroup(_ object: [String: JSONValue]) throws -> MatcherGroup? {
    let matcher: String?
    if let raw = object["matcher"] {
        switch raw {
        case .null:
            matcher = nil
        case .string(let text):
            matcher = text
        default:
            return nil
        }
    } else {
        matcher = nil
    }
    let hooks: [HookHandlerConfig]
    if let raw = object["hooks"] {
        guard let items = raw.arrayValue else { return nil }
        hooks = try items.map { item in
            guard let handlerObject = item.objectValue,
                  let handler = try parseHookHandlerConfig(handlerObject)
            else {
                throw HooksFileParseError(message: "invalid hook handler")
            }
            return handler
        }
    } else {
        hooks = []
    }
    return MatcherGroup(matcher: matcher, hooks: hooks)
}

func parseHookHandlerConfig(_ object: [String: JSONValue]) throws -> HookHandlerConfig? {
    guard case .string(let type)? = object["type"] else { return nil }
    switch type {
    case "command":
        guard let command = object["command"]?.stringValue else { return nil }
        let commandWindows = object["commandWindows"]?.stringValue
            ?? object["command_windows"]?.stringValue
        guard let timeoutSec = parseOptionalUInt64(object["timeout"]) else { return nil }
        let isAsync: Bool
        if let raw = object["async"] {
            guard let flag = raw.boolValue else { return nil }
            isAsync = flag
        } else {
            isAsync = false
        }
        guard let statusMessage = parseOptionalString(object["statusMessage"]) else { return nil }
        guard let additionalContextLimit = parseOptionalInt(object["additionalContextLimit"]) else {
            return nil
        }
        return .command(
            command: command,
            commandWindows: commandWindows,
            timeoutSec: timeoutSec,
            isAsync: isAsync,
            statusMessage: statusMessage,
            additionalContextLimit: additionalContextLimit
        )
    case "mcp_tool":
        guard let server = object["server"]?.stringValue,
              let tool = object["tool"]?.stringValue
        else {
            return nil
        }
        let input: [String: JSONValue]
        if let raw = object["input"] {
            guard let objectInput = raw.objectValue else { return nil }
            if objectInput.values.contains(where: jsonValueContainsNull) {
                throw HooksFileParseError(message: "MCP hook input must be representable as TOML")
            }
            input = objectInput
        } else {
            input = [:]
        }
        guard let timeoutSec = parseOptionalUInt64(object["timeout"]) else { return nil }
        guard let statusMessage = parseOptionalString(object["statusMessage"]) else { return nil }
        return .mcpTool(
            server: server,
            tool: tool,
            input: input,
            timeoutSec: timeoutSec,
            statusMessage: statusMessage
        )
    case "prompt":
        return .prompt
    case "agent":
        return .agent
    default:
        return nil
    }
}

func parseOptionalString(_ value: JSONValue?) -> String?? {
    guard let value else { return .some(nil) }
    switch value {
    case .null: return .some(nil)
    case .string(let text): return .some(text)
    default: return nil
    }
}

func parseOptionalUInt64(_ value: JSONValue?) -> UInt64?? {
    guard let value else { return .some(nil) }
    switch value {
    case .null:
        return .some(nil)
    case .int(let number) where number >= 0:
        return .some(UInt64(number))
    case .uint(let number):
        return .some(number)
    default:
        return nil
    }
}

func parseOptionalInt(_ value: JSONValue?) -> Int?? {
    guard let value else { return .some(nil) }
    switch value {
    case .null:
        return .some(nil)
    case .int(let number) where number >= 0:
        return .some(Int(number))
    case .uint(let number):
        return Int(exactly: number).map { .some($0) }
    default:
        return nil
    }
}

func jsonValueContainsNull(_ value: JSONValue) -> Bool {
    switch value {
    case .null:
        return true
    case .array(let items):
        return items.contains(where: jsonValueContainsNull)
    case .object(let object):
        return object.values.contains(where: jsonValueContainsNull)
    default:
        return false
    }
}

func appendHookEvents(
    handlers: inout [ConfiguredHandler],
    hookEntries: inout [HookListEntry],
    warnings: inout [String],
    requiredLoadErrors: inout [String],
    displayOrder: inout Int64,
    source: inout HookHandlerSource,
    hookEvents: HookEventsToml,
    policy: HookDiscoveryPolicy
) {
    guard policy.allows(source) else { return }
    for (eventName, groups) in hookEvents.matcherGroups() {
        appendMatcherGroups(
            handlers: &handlers,
            hookEntries: &hookEntries,
            warnings: &warnings,
            requiredLoadErrors: &requiredLoadErrors,
            displayOrder: &displayOrder,
            source: &source,
            eventName: eventName,
            groups: groups
        )
    }
}

func appendMatcherGroups(
    handlers: inout [ConfiguredHandler],
    hookEntries: inout [HookListEntry],
    warnings: inout [String],
    requiredLoadErrors: inout [String],
    displayOrder: inout Int64,
    source: inout HookHandlerSource,
    eventName: HookEventName,
    groups: [MatcherGroup]
) {
    for (groupIndex, group) in groups.enumerated() {
        let matcher = matcherPatternForEvent(eventName, matcher: group.matcher)
        if let matcher {
            do {
                try validateMatcherPattern(matcher)
            } catch {
                let warning = "invalid matcher \(String(reflecting: matcher)) in \(source.path.display): \(error)"
                if group.hooks.isEmpty {
                    warnings.append(warning)
                } else {
                    source.recordLoadFailure(warning, warnings: &warnings, requiredLoadErrors: &requiredLoadErrors)
                }
                continue
            }
        }
        for (handlerIndex, handler) in group.hooks.enumerated() {
            let normalized: NormalizedHandler
            switch handler {
            case .command(
                let command,
                let commandWindows,
                let timeoutSec,
                let isAsync,
                let statusMessage,
                let additionalContextLimit
            ):
                #if os(Windows)
                let resolvedCommand = commandWindows ?? command
                #else
                let resolvedCommand = command
                #endif
                if resolvedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    source.recordLoadFailure(
                        "skipping empty hook command in \(source.path.display)",
                        warnings: &warnings,
                        requiredLoadErrors: &requiredLoadErrors
                    )
                    continue
                }
                let timeout = normalizeCommandHook(
                    eventName,
                    timeoutSec: timeoutSec,
                    sourcePath: source.path,
                    warnings: &warnings
                )
                let runsAsync = isAsync && eventName != .sessionEnd
                if isAsync && !runsAsync {
                    warnings.append(
                        "running async \(hookEventNameLabel(eventName)) hook synchronously in \(source.path.display)"
                    )
                }
                let retainedLimit: Int?
                switch eventName {
                case .preToolUse, .postToolUse, .sessionStart, .userPromptSubmit, .subagentStart:
                    retainedLimit = additionalContextLimit
                default:
                    if additionalContextLimit != nil {
                        warnings.append(
                            "ignoring additionalContextLimit for \(hookEventNameLabel(eventName)) hook in \(source.path.display): this event cannot emit additionalContext"
                        )
                    }
                    retainedLimit = nil
                }
                let normalizedLimit = retainedLimit.flatMap { limit in
                    limit == DEFAULT_HOOK_OUTPUT_TOKEN_LIMIT ? nil : limit
                }
                let substituted = source.env.reduce(resolvedCommand) { command, pair in
                    command.replacingOccurrences(of: "${\(pair.key)}", with: pair.value)
                }
                normalized = NormalizedHandler(
                    config: .command(
                        command: resolvedCommand,
                        commandWindows: nil,
                        timeoutSec: timeout,
                        isAsync: isAsync,
                        statusMessage: statusMessage,
                        additionalContextLimit: normalizedLimit
                    ),
                    kind: .command(command: substituted, env: source.env, isAsync: runsAsync),
                    timeoutSec: timeout,
                    statusMessage: statusMessage,
                    additionalContextLimit: retainedLimit
                )
            case .mcpTool(let server, let tool, let input, let timeoutSec, let statusMessage):
                if eventName == .sessionEnd {
                    source.recordLoadFailure(
                        "skipping MCP tool hook in \(source.path.display): \(hookEventNameLabel(eventName)) MCP hooks are not supported",
                        warnings: &warnings,
                        requiredLoadErrors: &requiredLoadErrors
                    )
                    continue
                }
                if server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || tool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    source.recordLoadFailure(
                        "skipping MCP tool hook in \(source.path.display): server and tool must not be empty",
                        warnings: &warnings,
                        requiredLoadErrors: &requiredLoadErrors
                    )
                    continue
                }
                let timeout = normalizeCommandHook(
                    eventName,
                    timeoutSec: timeoutSec,
                    sourcePath: source.path,
                    warnings: &warnings
                )
                normalized = NormalizedHandler(
                    config: .mcpTool(
                        server: server,
                        tool: tool,
                        input: input,
                        timeoutSec: timeout,
                        statusMessage: statusMessage
                    ),
                    kind: .mcpTool(server: server, tool: tool, input: input),
                    timeoutSec: timeout,
                    statusMessage: statusMessage,
                    additionalContextLimit: nil
                )
            case .prompt:
                source.recordLoadFailure(
                    "skipping prompt hook in \(source.path.display): prompt hooks are not supported yet",
                    warnings: &warnings,
                    requiredLoadErrors: &requiredLoadErrors
                )
                continue
            case .agent:
                source.recordLoadFailure(
                    "skipping agent hook in \(source.path.display): agent hooks are not supported yet",
                    warnings: &warnings,
                    requiredLoadErrors: &requiredLoadErrors
                )
                continue
            }

            let currentHash = hookHash(
                eventName: eventName,
                matcher: matcher,
                group: group,
                normalizedHandler: normalized.config
            )
            let key = hookKey(
                keySource: source.keySource,
                eventName: eventName,
                groupIndex: groupIndex,
                handlerIndex: handlerIndex
            )
            let state = source.hookStates[key]
            let builtin = false
            let enabled = hookEnabled(isManaged: source.isManaged, builtin: builtin, state: state)
            let trustedHash = hookTrustedHash(isManaged: source.isManaged, state: state)
            let trustStatus = hookTrustStatus(
                isManaged: source.isManaged,
                builtin: builtin,
                currentHash: currentHash,
                trustedHash: trustedHash
            )
            let listHandler: HookListEntryHandler
            switch normalized.kind {
            case .command(let command, _, let isAsync):
                listHandler = .command(command: command, isAsync: isAsync)
            case .mcpTool(let server, let tool, _):
                listHandler = .mcpTool(server: server, tool: tool)
            }
            hookEntries.append(
                HookListEntry(
                    builtin: builtin,
                    key: key,
                    eventName: eventName,
                    handler: listHandler,
                    matcher: matcher,
                    timeoutSec: normalized.timeoutSec,
                    statusMessage: normalized.statusMessage,
                    additionalContextLimit: normalized.additionalContextLimit,
                    sourcePath: source.path,
                    source: source.source,
                    pluginId: source.pluginId,
                    displayOrder: displayOrder,
                    enabled: enabled,
                    isManaged: source.isManaged,
                    currentHash: currentHash,
                    trustStatus: trustStatus
                )
            )
            if enabled
                && (source.bypassHookTrust
                    || trustStatus == .managed
                    || trustStatus == .trusted)
            {
                handlers.append(
                    ConfiguredHandler(
                        builtin: builtin,
                        eventName: eventName,
                        matcher: matcher,
                        timeoutSec: normalized.timeoutSec,
                        statusMessage: normalized.statusMessage,
                        additionalContextLimit: AdditionalContextLimit.fromConfig(
                            normalized.additionalContextLimit
                        ),
                        sourcePath: .local(source.path),
                        source: source.source,
                        displayOrder: displayOrder,
                        kind: normalized.kind
                    )
                )
            }
            displayOrder += 1
        }
    }
}

/// SessionEnd and Interrupt default to one second and are capped at three
/// seconds; all other hooks keep the standard ten-minute default.
func normalizeCommandHook(
    _ eventName: HookEventName,
    timeoutSec: UInt64?,
    sourcePath: AbsolutePathBuf,
    warnings: inout [String]
) -> UInt64 {
    switch eventName {
    case .sessionEnd, .interrupt:
        let maxTimeoutSec = SESSION_END_MAX_TIMEOUT_SEC
        if let timeoutSec, timeoutSec > maxTimeoutSec {
            warnings.append(
                "clamping \(hookEventNameLabel(eventName)) hook timeout to \(maxTimeoutSec)s in \(sourcePath.display)"
            )
        }
        return min(max(timeoutSec ?? SESSION_END_DEFAULT_TIMEOUT_SEC, 1), maxTimeoutSec)
    default:
        return max(timeoutSec ?? 600, 1)
    }
}

func hookHash(
    eventName: HookEventName,
    matcher: String?,
    group: MatcherGroup,
    normalizedHandler: HookHandlerConfig
) -> String {
    _ = group
    var identity: [String: JSONValue] = [
        "event_name": .string(hookEventKeyLabel(eventName)),
        "hooks": .array([encodeHookHandlerConfig(normalizedHandler)]),
    ]
    if let matcher {
        identity["matcher"] = .string(matcher)
    }
    return versionForCanonicalJSON(.object(identity))
}

func encodeHookHandlerConfig(_ config: HookHandlerConfig) -> JSONValue {
    switch config {
    case .command(
        let command,
        _,
        let timeoutSec,
        let isAsync,
        let statusMessage,
        let additionalContextLimit
    ):
        var object: [String: JSONValue] = [
            "type": .string("command"),
            "command": .string(command),
            "async": .bool(isAsync),
        ]
        if let timeoutSec {
            object["timeout"] = .uint(timeoutSec)
        }
        if let statusMessage {
            object["statusMessage"] = .string(statusMessage)
        }
        if let additionalContextLimit {
            object["additionalContextLimit"] = .int(Int64(additionalContextLimit))
        }
        return .object(object)
    case .mcpTool(let server, let tool, let input, let timeoutSec, let statusMessage):
        var object: [String: JSONValue] = [
            "type": .string("mcp_tool"),
            "server": .string(server),
            "tool": .string(tool),
            "input": .object(input),
        ]
        if let timeoutSec {
            object["timeout"] = .uint(timeoutSec)
        }
        if let statusMessage {
            object["statusMessage"] = .string(statusMessage)
        }
        return .object(object)
    case .prompt:
        return .object(["type": .string("prompt")])
    case .agent:
        return .object(["type": .string("agent")])
    }
}

func versionForCanonicalJSON(_ value: JSONValue) -> String {
    let digest = SHA256.hash(data: Data(value.encodedString().utf8))
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
}

func hookTrustStatus(
    isManaged: Bool,
    builtin: Bool,
    currentHash: String,
    trustedHash: String?
) -> HookTrustStatus {
    if builtin {
        return .trusted
    }
    if isManaged {
        return .managed
    }
    guard let trustedHash else { return .untrusted }
    return trustedHash == currentHash ? .trusted : .modified
}

func hookEnabled(isManaged: Bool, builtin: Bool, state: HookStateToml?) -> Bool {
    builtin || isManaged || state?.enabled != false
}

func hookTrustedHash(isManaged: Bool, state: HookStateToml?) -> String? {
    isManaged ? nil : state?.trustedHash
}

func managedHookHandlerSource(
    _ path: AbsolutePathBuf,
    hookStates: [String: HookStateToml] = [:]
) -> HookHandlerSource {
    HookHandlerSource(
        path: path,
        keySource: path.display,
        source: .system,
        isManaged: true,
        requirement: .optional,
        bypassHookTrust: false,
        hookStates: hookStates,
        env: [:],
        pluginId: nil
    )
}

func unmanagedHookHandlerSource(
    _ path: AbsolutePathBuf,
    hookStates: [String: HookStateToml] = [:],
    bypassHookTrust: Bool
) -> HookHandlerSource {
    HookHandlerSource(
        path: path,
        keySource: path.display,
        source: .user,
        isManaged: false,
        requirement: .optional,
        bypassHookTrust: bypassHookTrust,
        hookStates: hookStates,
        env: [:],
        pluginId: nil
    )
}

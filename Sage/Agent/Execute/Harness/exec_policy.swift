//
//  exec_policy.swift
//  Sage
//
//  Port of codex-rs/core/src/exec_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Manager, unmatched-command heuristics, amendment derivation, and
//  `.rules` loading. ConfigLayerStack is Phase 5, so loaders take explicit
//  rules-dir layers plus an optional requirements overlay.
//

import CodexExecPolicy
import CodexProtocol
import CodexShellCommand
import Foundation

typealias ExecPolicyRequirements = CodexExecPolicy.RequirementsExecPolicy

let PROMPT_CONFLICT_REASON =
    "approval required by policy, but AskForApproval is set to Never"
let REJECT_SANDBOX_APPROVAL_REASON =
    "approval required by policy, but AskForApproval::Granular.sandbox_approval is false"
let REJECT_RULES_APPROVAL_REASON =
    "approval required by policy, but AskForApproval::Granular.rules is false"
let RULES_DIR_NAME = "rules"
let RULE_EXTENSION = "rules"
let DEFAULT_POLICY_FILE = "default.rules"

let BANNED_PREFIX_SUGGESTIONS: [[String]] = [
    ["/bin/bash"],
    ["/bin/bash", "-c"],
    ["/bin/bash", "-lc"],
    ["/bin/sh"],
    ["/bin/sh", "-c"],
    ["/bin/sh", "-lc"],
    ["/bin/zsh"],
    ["/bin/zsh", "-c"],
    ["/bin/zsh", "-lc"],
    ["Rscript"],
    ["bash"],
    ["bash", "-c"],
    ["bash", "-lc"],
    ["bun"],
    ["bun", "-e"],
    ["bun", "run"],
    ["cmd"],
    ["cmd", "/c"],
    ["cmd", "/k"],
    ["cmd.exe"],
    ["cmd.exe", "/c"],
    ["cmd.exe", "/k"],
    ["dash"],
    ["dash", "-c"],
    ["deno"],
    ["deno", "eval"],
    ["env"],
    ["fish"],
    ["fish", "-c"],
    ["git"],
    ["julia"],
    ["julia", "-e"],
    ["ksh"],
    ["ksh", "-c"],
    ["lua"],
    ["lua", "-e"],
    ["node"],
    ["node", "-e"],
    ["nodejs"],
    ["nodejs", "-e"],
    ["npm", "run"],
    ["osascript"],
    ["perl"],
    ["perl", "-e"],
    ["php"],
    ["php", "-r"],
    ["pnpm", "run"],
    ["powershell"],
    ["powershell", "-Command"],
    ["powershell", "-EncodedCommand"],
    ["powershell", "-File"],
    ["powershell", "-c"],
    ["powershell.exe"],
    ["powershell.exe", "-Command"],
    ["powershell.exe", "-EncodedCommand"],
    ["powershell.exe", "-File"],
    ["powershell.exe", "-c"],
    ["pwsh"],
    ["pwsh", "-Command"],
    ["pwsh", "-EncodedCommand"],
    ["pwsh", "-File"],
    ["pwsh", "-c"],
    ["pwsh", "-e"],
    ["pwsh", "-ec"],
    ["pwsh", "-f"],
    ["py"],
    ["py", "-3"],
    ["pypy"],
    ["pypy3"],
    ["python"],
    ["python", "-"],
    ["python", "-c"],
    ["python3"],
    ["python3", "-"],
    ["python3", "-c"],
    ["pythonw"],
    ["pyw"],
    ["rm"],
    ["ruby"],
    ["ruby", "-e"],
    ["sh"],
    ["sh", "-c"],
    ["sh", "-lc"],
    ["sudo"],
    ["yarn", "run"],
    ["zsh"],
    ["zsh", "-c"],
    ["zsh", "-lc"],
]

/// Describes which unmatched-command heuristics should classify the command
/// words being evaluated by exec-policy.
enum ExecPolicyCommandOrigin: Equatable, Sendable {
    case generic
    case powerShell
}

struct UnmatchedCommandContext {
    var approvalPolicy: AskForApproval
    var permissionProfile: PermissionProfile
    var windowsSandboxLevel: WindowsSandboxLevel
    var sandboxPermissions: SandboxPermissions
    var commandOrigin: ExecPolicyCommandOrigin
}

struct ExecPolicyCommands: Equatable {
    var commands: [[String]]
    var commandOrigin: ExecPolicyCommandOrigin
}

/// Rules-dir layer used in place of `ConfigLayerStack` until Phase 5.
public struct ExecPolicyLayer: Equatable, Sendable {
    public var rulesDir: String
    public var isUserOrProject: Bool

    public init(rulesDir: String, isUserOrProject: Bool) {
        self.rulesDir = rulesDir
        self.isUserOrProject = isUserOrProject
    }
}

public enum ExecPolicyError: Error, Equatable, CustomStringConvertible {
    case readDir(dir: String, message: String)
    case readFile(path: String, message: String)
    case parsePolicy(path: String, source: String, location: ErrorLocation?)

    public var description: String {
        switch self {
        case .readDir(let dir, let message):
            return "failed to read rules files from \(dir): \(message)"
        case .readFile(let path, let message):
            return "failed to read rules file \(path): \(message)"
        case .parsePolicy(let path, let source, _):
            return "failed to parse rules file \(path): \(source)"
        }
    }
}

public enum ExecPolicyUpdateError: Error, Equatable, CustomStringConvertible {
    case appendRule(path: String, message: String)
    case joinBlockingTask(String)
    case addRule(String)

    public var description: String {
        switch self {
        case .appendRule(let path, let message):
            return "failed to update rules file \(path): \(message)"
        case .joinBlockingTask(let message):
            return "failed to join blocking rules update task: \(message)"
        case .addRule(let message):
            return "failed to update in-memory rules: \(message)"
        }
    }
}

public enum ExecApprovalRequirement: Equatable, Sendable {
    case skip(bypassSandbox: Bool, proposedExecpolicyAmendment: ExecPolicyAmendment?)
    case needsApproval(reason: String?, proposedExecpolicyAmendment: ExecPolicyAmendment?)
    case forbidden(reason: String)
}

struct ExecApprovalRequest {
    var command: [String]
    var approvalPolicy: AskForApproval
    var permissionProfile: PermissionProfile
    var environmentPolicy: ExecPolicyRequirements?
    var windowsSandboxLevel: WindowsSandboxLevel
    var sandboxPermissions: SandboxPermissions
    var prefixRule: [String]?
    var allowPrefixRules: AllowPrefixRules
}

func childUsesParentExecPolicy(
    parentRulesDirs: [String],
    childRulesDirs: [String],
    parentIgnoreUserAndProjectRules: Bool,
    childIgnoreUserAndProjectRules: Bool,
    parentRequirements: ExecPolicyRequirements?,
    childRequirements: ExecPolicyRequirements?
) -> Bool {
    parentRulesDirs == childRulesDirs
        && parentIgnoreUserAndProjectRules == childIgnoreUserAndProjectRules
        && parentRequirements == childRequirements
}

func isPolicyMatch(_ ruleMatch: RuleMatch) -> Bool {
    switch ruleMatch {
    case .prefixRuleMatch: return true
    case .heuristicsRuleMatch: return false
    }
}

/// Returns a rejection reason when `approvalPolicy` disallows surfacing the
/// current prompt to the user.
func promptIsRejectedByPolicy(
    _ approvalPolicy: AskForApproval,
    promptIsRule: Bool
) -> String? {
    switch approvalPolicy {
    case .never:
        return PROMPT_CONFLICT_REASON
    case .onRequest, .unlessTrusted:
        return nil
    case .granular(let granularConfig):
        if promptIsRule {
            return granularConfig.allowsRulesApproval() ? nil : REJECT_RULES_APPROVAL_REASON
        }
        return granularConfig.allowsSandboxApproval() ? nil : REJECT_SANDBOX_APPROVAL_REASON
    }
}

public final class ExecPolicyManager: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Policy
    private let updateLock = NSLock()

    public init(_ policy: Policy) {
        stored = policy
    }

    public static func empty() -> ExecPolicyManager {
        ExecPolicyManager(Policy.empty())
    }

    static func load(
        layers: [ExecPolicyLayer],
        ignoreUserAndProjectRules: Bool = false,
        requirements: ExecPolicyRequirements? = nil
    ) async throws -> ExecPolicyManager {
        let (policy, warning) = try await loadExecPolicyWithWarning(
            layers: layers,
            ignoreUserAndProjectRules: ignoreUserAndProjectRules,
            requirements: requirements
        )
        if let warning {
            NSLog("failed to parse rules: \(warning)")
        }
        return ExecPolicyManager(policy)
    }

    public func current() -> Policy {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func store(_ policy: Policy) {
        lock.lock()
        stored = policy
        lock.unlock()
    }

    func createExecApprovalRequirementForCommand(
        _ req: ExecApprovalRequest
    ) async -> ExecApprovalRequirement {
        await createExecApprovalRequirementForCommandPlatform(req, DangerousCommandPlatform.host())
    }

    func createExecApprovalRequirementForCommandPlatform(
        _ req: ExecApprovalRequest,
        _ commandPlatform: DangerousCommandPlatform
    ) async -> ExecApprovalRequirement {
        let commands = commandsForExecPolicyForPlatform(req.command, commandPlatform)
        return await createExecApprovalRequirementForParsedCommands(
            req,
            commands,
            commandPlatform
        )
    }

    func createExecApprovalRequirementForParsedCommands(
        _ req: ExecApprovalRequest,
        _ parsed: ExecPolicyCommands,
        _ commandPlatform: DangerousCommandPlatform
    ) async -> ExecApprovalRequirement {
        let execPolicy = currentForEnvironment(req.environmentPolicy, req.allowPrefixRules)
        let autoAmendmentAllowed = req.allowPrefixRules == .honor
        let approvalPolicy = req.approvalPolicy
        let permissionProfile = req.permissionProfile
        let windowsSandboxLevel = req.windowsSandboxLevel
        let sandboxPermissions = req.sandboxPermissions
        let commandOrigin = parsed.commandOrigin
        let commands = parsed.commands
        let command = req.command
        let fallback: ([String]) -> Decision = { cmd in
            renderDecisionForUnmatchedCommandForPlatform(
                cmd,
                UnmatchedCommandContext(
                    approvalPolicy: approvalPolicy,
                    permissionProfile: permissionProfile,
                    windowsSandboxLevel: windowsSandboxLevel,
                    sandboxPermissions: sandboxPermissions,
                    commandOrigin: commandOrigin
                ),
                commandPlatform
            )
        }
        let matchOptions = MatchOptions(resolveHostExecutables: true)
        let evaluation = execPolicy.checkMultipleWithOptions(
            commands,
            heuristicsFallback: fallback,
            options: matchOptions
        )
        let requestedAmendment: ExecPolicyAmendment?
        if autoAmendmentAllowed {
            requestedAmendment = deriveRequestedExecpolicyAmendmentFromPrefixRule(
                req.prefixRule,
                evaluation.matchedRules,
                execPolicy,
                commands,
                fallback,
                matchOptions
            )
        } else {
            requestedAmendment = nil
        }

        switch evaluation.decision {
        case .forbidden:
            return .forbidden(
                reason: deriveForbiddenReason(
                    command,
                    evaluation,
                    dangerousCommandMatchForHeuristics(
                        evaluation,
                        .forbidden,
                        commandOrigin,
                        commandPlatform
                    )
                )
            )
        case .prompt:
            let promptIsRule = evaluation.matchedRules.contains { ruleMatch in
                isPolicyMatch(ruleMatch) && ruleMatch.decision() == .prompt
            }
            if let reason = promptIsRejectedByPolicy(approvalPolicy, promptIsRule: promptIsRule) {
                if promptIsRule {
                    return .forbidden(reason: reason)
                }
                return .forbidden(
                    reason: deriveRejectedPromptReason(
                        reason,
                        dangerousCommandMatchForHeuristics(
                            evaluation,
                            .prompt,
                            commandOrigin,
                            commandPlatform
                        )
                    )
                )
            }
            let proposed = requestedAmendment ?? {
                autoAmendmentAllowed
                    ? tryDeriveExecpolicyAmendmentForPromptRules(evaluation.matchedRules)
                    : nil
            }()
            return .needsApproval(
                reason: derivePromptReason(command, evaluation),
                proposedExecpolicyAmendment: proposed
            )
        case .allow:
            let bypassSandbox = commands.allSatisfy { segment in
                execPolicy
                    .matchesForCommandWithOptions(
                        segment,
                        heuristicsFallback: nil,
                        options: matchOptions
                    )
                    .contains { ruleMatch in
                        isPolicyMatch(ruleMatch) && ruleMatch.decision() == .allow
                    }
            }
            return .skip(
                bypassSandbox: bypassSandbox,
                proposedExecpolicyAmendment: autoAmendmentAllowed
                    ? tryDeriveExecpolicyAmendmentForAllowRules(evaluation.matchedRules)
                    : nil
            )
        }
    }

    func appendAmendmentAndUpdate(codexHome: String, amendment: ExecPolicyAmendment) async throws {
        updateLock.lock()
        defer { updateLock.unlock() }
        let policyPath = defaultPolicyPath(codexHome)
        do {
            try blockingAppendAllowPrefixRule(policyPath: policyPath, prefix: amendment.command)
        } catch {
            throw ExecPolicyUpdateError.appendRule(
                path: policyPath,
                message: String(describing: error)
            )
        }

        let currentPolicy = current()
        let matchOptions = MatchOptions(resolveHostExecutables: true)
        let existing = currentPolicy.checkMultipleWithOptions(
            [amendment.command],
            heuristicsFallback: { _ in .forbidden },
            options: matchOptions
        )
        let alreadyAllowed = existing.decision == .allow
            && existing.matchedRules.contains { ruleMatch in
                isPolicyMatch(ruleMatch) && ruleMatch.decision() == .allow
            }
        if alreadyAllowed { return }

        let updated = currentPolicy.clone()
        do {
            try updated.addPrefixRule(amendment.command, decision: .allow)
        } catch {
            throw ExecPolicyUpdateError.addRule(String(describing: error))
        }
        store(updated)
    }

    func appendNetworkRuleAndUpdate(
        codexHome: String,
        host: String,
        protocol_: NetworkRuleProtocol,
        decision: Decision,
        justification: String? = nil
    ) async throws {
        updateLock.lock()
        defer { updateLock.unlock() }
        let policyPath = defaultPolicyPath(codexHome)
        do {
            try blockingAppendNetworkRule(
                policyPath: policyPath,
                host: host,
                protocol_: protocol_,
                decision: decision,
                justification: justification
            )
        } catch {
            throw ExecPolicyUpdateError.appendRule(
                path: policyPath,
                message: String(describing: error)
            )
        }
        let updated = current().clone()
        do {
            try updated.addNetworkRule(
                host: host,
                protocol_: protocol_,
                decision: decision,
                justification: justification
            )
        } catch {
            throw ExecPolicyUpdateError.addRule(String(describing: error))
        }
        store(updated)
    }
}

func checkExecpolicyForWarnings(
    layers: [ExecPolicyLayer],
    ignoreUserAndProjectRules: Bool = false,
    requirements: ExecPolicyRequirements? = nil
) async throws -> ExecPolicyError? {
    let (_, warning) = try await loadExecPolicyWithWarning(
        layers: layers,
        ignoreUserAndProjectRules: ignoreUserAndProjectRules,
        requirements: requirements
    )
    return warning
}

func execPolicyMessageForDisplay(_ source: String) -> String {
    if let line = source.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("error: ") }) {
        return String(line)
    }
    if let firstLine = source.split(separator: "\n").first {
        let text = String(firstLine)
        if let range = text.range(of: ": starlark error: ", options: .backwards) {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
    return ""
}

func parseStarlarkLineFromMessage(_ message: String) -> (path: String, line: Int)? {
    guard let firstLine = message.split(separator: "\n").first else { return nil }
    let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
    guard let marker = trimmed.range(of: ": starlark error:", options: .backwards) else {
        return nil
    }
    let pathAndPosition = String(trimmed[..<marker.lowerBound])
    let parts = pathAndPosition.split(separator: ":").map(String.init)
    guard parts.count >= 3,
          let column = Int(parts[parts.count - 1]),
          let line = Int(parts[parts.count - 2]),
          line > 0 else {
        return nil
    }
    _ = column
    let path = parts.dropLast(2).joined(separator: ":")
    return (path, line)
}

public func formatExecPolicyErrorWithSource(_ error: ExecPolicyError) -> String {
    switch error {
    case .parsePolicy(let path, let source, let location):
        let structured: (String, Int)? = location.map { ($0.path, $0.range.start.line) }
        let parsed = parseStarlarkLineFromMessage(source)
        let resolved: (String, Int)?
        switch (structured, parsed) {
        case (.some((_, 1)), .some(let parsed)) where parsed.line > 1:
            resolved = parsed
        case (.some(let structured), _):
            resolved = structured
        case (.none, let parsed):
            resolved = parsed
        }
        let message = execPolicyMessageForDisplay(source)
        if let (locatedPath, line) = resolved {
            return "\(locatedPath):\(line): \(message) (problem is on or around line \(line))"
        }
        return "\(path): \(message)"
    default:
        return error.description
    }
}

func loadExecPolicyWithWarning(
    layers: [ExecPolicyLayer],
    ignoreUserAndProjectRules: Bool,
    requirements: ExecPolicyRequirements?
) async throws -> (Policy, ExecPolicyError?) {
    do {
        let policy = try await loadExecPolicy(
            layers: layers,
            ignoreUserAndProjectRules: ignoreUserAndProjectRules,
            requirements: requirements
        )
        return (policy, nil)
    } catch let error as ExecPolicyError {
        if case .parsePolicy = error {
            return (requirements?.policy.clone() ?? Policy.empty(), error)
        }
        throw error
    }
}

func loadExecPolicy(
    layers: [ExecPolicyLayer],
    ignoreUserAndProjectRules: Bool = false,
    requirements: ExecPolicyRequirements? = nil
) async throws -> Policy {
    var policyPaths: [String] = []
    for layer in layers {
        if ignoreUserAndProjectRules && layer.isUserOrProject {
            continue
        }
        policyPaths.append(contentsOf: try collectPolicyFiles(layer.rulesDir))
    }

    let parser = PolicyParser()
    for policyPath in policyPaths {
        let contents: String
        do {
            contents = try String(contentsOfFile: policyPath, encoding: .utf8)
        } catch {
            throw ExecPolicyError.readFile(path: policyPath, message: String(describing: error))
        }
        do {
            try parser.parse(policyIdentifier: policyPath, policyFileContents: contents)
        } catch let source as CodexExecPolicy.ExecPolicyError {
            throw ExecPolicyError.parsePolicy(
                path: policyPath,
                source: source.description,
                location: source.location
            )
        }
    }

    let policy = parser.build()
    guard let requirements else { return policy }
    return policy.mergeOverlay(requirements.policy)
}

func dangerousCommandMatchForOrigin(
    _ command: [String],
    _ commandOrigin: ExecPolicyCommandOrigin,
    _ commandPlatform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    switch commandOrigin {
    case .generic:
        return dangerousCommandMatchForPlatform(command, commandPlatform)
    case .powerShell:
        return dangerousPowershellWordsMatch(command, commandPlatform)
    }
}

func dangerousCommandMatchForHeuristics(
    _ evaluation: Evaluation,
    _ decision: Decision,
    _ commandOrigin: ExecPolicyCommandOrigin,
    _ commandPlatform: DangerousCommandPlatform
) -> DangerousCommandMatch? {
    for ruleMatch in evaluation.matchedRules {
        if case .heuristicsRuleMatch(let command, let matchedDecision) = ruleMatch,
           matchedDecision == decision {
            return dangerousCommandMatchForOrigin(command, commandOrigin, commandPlatform)
        }
    }
    return nil
}

func renderDecisionForUnmatchedCommand(
    _ command: [String],
    _ context: UnmatchedCommandContext
) -> Decision {
    renderDecisionForUnmatchedCommandForPlatform(command, context, DangerousCommandPlatform.host())
}

func renderDecisionForUnmatchedCommandForPlatform(
    _ command: [String],
    _ context: UnmatchedCommandContext,
    _ commandPlatform: DangerousCommandPlatform
) -> Decision {
    let dangerous = dangerousCommandMatchForOrigin(
        command,
        context.commandOrigin,
        commandPlatform
    )
    let fileSystemSandboxPolicy = context.permissionProfile.fileSystemSandboxPolicy()
    let windowsManagedFsRestrictionsWithoutSandboxBackend = false
    if dangerous != nil || windowsManagedFsRestrictionsWithoutSandboxBackend {
        switch context.approvalPolicy {
        case .never:
            return .forbidden
        case .onRequest, .unlessTrusted, .granular:
            return .prompt
        }
    }

    switch context.approvalPolicy {
    case .never:
        return .allow
    case .unlessTrusted:
        return .prompt
    case .onRequest:
        switch fileSystemSandboxPolicy.kind {
        case .unrestricted, .externalSandbox:
            return .allow
        case .restricted:
            return context.sandboxPermissions.requestsSandboxOverride ? .prompt : .allow
        }
    case .granular:
        switch fileSystemSandboxPolicy.kind {
        case .unrestricted, .externalSandbox:
            return .allow
        case .restricted:
            return context.sandboxPermissions.requestsSandboxOverride ? .prompt : .allow
        }
    }
}

func profileHasManagedFilesystemRestrictions(_ permissionProfile: PermissionProfile) -> Bool {
    let fileSystemSandboxPolicy = permissionProfile.fileSystemSandboxPolicy()
    if case .managed = permissionProfile,
       fileSystemSandboxPolicy.kind == .restricted,
       !fileSystemSandboxPolicy.hasFullDiskWriteAccess() {
        return true
    }
    return false
}

func defaultPolicyPath(_ codexHome: String) -> String {
    ((codexHome as NSString).appendingPathComponent(RULES_DIR_NAME) as NSString)
        .appendingPathComponent(DEFAULT_POLICY_FILE)
}

func commandsForExecPolicy(_ command: [String]) -> ExecPolicyCommands {
    commandsForExecPolicyForPlatform(command, DangerousCommandPlatform.host())
}

func commandsForExecPolicyForPlatform(
    _ command: [String],
    _ commandPlatform: DangerousCommandPlatform
) -> ExecPolicyCommands {
    if let commands = parseShellLcPlainCommands(command), !commands.isEmpty {
        return ExecPolicyCommands(commands: commands, commandOrigin: .generic)
    }
    if commandPlatform == .windows,
       let extracted = extractPowershellCommand(command) {
        return ExecPolicyCommands(
            commands: [extracted.script.split(separator: " ").map(String.init)],
            commandOrigin: .powerShell
        )
    }
    return ExecPolicyCommands(commands: [command], commandOrigin: .generic)
}

func tryDeriveExecpolicyAmendmentForPromptRules(
    _ matchedRules: [RuleMatch]
) -> ExecPolicyAmendment? {
    if matchedRules.contains(where: { isPolicyMatch($0) && $0.decision() == .prompt }) {
        return nil
    }
    for ruleMatch in matchedRules {
        if case .heuristicsRuleMatch(let command, .prompt) = ruleMatch {
            return ExecPolicyAmendment(command)
        }
    }
    return nil
}

func tryDeriveExecpolicyAmendmentForAllowRules(
    _ matchedRules: [RuleMatch]
) -> ExecPolicyAmendment? {
    if matchedRules.contains(where: isPolicyMatch) {
        return nil
    }
    for ruleMatch in matchedRules {
        if case .heuristicsRuleMatch(let command, .allow) = ruleMatch {
            return ExecPolicyAmendment(command)
        }
    }
    return nil
}

func deriveRequestedExecpolicyAmendmentFromPrefixRule(
    _ prefixRule: [String]?,
    _ matchedRules: [RuleMatch],
    _ execPolicy: Policy,
    _ commands: [[String]],
    _ execPolicyFallback: @escaping ([String]) -> Decision,
    _ matchOptions: MatchOptions
) -> ExecPolicyAmendment? {
    guard let prefixRule, !prefixRule.isEmpty else { return nil }
    if BANNED_PREFIX_SUGGESTIONS.contains(where: { $0 == prefixRule }) {
        return nil
    }
    if matchedRules.contains(where: isPolicyMatch) {
        return nil
    }
    let amendment = ExecPolicyAmendment(prefixRule)
    if prefixRuleWouldApproveAllCommands(
        execPolicy,
        prefixRule,
        commands,
        execPolicyFallback,
        matchOptions
    ) {
        return amendment
    }
    return nil
}

func prefixRuleWouldApproveAllCommands(
    _ execPolicy: Policy,
    _ prefixRule: [String],
    _ commands: [[String]],
    _ execPolicyFallback: @escaping ([String]) -> Decision,
    _ matchOptions: MatchOptions
) -> Bool {
    let policyWithPrefix = execPolicy.clone()
    do {
        try policyWithPrefix.addPrefixRule(prefixRule, decision: .allow)
    } catch {
        return false
    }
    return commands.allSatisfy { command in
        policyWithPrefix
            .checkWithOptions(command, heuristicsFallback: execPolicyFallback, options: matchOptions)
            .decision == .allow
    }
}

func derivePromptReason(_ commandArgs: [String], _ evaluation: Evaluation) -> String? {
    let command = renderShlexCommand(commandArgs)
    var best: (length: Int, justification: String?)?
    for ruleMatch in evaluation.matchedRules {
        if case .prefixRuleMatch(let matchedPrefix, .prompt, _, let justification) = ruleMatch {
            let candidate = (matchedPrefix.count, justification)
            if best == nil || candidate.0 > best!.length {
                best = candidate
            }
        }
    }
    guard let best else { return nil }
    if let justification = best.justification {
        return "`\(command)` requires approval: \(justification)"
    }
    return "`\(command)` requires approval by policy"
}

func deriveForbiddenReason(
    _ commandArgs: [String],
    _ evaluation: Evaluation,
    _ dangerousCommandMatch: DangerousCommandMatch?
) -> String {
    let command = renderShlexCommand(commandArgs)
    var best: (prefix: [String], justification: String?)?
    for ruleMatch in evaluation.matchedRules {
        if case .prefixRuleMatch(let matchedPrefix, .forbidden, _, let justification) = ruleMatch {
            if best == nil || matchedPrefix.count > best!.prefix.count {
                best = (matchedPrefix, justification)
            }
        }
    }
    if let best {
        if let justification = best.justification {
            return "`\(command)` rejected: \(justification)"
        }
        let prefix = renderShlexCommand(best.prefix)
        return "`\(command)` rejected: policy forbids commands starting with `\(prefix)`"
    }
    if let dangerousCommandMatch {
        return "`\(command)` rejected: \(dangerousCommandRejectionReason(dangerousCommandMatch))"
    }
    return "`\(command)` rejected: blocked by policy"
}

func deriveRejectedPromptReason(
    _ fallbackReason: String,
    _ dangerousCommandMatch: DangerousCommandMatch?
) -> String {
    switch dangerousCommandMatch {
    case .forcedRm:
        return dangerousCommandRejectionReason(.forcedRm)
    case .other, nil:
        return fallbackReason
    }
}

func dangerousCommandRejectionReason(_ match: DangerousCommandMatch) -> String {
    switch match {
    case .forcedRm:
        return "rm -f style commands are not permitted. Use a safer approach"
    case .other:
        return "blocked by policy"
    }
}

func renderShlexCommand(_ args: [String]) -> String {
    args.map(shlexQuote).joined(separator: " ")
}

func shlexQuote(_ token: String) -> String {
    if token.isEmpty { return "''" }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:@+"))
    if token.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
        return token
    }
    return "'\(token.replacingOccurrences(of: "'", with: "'\\''"))'"
}

func collectPolicyFiles(_ dir: String) throws -> [String] {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if !fileManager.fileExists(atPath: dir, isDirectory: &isDirectory) {
        return []
    }
    if !isDirectory.boolValue {
        throw ExecPolicyError.readDir(dir: dir, message: "not a directory")
    }
    let entries: [String]
    do {
        entries = try fileManager.contentsOfDirectory(atPath: dir)
    } catch {
        throw ExecPolicyError.readDir(dir: dir, message: String(describing: error))
    }
    var policyPaths: [String] = []
    for entry in entries {
        let path = (dir as NSString).appendingPathComponent(entry)
        var isFile: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isFile), !isFile.boolValue else {
            continue
        }
        if (path as NSString).pathExtension == RULE_EXTENSION {
            policyPaths.append(path)
        }
    }
    policyPaths.sort()
    return policyPaths
}

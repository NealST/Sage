//
//  executable_identity.swift
//  Sage
//
//  Port of codex-rs/core/src/exec_policy/executable_identity.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Unix `/bin` and `/usr/bin` identity matches upstream. Windows
//  SystemRoot matching is excluded(platform). `UnifiedExecShellMode.zshFork`
//  is a tag without `ZshForkConfig` until Phase 4 tools land.
//

import CodexShellCommand
import Foundation

extension ExecPolicyManager {
    func createExecApprovalRequirementForShell(
        _ request: ExecApprovalRequest,
        configuredShell: Shell,
        shellMode: UnifiedExecShellMode,
        commandPlatform: DangerousCommandPlatform
    ) async -> ExecApprovalRequirement {
        var request = request
        let command = request.command
        let executable = shellApprovalCommand(command, configuredShell, shellMode)
        if executable.count == command.count {
            return await createExecApprovalRequirementForCommandPlatform(request, commandPlatform)
        }

        var policyCommands: ExecPolicyCommands
        if commandPlatform == .windows, let extracted = extractPowershellCommand(command) {
            policyCommands = ExecPolicyCommands(
                commands: [extracted.script.split(separator: " ").map(String.init)],
                commandOrigin: .powerShell
            )
        } else {
            policyCommands = commandsForExecPolicyForPlatform(command, commandPlatform)
        }

        policyCommands.commands.insert(executable, at: 0)
        request.command = executable
        return await createExecApprovalRequirementForParsedCommands(
            request,
            policyCommands,
            commandPlatform
        )
    }
}

func shellApprovalCommand(
    _ command: [String],
    _ configuredShell: Shell,
    _ shellMode: UnifiedExecShellMode
) -> [String] {
    guard let executable = command.first else { return command }
    let parent = (executable as NSString).deletingLastPathComponent
    let isSystemShell = parent == "/bin" || parent == "/usr/bin"
    let isConfiguredShell = executable == configuredShell.shellPath
    if isConfiguredShell || isSystemShell || shellMode == .zshFork {
        return command
    }
    return [executable]
}

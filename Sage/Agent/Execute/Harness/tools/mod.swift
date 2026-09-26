//
//  mod.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Feature flags and TurnContext wait for Phase 5. Tool-mode helpers take
//  the requested mode directly.
//

import CodexCore
import CodexProtocol
import CodexShellCommand
import CodexUtils
import Foundation

func flatToolName(_ toolName: ToolName) -> String {
    if toolName.isDefaultNamespace() {
        return toolName.name
    }
    if let namespace = toolName.namespace {
        return namespace + toolName.name
    }
    return toolName.name
}

func toolUserShellType(_ shell: Shell) -> String {
    switch shell.shellType {
    case .zsh: return "zsh"
    case .bash: return "bash"
    case .powerShell: return "powershell"
    case .sh: return "sh"
    case .cmd: return "cmd"
    }
}

func effectiveToolMode(requested: ToolMode, codeModeAvailable: Bool, disableInProcessFallback: Bool) -> ToolMode {
    if !codeModeAvailable && requested == .codeMode && !disableInProcessFallback {
        return .direct
    }
    return requested
}

func formatExecOutputForModel(
    _ execOutput: ExecToolCallOutput,
    truncationPolicy: TruncationPolicy
) -> String {
    let durationSeconds = (durationSecondsValue(execOutput.duration) * 10).rounded() / 10
    let content = buildContentWithTimeout(execOutput)
    let totalLines = content.split(separator: "\n", omittingEmptySubsequences: false).count
    let formatted = formattedTruncateText(content: content, byteBudget: truncationPolicy.byteBudget)
    var sections = [
        "Exit code: \(execOutput.exitCode)",
        "Wall time: \(durationSeconds) seconds",
    ]
    if totalLines != formatted.split(separator: "\n", omittingEmptySubsequences: false).count {
        sections.append("Total output lines: \(totalLines)")
    }
    sections.append("Output:")
    sections.append(formatted)
    return sections.joined(separator: "\n")
}

func formatExecOutputStr(
    _ execOutput: ExecToolCallOutput,
    truncationPolicy: TruncationPolicy
) -> String {
    formattedTruncateText(content: buildContentWithTimeout(execOutput), byteBudget: truncationPolicy.byteBudget)
}

func buildContentWithTimeout(_ execOutput: ExecToolCallOutput) -> String {
    if execOutput.timedOut {
        let millis = Int((durationSecondsValue(execOutput.duration) * 1000).rounded())
        return "command timed out after \(millis) milliseconds\n\(execOutput.aggregatedOutput.text)"
    }
    return execOutput.aggregatedOutput.text
}

func durationSecondsValue(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}

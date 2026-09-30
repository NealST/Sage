//
//  user_shell_command.swift
//  Sage
//
//  Port of codex-rs/core/src/user_shell_command.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Formats a user-shell command record. Contextual fragments / TurnContext
//  stay out; the record is the payload later session wiring wraps.
//

import CodexProtocol
import Foundation

struct UserShellCommandRecord: Equatable, Sendable {
    var command: String
    var exitCode: Int32
    var duration: Duration
    var output: String
}

func userShellCommandRecord(
    command: String,
    execOutput: ExecToolCallOutput,
    truncatedOutput: String
) -> UserShellCommandRecord {
    UserShellCommandRecord(
        command: command,
        exitCode: execOutput.exitCode,
        duration: execOutput.duration,
        output: truncatedOutput
    )
}

func formatUserShellCommandRecord(_ record: UserShellCommandRecord) -> String {
    let status = record.exitCode == 0 ? "ok" : "exit \(record.exitCode)"
    return "$ \(record.command)\n[\(status)]\n\(record.output)"
}

func userShellCommandRecordItem(_ record: UserShellCommandRecord) -> ResponseItem {
    .message(
        id: nil,
        role: "user",
        content: [.inputText(text: formatUserShellCommandRecord(record))],
        phase: nil,
        internalChatMessageMetadataPassthrough: nil
    )
}

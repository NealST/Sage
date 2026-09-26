//
//  unified_exec_shell_snapshot.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/shell_snapshot.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  R4a: basename `shell_snapshot.swift` is taken by core/src/shell_snapshot.rs.
//  `Session.prewarm_shell_snapshots` waits on Phase 5 session + exec-server.
//  Request construction is kept so later wiring can call it.
//

import CodexProtocol
import CodexSandboxing
import CodexShellCommand
import CodexUtils
import Foundation

func shellSnapshotRequest(
    request: ExecCommandRequest,
    cwd: PathUri,
    snapshotSupported: Bool,
    featureEnabled: Bool
) -> ShellSnapshotRequest? {
    if !featureEnabled
        || !snapshotSupported
        || request.cwd != cwd
        || request.shellMode != .direct
        || ![.bash, .zsh, .sh].contains(request.shellType)
        || request.command.count < 2
        || request.command[1] != "-lc" {
        return nil
    }
    guard let path = request.command.first else { return nil }
    return ShellSnapshotRequest(
        scopeId: request.processId.description,
        shellName: request.shellType.name(),
        shellPath: path
    )
}

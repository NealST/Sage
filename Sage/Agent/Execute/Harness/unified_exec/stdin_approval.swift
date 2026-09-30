//
//  stdin_approval.swift
//  Sage
//
//  Port of codex-rs/core/src/unified_exec/stdin_approval.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Permission snapshots and review text match upstream. `StdinApprovalNeed`
//  is the portable ApprovalAction payload; HUD / Guardian consume it. A
//  needed review is thrown, never waited on inside `runTurn`.
//

import CodexProtocol
import CodexSandboxing
import CodexUtils
import Foundation

enum TerminalSandboxSource: Equatable, Sendable {
    case native
    case executor
}

struct StdinApprovalNeed: Equatable, Sendable {
    var callId: String
    var processId: Int32
    var input: String
    var cwd: PathUri
    var tty: Bool
    var sandboxPermissions: SandboxPermissions
    var reason: String
}

struct TerminalPermissions {
    var sandboxSource: TerminalSandboxSource
    var launchPermissions: SandboxPermissions
    var additionalPermissions: AdditionalPermissionProfile?
    var internalPermissions: AdditionalPermissionProfile?
    var launchProfile: PermissionProfile

    static func nativeDefault() -> TerminalPermissions {
        TerminalPermissions(
            sandboxSource: .native,
            launchPermissions: .useDefault,
            additionalPermissions: nil,
            internalPermissions: nil,
            launchProfile: .disabled
        )
    }

    func reviewRequirement(
        current: PermissionProfile,
        baseline: PermissionProfile
    ) -> Result<SandboxPermissions, UnifiedExecError> {
        let bypassed = launchPermissions.requiresEscalatedPermissions
        if baseline.fileSystemSandboxPolicy().hasDeniedReadRestrictions()
            && (bypassed || launchProfile != current) {
            return .failure(.stdinApproval(
                "this terminal cannot enforce the current denied-read restrictions; start a new terminal"
            ))
        }
        if bypassed || launchProfile != current {
            return .success(.requireEscalated)
        }
        if launchProfile == baseline {
            return .success(.useDefault)
        }
        return .success(.withAdditionalPermissions)
    }

    func approvalReason(_ sandboxPermissions: SandboxPermissions) -> String {
        let authority: String
        if launchPermissions.requiresEscalatedPermissions {
            authority = "This terminal was launched outside the sandbox, bypassing any managed network proxy."
        } else if launchProfile == .disabled {
            authority = "This terminal runs without a filesystem sandbox."
        } else {
            switch sandboxPermissions {
            case .useDefault:
                authority = "This terminal uses the current permissions."
            case .withAdditionalPermissions:
                authority = "This terminal retains additional permissions."
            case .requireEscalated:
                authority = "This terminal retains sandbox or network settings that differ from the current permissions."
            }
        }
        var reason = "Send input to an existing terminal. \(authority)"
        if internalPermissions != nil {
            reason += " It also has an internal filesystem grant."
        }
        reason += " The cwd is its launch directory; the terminal's current directory and state may have changed."
        if let grants = additionalPermissions,
           let data = try? JSONEncoder().encode(grants),
           let text = String(data: data, encoding: .utf8) {
            reason += " Retained grants: \(text)."
        }
        return reason
    }
}

func decideStdinApproval(
    input: String,
    processId: Int32,
    tty: Bool,
    cwd: PathUri,
    callId: String,
    permissions: TerminalPermissions,
    current: PermissionProfile,
    writeStdinApprovalEnabled: Bool,
    strictAutoReview: Bool
) -> Result<StdinApprovalNeed?, UnifiedExecError> {
    if input.isEmpty || (!tty && input == "\u{3}") || !writeStdinApprovalEnabled {
        return .success(nil)
    }
    switch permissions.reviewRequirement(current: current, baseline: current) {
    case .failure(let reason):
        return .failure(reason)
    case .success(let sandboxPermissions):
        if sandboxPermissions == .useDefault && !strictAutoReview {
            return .success(nil)
        }
        if input.contains("\0") {
            return .failure(.stdinApproval(
                "terminal input contains a NUL byte and cannot be reviewed safely"
            ))
        }
        return .success(
            StdinApprovalNeed(
                callId: callId,
                processId: processId,
                input: input,
                cwd: cwd,
                tty: tty,
                sandboxPermissions: sandboxPermissions,
                reason: permissions.approvalReason(sandboxPermissions)
            )
        )
    }
}

extension ProcessEntry {
    func stdinApproval(
        input: String,
        current: PermissionProfile,
        writeStdinApprovalEnabled: Bool,
        strictAutoReview: Bool
    ) -> Result<StdinApprovalNeed?, UnifiedExecError> {
        decideStdinApproval(
            input: input,
            processId: processId,
            tty: tty,
            cwd: cwd,
            callId: callId,
            permissions: permissions,
            current: current,
            writeStdinApprovalEnabled: writeStdinApprovalEnabled,
            strictAutoReview: strictAutoReview
        )
    }
}

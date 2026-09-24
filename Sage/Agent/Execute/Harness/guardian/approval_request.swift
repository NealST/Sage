//
//  approval_request.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/approval_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//

import Foundation

enum GuardianApprovalRequest: Sendable, Equatable {
    case execCommand(id: String, command: String, cwd: URL, permissionBits: SandboxPermissionBits)
    case applyPatch(id: String, cwd: URL, files: [URL], patch: String)
    case networkAccess(id: String, host: String)

    static func from(_ action: ApprovalAction) -> Self {
        switch action {
        case .execCommand(let id, let command, let cwd, let bits):
            return .execCommand(id: id, command: command, cwd: cwd, permissionBits: bits)

        case .applyPatch(let id, let cwd, let files, let patch):
            return .applyPatch(id: id, cwd: cwd, files: files, patch: patch)
        }
    }

    func pretty() -> String {
        switch self {
        case .execCommand(_, let command, let cwd, let bits):
            return """
            exec_command
            cwd: \(cwd.path)
            permissions: \(bits.rawValue)
            command:
            \(command)
            """

        case .applyPatch(_, let cwd, let files, let patch):
            let list = files.map(\.path).joined(separator: "\n")
            return """
            apply_patch
            cwd: \(cwd.path)
            files:
            \(list)
            patch:
            \(patch)
            """

        case .networkAccess(_, let host):
            return "network_access\nhost: \(host)"
        }
    }
}

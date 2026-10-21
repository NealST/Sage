//
//  config_permissions.swift
//  Sage
//
//  Port of codex-rs/core/src/config/permissions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import SageProtocol
import Foundation

struct Permissions: Equatable, Sendable {
    var approvalPolicy: SageProtocol.AskForApproval
    var permissionProfile: PermissionProfile
    var sandboxMode: SandboxMode

    init(
        approvalPolicy: SageProtocol.AskForApproval = SageProtocol.AskForApproval.onRequest,
        permissionProfile: PermissionProfile = .readOnly(),
        sandboxMode: SandboxMode = .readOnly
    ) {
        self.approvalPolicy = approvalPolicy
        self.permissionProfile = permissionProfile
        self.sandboxMode = sandboxMode
    }
}

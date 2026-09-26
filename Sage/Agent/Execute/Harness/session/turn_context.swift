//
//  turn_context.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Turn-scoped settings and environment. Shell snapshot futures and
//  plugin metrics wait for Phase 6/9.
//

import CodexCore
import CodexProtocol
import Foundation

struct TurnEnvironment: Sendable {
    var environmentId: String
    var cwd: String
    var userHomeDir: String?
    var executorPlatformOS: String?

    init(
        environmentId: String = "local",
        cwd: String = FileManager.default.currentDirectoryPath,
        userHomeDir: String? = NSHomeDirectory(),
        executorPlatformOS: String? = "macos"
    ) {
        self.environmentId = environmentId
        self.cwd = cwd
        self.userHomeDir = userHomeDir
        self.executorPlatformOS = executorPlatformOS
    }
}

final class TurnContext: @unchecked Sendable {
    var subId: String
    var sessionId: SessionId
    var threadId: ThreadId
    var cwd: String
    var model: String
    var approvalPolicy: CodexProtocol.AskForApproval
    var sandboxPolicy: SandboxPolicy
    var permissionProfile: PermissionProfile
    var disabledPluginIds: [String]
    var collaborationMode: CollaborationMode?
    var environment: TurnEnvironment
    var finalOutputJsonSchema: String?
    var cyberAccessProgram: Bool
    var nextStepSettings: StepSettings

    init(
        subId: String = UUID().uuidString,
        sessionId: SessionId = SessionId(),
        threadId: ThreadId = ThreadId(),
        cwd: String = FileManager.default.currentDirectoryPath,
        model: String = "gpt-5",
        approvalPolicy: CodexProtocol.AskForApproval = CodexProtocol.AskForApproval.onRequest,
        sandboxPolicy: SandboxPolicy = .readOnly(networkAccess: false),
        permissionProfile: PermissionProfile = .readOnly(),
        disabledPluginIds: [String] = [],
        collaborationMode: CollaborationMode? = nil,
        environment: TurnEnvironment = TurnEnvironment(),
        finalOutputJsonSchema: String? = nil,
        cyberAccessProgram: Bool = false,
        nextStepSettings: StepSettings = StepSettings()
    ) {
        self.subId = subId
        self.sessionId = sessionId
        self.threadId = threadId
        self.cwd = cwd
        self.model = model
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfile = permissionProfile
        self.disabledPluginIds = disabledPluginIds
        self.collaborationMode = collaborationMode
        self.environment = environment
        self.finalOutputJsonSchema = finalOutputJsonSchema
        self.cyberAccessProgram = cyberAccessProgram
        self.nextStepSettings = nextStepSettings
    }

    func collaborationModeValue() -> CollaborationMode? {
        collaborationMode
    }
}

struct NewTurnContextOptions: Sendable {
    var subId: String?
    var model: String?

    init(subId: String? = nil, model: String? = nil) {
        self.subId = subId
        self.model = model
    }
}

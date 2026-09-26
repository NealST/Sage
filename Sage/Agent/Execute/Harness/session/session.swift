//
//  session.swift
//  Sage
//
//  Port of codex-rs/core/src/session/session.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session type shape and configuration. The 1,928-line mutex/event loop
//  is Session-aware and is filled as remaining Phase 5 files land. Phase 4
//  handlers stay Session-free and talk through ToolInvocation callbacks.
//

import CodexCore
import CodexProtocol
import Foundation

struct TurnEnvironmentSelection: Equatable, Sendable {
    var environmentId: String

    init(environmentId: String = "local") {
        self.environmentId = environmentId
    }
}

struct DynamicToolSpec: Equatable, Sendable {
    var name: String

    init(name: String) {
        self.name = name
    }
}

final class SessionConfiguration: @unchecked Sendable {
    var stepSettings: StepSettings
    var environments: [TurnEnvironmentSelection]
    var developerInstructions: String?
    var baseInstructions: String
    var allowLoginShell: Bool
    var shellEnvironmentPolicy: ShellEnvironmentPolicy
    var legacyFallbackCwd: String
    var runtimeWorkspaceRoots: [String]
    var codexHome: String
    var threadName: String?
    var disabledPluginIds: [String]
    var originalConfig: Config
    var sessionSource: SessionSource
    var parentThreadId: ThreadId?
    var forkedFromThreadId: ThreadId?
    var dynamicTools: [DynamicToolSpec]
    var trustedGuardianReviewer: Bool

    init(
        stepSettings: StepSettings = StepSettings(),
        environments: [TurnEnvironmentSelection] = [],
        developerInstructions: String? = nil,
        baseInstructions: String = "",
        allowLoginShell: Bool = false,
        shellEnvironmentPolicy: ShellEnvironmentPolicy = ShellEnvironmentPolicy(),
        legacyFallbackCwd: String = FileManager.default.currentDirectoryPath,
        runtimeWorkspaceRoots: [String] = [],
        codexHome: String = NSHomeDirectory() + "/.codex",
        threadName: String? = nil,
        disabledPluginIds: [String] = [],
        originalConfig: Config = Config(),
        sessionSource: SessionSource = .cli,
        parentThreadId: ThreadId? = nil,
        forkedFromThreadId: ThreadId? = nil,
        dynamicTools: [DynamicToolSpec] = [],
        trustedGuardianReviewer: Bool = false
    ) {
        self.stepSettings = stepSettings
        self.environments = environments
        self.developerInstructions = developerInstructions
        self.baseInstructions = baseInstructions
        self.allowLoginShell = allowLoginShell
        self.shellEnvironmentPolicy = shellEnvironmentPolicy
        self.legacyFallbackCwd = legacyFallbackCwd
        self.runtimeWorkspaceRoots = runtimeWorkspaceRoots
        self.codexHome = codexHome
        self.threadName = threadName
        self.disabledPluginIds = disabledPluginIds
        self.originalConfig = originalConfig
        self.sessionSource = sessionSource
        self.parentThreadId = parentThreadId
        self.forkedFromThreadId = forkedFromThreadId
        self.dynamicTools = dynamicTools
        self.trustedGuardianReviewer = trustedGuardianReviewer
    }

    var cwd: String { legacyFallbackCwd }
}

final class Session: @unchecked Sendable {
    var threadId: ThreadId
    var installationId: String
    var state: SessionState
    var activeTurn: ActiveTurn?
    var services: SessionServices
    var inputQueue: InputQueue
    var features: Features

    init(
        threadId: ThreadId = ThreadId(),
        installationId: String = "sage",
        configuration: SessionConfiguration = SessionConfiguration(),
        services: SessionServices = SessionServices(),
        features: Features = Features()
    ) {
        self.threadId = threadId
        self.installationId = installationId
        self.state = SessionState(sessionConfiguration: configuration)
        self.services = services
        self.inputQueue = InputQueue()
        self.features = features
    }

    func isInterrupted() -> Bool {
        activeTurn?.task?.done == true
    }

    func markMcpRuntimeDirty() {}

    func hooks() -> HookSnapshot {
        HookSnapshot()
    }

    func refreshHooks(_ config: Config) async {}

    func refreshMcpIfDirty() async {}
}

struct HookSnapshot: Sendable {
    init() {}

    func matchesPluginHooks(_ sources: [String], _ warnings: [String]) -> Bool {
        true
    }
}

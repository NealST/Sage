//
//  environment_selection.swift
//  CodexCore
//
//  Port of codex-rs/core/src/environment_selection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Origin, root-combining, ID/cwd validation, and snapshot projection are
//  faithful. Live EnvironmentManager / exec-server connections wait.
//  `ThreadEnvironmentDefaults` is inlined from session/environment.rs
//  because CodexCore stays Session-free.
//

import CodexProtocol
import CodexUtils
import Foundation
import os

public let LOCAL_ENVIRONMENT_ID = "local"
public let MAX_SELECTED_CAPABILITY_ROOTS = 256
let MAX_TURN_ENVIRONMENT_CWD_BYTES = 8 * 1024

/// Records whether a normalized config should follow later thread setting updates.
public enum EnvironmentConfigOrigin: Equatable, Sendable {
    case thread
    case owner

    /// Reconstructs the input form so another attachment boundary preserves config ownership.
    public func intoInputSelection(_ selection: TurnEnvironmentSelection) -> TurnEnvironmentSelection {
        var selection = selection
        if self == .thread {
            selection.config = .fromThread
        }
        return selection
    }

    public func selectedCapabilityRoots(
        threadRoots: [SelectedCapabilityRoot],
        ownerRoots: [SelectedCapabilityRoot]
    ) -> [SelectedCapabilityRoot] {
        switch self {
        case .thread:
            return threadRoots
        case .owner:
            return ownerRoots
        }
    }
}

/// Combines persisted thread roots with attachment roots in selection order.
///
/// Thread-owned attachments still rely on roots reported by legacy executors. A matching live root
/// refreshes the persisted location while explicit owner configuration retains the existing
/// thread-first collision behavior.
public func combineSelectedCapabilityRoots(
    threadRoots: [SelectedCapabilityRoot],
    sources: [(EnvironmentConfigOrigin, [SelectedCapabilityRoot])]
) -> [SelectedCapabilityRoot] {
    let attachmentRoots = sources.flatMap { origin, roots in
        roots.map { (origin, $0) }
    }
    var combinedRoots = threadRoots.map { threadRoot in
        guard case .environment(let threadEnvironmentId, _) = threadRoot.location else {
            return threadRoot
        }
        return attachmentRoots.first { origin, attachmentRoot in
            if origin != .thread || attachmentRoot.id != threadRoot.id {
                return false
            }
            guard case .environment(let attachmentEnvironmentId, _) = attachmentRoot.location else {
                return false
            }
            return attachmentEnvironmentId == threadEnvironmentId
        }?.1 ?? threadRoot
    }
    combinedRoots.append(contentsOf: attachmentRoots.map(\.1))
    return combinedRoots
}

public func defaultThreadEnvironmentSelections(
    defaultEnvironmentIds: [String],
    cwd: AbsolutePathBuf,
    workspaceRoots: [AbsolutePathBuf]
) -> [TurnEnvironmentSelection] {
    let cwdUri = PathUri.fromAbsPath(cwd)
    let rootUris = workspaceRoots.map(PathUri.fromAbsPath)
    return defaultEnvironmentIds.map { environmentId in
        TurnEnvironmentSelection(
            environmentId: environmentId,
            cwd: cwdUri,
            workspaceRoots: rootUris,
            config: .fromThread
        )
    }
}

/// Checks that environment IDs are registered and unique and that working directories are not too long.
public func validateEnvironmentIdsAndCwds(
    knownEnvironmentIds: Set<String>,
    environments: [TurnEnvironmentSelection]
) throws {
    var environmentIds = Set<String>()
    environmentIds.reserveCapacity(environments.count)
    for environment in environments {
        if environment.cwd.inferredNativePathString().utf8.count > MAX_TURN_ENVIRONMENT_CWD_BYTES {
            throw CodexErr.invalidRequest(
                "turn environment working directory exceeds the maximum size"
            )
        }
        if !environmentIds.insert(environment.environmentId).inserted {
            throw CodexErr.invalidRequest(
                "duplicate turn environment id `\(environment.environmentId)`"
            )
        }
        if !knownEnvironmentIds.contains(environment.environmentId) {
            throw CodexErr.invalidRequest(
                "unknown turn environment id `\(environment.environmentId)`"
            )
        }
    }
}

/// Defaults for environments that inherit their configuration from the running turn.
public struct ThreadEnvironmentDefaults: Equatable, Sendable {
    public var common: EnvironmentConfig
    public var localWindowsSandboxType: SandboxType

    public init(common: EnvironmentConfig, localWindowsSandboxType: SandboxType) {
        self.common = common
        self.localWindowsSandboxType = localWindowsSandboxType
    }

    public func forSelection(_ selection: TurnEnvironmentSelection) -> EnvironmentConfig {
        var config = common
        config.workspaceRoots = selection.workspaceRoots
        if selection.environmentId == LOCAL_ENVIRONMENT_ID {
            config.windowsSandboxType = localWindowsSandboxType
        }
        return config
    }
}

/// Uses the current thread defaults when requested and records who owns later config updates.
public func resolveSelectionConfig(
    _ selection: TurnEnvironmentSelection,
    defaults: ThreadEnvironmentDefaults
) -> (TurnEnvironmentSelection, EnvironmentConfigOrigin) {
    var selection = selection
    let origin: EnvironmentConfigOrigin
    switch selection.config {
    case .fromThread:
        selection.config = .ready(defaults.forSelection(selection))
        origin = .thread
    case .ready, .pending, .failed:
        origin = .owner
    }
    return (selection, origin)
}

public func ensureConfigsStayOwnerProvided(
    current: [TurnEnvironmentSelection],
    proposed: [TurnEnvironmentSelection]
) throws {
    if let environment = proposed.first(where: { environment in
        environment.config == .fromThread
            && current.contains { current in
                current.environmentId == environment.environmentId
                    && current.config != .fromThread
            }
    }) {
        throw CodexErr.invalidRequest(
            "owner-provided environment configuration required for `\(environment.environmentId)`"
        )
    }
}

public func validateEnvironmentConfig(
    _ selection: TurnEnvironmentSelection,
    _ config: EnvironmentConfig
) throws {
    if config.networkPolicy != nil, selection.environmentId == LOCAL_ENVIRONMENT_ID {
        throw CodexErr.invalidRequest(
            "attachment-owned network policy requires a remote executor"
        )
    }
    if config.selectedCapabilityRoots.count > MAX_SELECTED_CAPABILITY_ROOTS {
        throw CodexErr.invalidRequest(
            "environment readiness contains more than \(MAX_SELECTED_CAPABILITY_ROOTS) selected capability roots"
        )
    }
    var rootIds = Set<String>()
    rootIds.reserveCapacity(config.selectedCapabilityRoots.count)
    for root in config.selectedCapabilityRoots {
        guard case .environment(let environmentId, _) = root.location else { continue }
        if root.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || environmentId != selection.environmentId
            || !rootIds.insert(root.id).inserted
        {
            throw CodexErr.invalidRequest(
                "selected capability roots must have unique non-empty IDs and belong to environment `\(selection.environmentId)`"
            )
        }
    }
}

public func validateEnvironmentConfigs(_ selections: [TurnEnvironmentSelection]) throws {
    for selection in selections {
        if case .ready(let config) = selection.config {
            try validateEnvironmentConfig(selection, config)
        }
    }
}

public struct SelectedEnvironmentBinding: Equatable {
    public var selection: TurnEnvironmentSelection
    public var configOrigin: EnvironmentConfigOrigin
    public var isRemote: Bool

    public init(
        selection: TurnEnvironmentSelection,
        configOrigin: EnvironmentConfigOrigin,
        isRemote: Bool
    ) {
        self.selection = selection
        self.configOrigin = configOrigin
        self.isRemote = isRemote
    }

    public func selectionValue() -> TurnEnvironmentSelection { selection }
}

public struct StartingTurnEnvironment: Equatable {
    public var selection: TurnEnvironmentSelection
    public var configOrigin: EnvironmentConfigOrigin

    public init(selection: TurnEnvironmentSelection, configOrigin: EnvironmentConfigOrigin) {
        self.selection = selection
        self.configOrigin = configOrigin
    }
}

public enum TurnEnvironmentState: Equatable {
    case ready(SelectedEnvironmentBinding)
    case starting(StartingTurnEnvironment)
    case failed(selection: TurnEnvironmentSelection, error: String)
}

/// Existing environment bindings captured for a turn.
public struct TurnEnvironmentSnapshot: Equatable {
    public var environments: [TurnEnvironmentState]

    public init(environments: [TurnEnvironmentState] = []) {
        self.environments = environments
    }

    public func hasFullAccess(
        approvalPolicy: AskForApproval,
        threadProfile: PermissionProfile
    ) -> Bool {
        CodexProtocol.hasFullAccess(
            approvalPolicy: approvalPolicy,
            threadProfile: threadProfile,
            environments: refreshReadiness().environments.map { environment in
                switch environment {
                case .ready(let binding):
                    return binding.selection.config
                case .starting, .failed:
                    return .pending
                }
            }
        )
    }

    /// Promotes completed startup work without adopting newer thread selections.
    /// Without exec-server resolution, starting entries stay starting.
    public func refreshReadiness() -> TurnEnvironmentSnapshot {
        TurnEnvironmentSnapshot(environments: environments)
    }

    public func turnEnvironments() -> [SelectedEnvironmentBinding] {
        environments.compactMap { environment in
            if case .ready(let binding) = environment { return binding }
            return nil
        }
    }

    public func starting() -> [StartingTurnEnvironment] {
        environments.compactMap { environment in
            if case .starting(let starting) = environment { return starting }
            return nil
        }
    }

    public func primary() -> SelectedEnvironmentBinding? {
        turnEnvironments().first
    }

    public func primaryWorkspaceRootUris() -> [PathUri] {
        let selection: TurnEnvironmentSelection?
        switch environments.first {
        case .ready(let binding):
            selection = binding.selection
        case .starting(let starting):
            selection = starting.selection
        case .failed(let failed, _):
            selection = failed
        case nil:
            return []
        }
        return selection?.workspaceRoots ?? []
    }

    public func primaryWorkspaceRoots() -> [AbsolutePathBuf] {
        primaryWorkspaceRootUris().compactMap { try? $0.toAbsPath() }
    }

    public func local() -> SelectedEnvironmentBinding? {
        turnEnvironments().first { !$0.isRemote }
    }

    public func localEnvironmentCwd() -> AbsolutePathBuf? {
        for environment in environments {
            switch environment {
            case .ready(let binding) where !binding.isRemote:
                return try? binding.selection.cwd.toAbsPath()
            case .starting(let starting) where starting.selection.environmentId == LOCAL_ENVIRONMENT_ID:
                return try? starting.selection.cwd.toAbsPath()
            default:
                continue
            }
        }
        return nil
    }

    public func toSelections() -> [TurnEnvironmentSelection] {
        turnEnvironments().map(\.selection)
    }

    /// Returns every captured selection, including those still starting or unable to connect.
    public func allSelections() -> [TurnEnvironmentSelection] {
        environments.map { environment in
            switch environment {
            case .ready(let binding):
                return binding.selectionValue()
            case .starting(let starting):
                return starting.configOrigin.intoInputSelection(starting.selection)
            case .failed(let selection, _):
                return selection
            }
        }
    }

    public func singleLocalEnvironment() -> SelectedEnvironmentBinding? {
        if !starting().isEmpty { return nil }
        let ready = turnEnvironments()
        guard ready.count == 1, let environment = ready.first, !environment.isRemote else {
            return nil
        }
        return environment
    }

    public func singleLocalEnvironmentCwd() -> AbsolutePathBuf? {
        try? singleLocalEnvironment()?.selection.cwd.toAbsPath()
    }
}

public func primaryConfigFor(
    _ selections: [TurnEnvironmentSelection]
) -> EnvironmentConfig? {
    guard let first = selections.first else { return nil }
    if case .ready(let config) = first.config {
        return config
    }
    return nil
}

public func primaryWorkspaceRootsFor(
    _ selections: [TurnEnvironmentSelection]
) -> [AbsolutePathBuf] {
    guard let first = selections.first else { return [] }
    return first.workspaceRoots.compactMap { try? $0.toAbsPath() }
}

public final class ThreadEnvironments: @unchecked Sendable {
    private struct State {
        var threadDefaults: ThreadEnvironmentDefaults
        var environments: [TurnEnvironmentState]
    }

    private let knownEnvironmentIds: Set<String>
    private let lock: OSAllocatedUnfairLock<State>

    public init(
        knownEnvironmentIds: Set<String> = [LOCAL_ENVIRONMENT_ID],
        threadDefaults: ThreadEnvironmentDefaults,
        current: TurnEnvironmentSnapshot = TurnEnvironmentSnapshot()
    ) {
        self.knownEnvironmentIds = knownEnvironmentIds
        self.lock = OSAllocatedUnfairLock(
            initialState: State(
                threadDefaults: threadDefaults,
                environments: current.environments.filter {
                    if case .ready = $0 { return true }
                    return false
                }
            )
        )
    }

    public func setActiveThreadDefaults(_ defaults: ThreadEnvironmentDefaults) {
        lock.withLock { $0.threadDefaults = defaults }
    }

    public func updateSelections(_ environments: [TurnEnvironmentSelection]) {
        lock.withLock { state in
            var seen = Set<String>()
            var next: [TurnEnvironmentState] = []
            for selected in environments {
                if !seen.insert(selected.environmentId).inserted {
                    continue
                }
                if let previous = state.environments.first(where: { environment in
                    let previousSelection = environmentSelection(environment)
                    return previousSelection.environmentId == selected.environmentId
                        && previousSelection.cwd == selected.cwd
                        && previousSelection.workspaceRoots == selected.workspaceRoots
                }) {
                    let failed: Bool
                    if case .failed = previous { failed = true } else { failed = false }
                    let restartingAsPending: Bool
                    if case .pending = selected.config,
                       case .pending = environmentSelection(previous).config
                    {
                        restartingAsPending = false
                    } else if case .pending = selected.config {
                        restartingAsPending = true
                    } else {
                        restartingAsPending = false
                    }
                    if !failed && !restartingAsPending {
                        let (resolved, origin) = resolveSelectionConfig(
                            selected,
                            defaults: state.threadDefaults
                        )
                        next.append(makeState(resolved, origin: origin))
                        continue
                    }
                }
                if !knownEnvironmentIds.contains(selected.environmentId) {
                    continue
                }
                let (resolved, origin) = resolveSelectionConfig(
                    selected,
                    defaults: state.threadDefaults
                )
                next.append(makeState(resolved, origin: origin))
            }
            state.environments = next
        }
    }

    public func selections() -> [TurnEnvironmentSelection] {
        lock.withLock { state in
            state.environments.map { environment in
                switch environment {
                case .ready(let binding):
                    return binding.configOrigin.intoInputSelection(binding.selection)
                case .starting(let starting):
                    return starting.configOrigin.intoInputSelection(starting.selection)
                case .failed(let selection, _):
                    return selection
                }
            }
        }
    }

    public func snapshot() -> TurnEnvironmentSnapshot {
        lock.withLock { TurnEnvironmentSnapshot(environments: $0.environments) }
    }
}

func environmentSelection(_ environment: TurnEnvironmentState) -> TurnEnvironmentSelection {
    switch environment {
    case .ready(let binding):
        return binding.selection
    case .starting(let starting):
        return starting.selection
    case .failed(let selection, _):
        return selection
    }
}

func makeState(
    _ selection: TurnEnvironmentSelection,
    origin: EnvironmentConfigOrigin
) -> TurnEnvironmentState {
    switch selection.config {
    case .pending:
        return .starting(StartingTurnEnvironment(selection: selection, configOrigin: origin))
    case .failed(let error):
        return .failed(selection: origin.intoInputSelection(selection), error: error)
    case .fromThread, .ready:
        return .ready(
            SelectedEnvironmentBinding(
                selection: selection,
                configOrigin: origin,
                isRemote: selection.environmentId != LOCAL_ENVIRONMENT_ID
            )
        )
    }
}

public func threadEnvironmentConfig(
    allowLoginShell: Bool = true,
    workspaceRoots: [PathUri] = [],
    permissionProfile: PermissionProfile = .readOnly()
) -> EnvironmentConfig {
    EnvironmentConfig(
        allowLoginShell: allowLoginShell,
        workspaceRoots: workspaceRoots,
        permissionProfile: .legacy(permissionProfile),
        shellEnvironmentPolicy: ShellEnvironmentPolicy(),
        windowsSandboxLevel: .disabled,
        windowsSandboxType: .none,
        useLegacyLandlock: false
    )
}

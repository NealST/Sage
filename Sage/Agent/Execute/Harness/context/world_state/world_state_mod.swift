//
//  world_state_mod.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Section trait objects and SHA-1 snapshot hashing are collapsed to a
//  dictionary of Codable snapshots. Diff rendering still emits fragments.
//  Reconstructed baselines also keep the rollout JSON so patches can merge.
//

import CodexProtocol
import Foundation

public struct WorldStateSnapshot: Equatable, Sendable {
    public var sections: [String: String]
    /// Rollout sections, kept as JSON so reconstruction can merge patches.
    public var jsonSections: [String: JSONValue]

    public init(
        sections: [String: String] = [:],
        jsonSections: [String: JSONValue] = [:]
    ) {
        self.sections = sections
        self.jsonSections = jsonSections
    }

    /// rust `WorldStateSnapshot::apply_merge_patch`. A null section is removed.
    public mutating func applyMergePatch(_ patch: [String: JSONValue]) {
        for (key, value) in patch {
            if value == .null {
                jsonSections.removeValue(forKey: key)
            } else if var current = jsonSections[key] {
                applyMergePatchValue(&current, value)
                jsonSections[key] = current
            } else {
                var current: JSONValue = .null
                applyMergePatchValue(&current, value)
                jsonSections[key] = current
            }
        }
    }
}

private func applyMergePatchValue(_ target: inout JSONValue, _ patch: JSONValue) {
    guard case .object(let patchObject) = patch else {
        target = patch
        return
    }
    var targetObject: [String: JSONValue]
    if case .object(let existing) = target {
        targetObject = existing
    } else {
        targetObject = [:]
    }
    for (key, value) in patchObject {
        if value == .null {
            targetObject.removeValue(forKey: key)
        } else if var current = targetObject[key] {
            applyMergePatchValue(&current, value)
            targetObject[key] = current
        } else {
            var current: JSONValue = .null
            applyMergePatchValue(&current, value)
            targetObject[key] = current
        }
    }
    target = .object(targetObject)
}

public final class WorldState: @unchecked Sendable {
    public var agentsMd: AgentsMdState
    public var appsInstructions: AppsInstructionsState
    public var collaborationMode: CollaborationModeState
    public var compactPermissions: CompactPermissionsState
    public var contextWindowGuidance: ContextWindowGuidanceState
    public var environment: EnvironmentsState
    public var environmentsInstructions: EnvironmentsInstructionsState
    public var managedDeveloperInstructions: ManagedDeveloperInstructionsState
    public var model: ModelInstructionsState
    public var multiAgentMode: MultiAgentModeState
    public var multiAgentUsageHint: MultiAgentUsageHintState
    public var permissions: PermissionsState
    public var persistentMode: PersistentModeState
    public var pluginsInstructions: PluginsInstructionsState
    public var realtime: RealtimeState
    public var tools: ToolsState

    public init() {
        agentsMd = AgentsMdState()
        appsInstructions = AppsInstructionsState()
        collaborationMode = CollaborationModeState()
        compactPermissions = CompactPermissionsState()
        contextWindowGuidance = ContextWindowGuidanceState()
        environment = EnvironmentsState()
        environmentsInstructions = EnvironmentsInstructionsState()
        managedDeveloperInstructions = ManagedDeveloperInstructionsState()
        model = ModelInstructionsState()
        multiAgentMode = MultiAgentModeState()
        multiAgentUsageHint = MultiAgentUsageHintState()
        permissions = PermissionsState()
        persistentMode = PersistentModeState()
        pluginsInstructions = PluginsInstructionsState()
        realtime = RealtimeState()
        tools = ToolsState()
    }

    public func snapshot() -> WorldStateSnapshot {
        var sections: [String: String] = [:]
        sections["agents_md"] = agentsMd.snapshot()
        sections["apps_instructions"] = appsInstructions.snapshot()
        sections["collaboration_mode"] = collaborationMode.snapshot()
        sections["compact_permissions"] = compactPermissions.snapshot()
        sections["context_window_guidance"] = contextWindowGuidance.snapshot()
        sections["environment"] = environment.snapshot()
        sections["environments_instructions"] = environmentsInstructions.snapshot()
        sections["managed_developer_instructions"] = managedDeveloperInstructions.snapshot()
        sections["model"] = model.snapshot()
        sections["multi_agent_mode"] = multiAgentMode.snapshot()
        sections["multi_agent_usage_hint"] = multiAgentUsageHint.snapshot()
        sections["permissions"] = permissions.snapshot()
        sections["persistent_mode"] = persistentMode.snapshot()
        sections["plugins_instructions"] = pluginsInstructions.snapshot()
        sections["realtime"] = realtime.snapshot()
        sections["tools"] = tools.snapshot()
        return WorldStateSnapshot(sections: sections.compactMapValues { $0 })
    }

    public func renderDiff(previous: WorldStateSnapshot?) -> [any ContextualUserFragment] {
        var fragments: [any ContextualUserFragment] = []
        func add(_ fragment: (any ContextualUserFragment)?) {
            if let fragment { fragments.append(fragment) }
        }
        add(agentsMd.renderDiff(previous: previous?.sections["agents_md"]))
        add(appsInstructions.renderDiff(previous: previous?.sections["apps_instructions"]))
        add(collaborationMode.renderDiff(previous: previous?.sections["collaboration_mode"]))
        add(compactPermissions.renderDiff(previous: previous?.sections["compact_permissions"]))
        add(contextWindowGuidance.renderDiff(previous: previous?.sections["context_window_guidance"]))
        add(environment.renderDiff(previous: previous?.sections["environment"]))
        add(environmentsInstructions.renderDiff(previous: previous?.sections["environments_instructions"]))
        add(managedDeveloperInstructions.renderDiff(previous: previous?.sections["managed_developer_instructions"]))
        add(model.renderDiff(previous: previous?.sections["model"]))
        add(multiAgentMode.renderDiff(previous: previous?.sections["multi_agent_mode"]))
        add(multiAgentUsageHint.renderDiff(previous: previous?.sections["multi_agent_usage_hint"]))
        add(permissions.renderDiff(previous: previous?.sections["permissions"]))
        add(persistentMode.renderDiff(previous: previous?.sections["persistent_mode"]))
        add(pluginsInstructions.renderDiff(previous: previous?.sections["plugins_instructions"]))
        add(realtime.renderDiff(previous: previous?.sections["realtime"]))
        add(tools.renderDiff(previous: previous?.sections["tools"]))
        return fragments
    }

    /// Codex `WorldState::render_full`: every section with no previous snapshot.
    public func renderFull() -> [any ContextualUserFragment] {
        renderDiff(previous: nil)
    }
}

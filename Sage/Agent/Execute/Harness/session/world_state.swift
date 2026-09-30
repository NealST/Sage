//
//  world_state.swift
//  Sage
//
//  Port of codex-rs/core/src/session/world_state.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Step snapshots fill model / environment / developer / collaboration
//  plus exec-policy approved prefixes. Plugin contributors stay out.
//

import CodexCore
import CodexExecPolicy
import CodexProtocol
import Foundation

extension Session {
    func currentWorldState() -> WorldState {
        WorldState()
    }

    func buildWorldStateForStep(_ stepContext: StepContext) -> WorldState {
        let turn = stepContext.turn
        let state = WorldState()
        state.model = ModelInstructionsState(model: turn.model)
        state.environment = EnvironmentsState(
            rendered: renderEnvironmentContext(
                cwd: turn.cwd,
                approvalPolicy: approvalPolicyLabel(turn.approvalPolicy)
            )
        )
        state.collaborationMode = CollaborationModeState(mode: turn.collaborationMode)
        state.realtime = RealtimeState(active: turn.realtimeActive)
        let developer = turn.config.developerInstructions
            ?? self.state.sessionConfiguration.developerInstructions
        if let developer, !developer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.managedDeveloperInstructions = ManagedDeveloperInstructionsState(
                text: validateManagedDeveloperInstructions(developer)
            )
        }
        state.permissions = PermissionsState(
            rendered: renderPermissionsContext(
                approvalPolicy: approvalPolicyLabel(turn.approvalPolicy),
                allowedPrefixes: services.execPolicy?.getAllowedPrefixes() ?? []
            )
        )
        return state
    }

    func buildInitialContextWithWorldState(
        _ stepContext: StepContext,
        worldState: WorldState
    ) -> [ResponseItemEnvelope] {
        var items = worldState.renderFull().map { ResponseItemEnvelope($0.asResponseItem()) }
        if stepContext.turn.config.features.enabled(.tokenBudget)
            || features.enabled(.tokenBudget),
           stepContext.turn.resolvedContextWindow() != nil
            || stepContext.turn.config.modelContextWindow != nil
            || stepContext.turn.modelContextWindow != nil
        {
            let ids = state.autoCompactWindow.ids
            items.append(
                ResponseItemEnvelope(
                    TokenBudgetContext(
                        agentPath: stepContext.turn.sessionSource.getAgentPath()?.description
                            ?? "root",
                        firstWindowId: ids.firstWindowId,
                        previousWindowId: ids.previousWindowId,
                        windowId: ids.windowId
                    ).asResponseItem()
                )
            )
        }
        return items
    }

    func buildCompactionInitialContext(
        stepContext: StepContext,
        injection: InitialContextInjection
    ) -> [ResponseItemEnvelope] {
        switch injection {
        case .doNotInject:
            return []
        case .beforeLastUserMessage:
            return buildInitialContextWithWorldState(
                stepContext,
                worldState: buildWorldStateForStep(stepContext)
            )
        }
    }
}

func applyCompactedHistoryInitialContext(
    _ history: [ResponseItemEnvelope],
    sess: Session,
    stepContext: StepContext,
    injection: InitialContextInjection
) -> [ResponseItemEnvelope] {
    let initialContext = sess.buildCompactionInitialContext(
        stepContext: stepContext,
        injection: injection
    )
    if initialContext.isEmpty { return history }
    return insertInitialContextBeforeLastRealUserOrSummary(
        history,
        initialContext: initialContext
    )
}

func renderPermissionsContext(approvalPolicy: String, allowedPrefixes: [[String]]) -> String {
    var rendered = "approval_policy: \(approvalPolicy)"
    if let prefixes = formatAllowPrefixes(allowedPrefixes) {
        rendered += "\n\(approvedCommandPrefixSavedMessagePrefix)\n\(prefixes)"
    }
    return rendered
}

func renderEnvironmentContext(cwd: String, approvalPolicy: String) -> String {
    """
    <environment_context>
      <cwd>\(xmlEscape(cwd))</cwd>
      <approval_policy>\(xmlEscape(approvalPolicy))</approval_policy>
    </environment_context>
    """
}

func approvalPolicyLabel(_ policy: CodexProtocol.AskForApproval) -> String {
    switch policy {
    case .unlessTrusted:
        return "untrusted"
    case .onRequest:
        return "on-request"
    case .granular:
        return "granular"
    case .never:
        return "never"
    }
}

func xmlEscape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

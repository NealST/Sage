//
//  turn_settings.swift
//  Sage
//
//  Port of codex-rs/core/src/session/step_activation.rs `apply_turn_settings`
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Publishes model, effort, summary, and service tier onto the named
//  live task's `nextStepSettings`. The turn's initial model, the session
//  configuration, and any step already captured stay unchanged. Reviewer
//  and environment updates, async model lookup, and the second
//  publication check after that lookup wait.
//

import CodexAsyncUtils
import CodexProtocol
import Foundation

extension Session {
    /// rust `Session::apply_turn_settings`. Does not start a turn.
    func applyTurnSettings(turnId: String, update: TurnSettingsUpdate) -> TurnSettingsUpdateOutcome {
        // Reviewer and environment overrides are absent, so rust requires the
        // feature for every update, including one that changes no model field.
        if !features.enabled(.stepModelSwitching) {
            return .rejected(
                reason: "turn settings updates require the step_model_switching feature"
            )
        }
        guard let task = activeTurn?.task,
              !task.done,
              task.turnContext.subId == turnId,
              task.cancellationToken?.isCancelled != true
        else {
            return .targetUnavailable
        }

        var settings = task.turnContext.nextStepSettings
        if let model = update.model {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed != model {
                return .rejected(
                    reason: "model must be a non-empty slug without surrounding whitespace"
                )
            }
            settings.model = model
            settings.modelSnapshot.slug = model
        }
        if let effort = update.reasoningEffort {
            settings.reasoningEffort = effort
        }
        if let summary = update.reasoningSummary {
            settings.reasoningSummary = summary
        }
        if let serviceTier = update.serviceTier {
            settings.serviceTier = serviceTier
        }
        if update.model != nil || update.reasoningEffort != nil,
           var collaboration = settings.collaborationMode
        {
            collaboration.settings.model = settings.model
            collaboration.settings.reasoningEffort = settings.reasoningEffort
            settings.collaborationMode = collaboration
        }
        task.turnContext.nextStepSettings = settings
        return .applied
    }
}

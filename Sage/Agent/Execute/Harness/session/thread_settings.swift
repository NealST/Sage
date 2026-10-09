//
//  thread_settings.swift
//  Sage
//
//  Port of codex-rs/core/src/session/thread_settings.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `Op::ThreadSettings` writes the Swift override fields onto session
//  `StepSettings` for later turns. The running turn keeps its own
//  `TurnContext`. A successful update clears `lastStartedTurnId` and
//  emits `ThreadSettingsApplied` without starting a turn. Persistence
//  checkpoints, config contributors, permission-profile refresh, and
//  MCP prewarm stay out. Snapshot approval, reviewer, and permission
//  profile are the session defaults until those override fields exist.
//

import CodexProtocol
import CodexUtils
import Foundation

struct ThreadSettingsOverrideError: Error {
    var message: String
}

extension Session {
    func applyThreadSettings(_ settings: StepSettings) {
        state.sessionConfiguration.stepSettings = settings
    }

    /// rust `thread_settings::update`. Does not start a turn.
    func updateThreadSettings(submissionId: String, overrides: ThreadSettingsOverrides) async {
        if state.shuttingDown { return }
        do {
            try applyThreadSettingsOverrides(overrides)
            lastStartedTurnId = nil
            sendEventRaw(
                Event(
                    id: submissionId,
                    msg: .threadSettingsApplied(
                        ThreadSettingsAppliedEvent(
                            threadId: threadId,
                            threadSettings: threadSettingsSnapshot()
                        )
                    )
                )
            )
        } catch let error as ThreadSettingsOverrideError {
            sendEventRaw(
                Event(
                    id: submissionId,
                    msg: .error(
                        ErrorEvent(
                            message: "invalid thread settings override: \(error.message)",
                            errorInfo: .badRequest
                        )
                    )
                )
            )
        } catch {
            sendEventRaw(
                Event(
                    id: submissionId,
                    msg: .error(
                        ErrorEvent(
                            message: "invalid thread settings override: \(error)",
                            errorInfo: .badRequest
                        )
                    )
                )
            )
        }
    }

    func applyThreadSettingsOverrides(_ overrides: ThreadSettingsOverrides) throws {
        var settings = state.sessionConfiguration.stepSettings
        if let model = overrides.model {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed != model {
                throw ThreadSettingsOverrideError(
                    message: "model must be a non-empty slug without surrounding whitespace"
                )
            }
            settings.model = model
            settings.modelSnapshot.slug = model
        }
        if let effort = overrides.reasoningEffort {
            settings.reasoningEffort = effort
        }
        if let summary = overrides.reasoningSummary {
            settings.reasoningSummary = summary
        }
        var collaboration = settings.collaborationMode ?? CollaborationMode(
            mode: overrides.mode ?? .default,
            settings: Settings(model: settings.model, reasoningEffort: settings.reasoningEffort)
        )
        if let mode = overrides.mode {
            collaboration.mode = mode
        }
        collaboration.settings.model = settings.model
        collaboration.settings.reasoningEffort = settings.reasoningEffort
        settings.collaborationMode = collaboration
        applyThreadSettings(settings)
    }

    func threadSettingsSnapshot() -> ThreadSettingsSnapshot {
        let configuration = state.sessionConfiguration
        let settings = configuration.stepSettings
        let collaboration = settings.collaborationMode ?? CollaborationMode(
            mode: .default,
            settings: Settings(model: settings.model, reasoningEffort: settings.reasoningEffort)
        )
        return ThreadSettingsSnapshot(
            model: collaboration.model,
            modelProviderId: configuration.originalConfig.modelProviderId,
            serviceTier: settings.serviceTier,
            approvalPolicy: configuration.originalConfig.approvalPolicy,
            approvalsReviewer: .user,
            permissionProfile: .readOnly(),
            cwd: absoluteThreadPath(configuration.legacyFallbackCwd),
            runtimeWorkspaceRoots: configuration.runtimeWorkspaceRoots.map(absoluteThreadPath),
            reasoningEffort: collaboration.reasoningEffort ?? settings.reasoningEffort,
            reasoningSummary: settings.reasoningSummary,
            collaborationMode: collaboration,
            disabledPluginIds: configuration.disabledPluginIds
        )
    }

    private func absoluteThreadPath(_ path: String) -> AbsolutePathBuf {
        if let absolute = try? AbsolutePathBuf.fromAbsolutePath(path) {
            return absolute
        }
        return AbsolutePathBuf.resolvePathAgainstBase(path, basePath: "/")
    }
}

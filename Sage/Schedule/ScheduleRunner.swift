//
//  ScheduleRunner.swift
//  Sage
//
//  Executes one script or agent recipe on an ephemeral session (no window focus).
//

import Foundation

/// Independent runner: PathGuard + ProcessRunner, or spawnScheduledTask + turn.
@MainActor
final class ScheduleRunner {
    private let taskRepository: any TaskRepository
    private let settings: ModelSettings
    private let mcpHub: CapabilityStore
    private let skillStateStore: SkillStateStore
    /// In-flight ephemeral sessions, keyed by schedule id, so Stop can interrupt.
    private var inFlightSessions: [UUID: AgentSession] = [:]

    init(
        taskRepository: any TaskRepository,
        settings: ModelSettings,
        mcpHub: CapabilityStore,
        skillStateStore: SkillStateStore
    ) {
        self.taskRepository = taskRepository
        self.settings = settings
        self.mcpHub = mcpHub
        self.skillStateStore = skillStateStore
    }

    /// Stops an in-flight agent beat for this schedule, if any.
    func stopAgent(forScheduleID id: UUID) {
        inFlightSessions[id]?.agent.stop()
    }

    func runScript(
        _ record: ScheduleRecord,
        processOwnerID: UUID
    ) async -> ScheduleScriptOutcome {
        let command = record.command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else {
            return ScheduleScriptOutcome(excerpt: "Failed: empty command.", exitCode: 1, failed: true)
        }
        do {
            try ShellCommandPolicy.validate(command)
        } catch {
            return ScheduleScriptOutcome(
                excerpt: "Failed: \(error.localizedDescription)",
                exitCode: 1,
                failed: true
            )
        }
        let policy: PathGuard.Policy
        if let projectID = record.projectID,
           let project = try? await taskRepository.loadProject(id: projectID) {
            policy = .project(root: project.rootURL)
        } else {
            policy = .home
        }
        do {
            return try await ProcessRunner.$ownerID.withValue(Optional(processOwnerID)) {
                try await PathGuard.$policy.withValue(policy) {
                    let cwd = try Self.resolveWorkingDirectory(record.workingDirectory, policy: policy)
                    let result = try await ProcessRunner.run(
                        executable: URL(fileURLWithPath: "/bin/zsh"),
                        arguments: ["-c", command],
                        currentDirectory: cwd,
                        timeout: .seconds(30)
                    )
                    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let excerpt = output.isEmpty ? "(no output)" : String(output.prefix(240))
                    if result.timedOut {
                        return ScheduleScriptOutcome(
                            excerpt: "Failed: timed out. \(excerpt)",
                            exitCode: result.exitCode,
                            failed: true
                        )
                    }
                    if result.exitCode != 0 {
                        return ScheduleScriptOutcome(
                            excerpt: "Failed (exit \(result.exitCode)): \(excerpt)",
                            exitCode: result.exitCode,
                            failed: true
                        )
                    }
                    return ScheduleScriptOutcome(excerpt: excerpt, exitCode: 0, failed: false)
                }
            }
        } catch is CancellationError {
            return ScheduleScriptOutcome(excerpt: "Stopped", exitCode: 1, failed: true)
        } catch {
            return ScheduleScriptOutcome(
                excerpt: "Failed: \(error.localizedDescription)",
                exitCode: 1,
                failed: true
            )
        }
    }

    func runAgent(_ record: ScheduleRecord) async -> ScheduleAgentOutcome {
        guard settings.isConfigured else {
            return .finished(ok: false, summary: "API key isn’t configured.", plan: nil, taskID: nil)
        }
        let prompt = record.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            return .finished(ok: false, summary: "Failed: empty prompt.", plan: nil, taskID: nil)
        }

        let project: ProjectRecord?
        if let projectID = record.projectID {
            project = try? await taskRepository.loadProject(id: projectID)
        } else {
            project = nil
        }

        if record.status == .armed, record.projectID != nil {
            let rootExists = project.map {
                FileManager.default.fileExists(atPath: $0.rootURL.path)
            } ?? false
            if !rootExists {
                return .degraded(reason: "Project folder is gone.")
            }
        }

        let kind: AgentSession.Kind = project.map { .project($0.id) } ?? .general
        let session = AgentSession(
            kind: kind,
            settings: settings,
            taskRepository: taskRepository,
            mcpHub: mcpHub,
            skillStateStore: skillStateStore
        )
        session.agent.state.focusedProject = project
        session.agent.state.didBootstrap = true
        inFlightSessions[record.id] = session
        defer { inFlightSessions[record.id] = nil }

        return await withTaskCancellationHandler {
            await self.performAgentRun(
                record: record,
                prompt: prompt,
                session: session,
                project: project
            )
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.inFlightSessions[record.id]?.agent.stop()
            }
        }
    }

    /// Resolves a relative working directory inside the schedule’s PathGuard sandbox.
    nonisolated static func resolveWorkingDirectory(
        _ raw: String?,
        policy: PathGuard.Policy
    ) throws -> URL {
        let relative = ScheduleRecord.normalizedWorkingDirectory(raw)
        let candidate: URL
        if let relative {
            if relative.hasPrefix("/") || relative.hasPrefix("~") {
                candidate = URL(
                    fileURLWithPath: (relative as NSString).expandingTildeInPath
                )
            } else {
                candidate = policy.defaultWorkingDirectory.appendingPathComponent(relative)
            }
        } else {
            candidate = policy.defaultWorkingDirectory
        }
        let resolved = try PathGuard.resolveAllowed(candidate.path, policy: policy, access: .write)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ToolError.invalidArguments(
                "Working directory does not exist: \(PathGuard.displayPath(resolved.path, policy: policy))"
            )
        }
        return resolved
    }

    // MARK: - Agent

    private func performAgentRun(
        record: ScheduleRecord,
        prompt: String,
        session: AgentSession,
        project: ProjectRecord?
    ) async -> ScheduleAgentOutcome {
        let isReplay = record.status == .armed
        if isReplay && record.frozenSkillNames.isEmpty {
            // Replay with no frozen skills: skip the catalog scan. Project root
            // was already checked before the session was created.
        } else {
            await session.skillCatalog.reloadSkills(projectRoot: project?.rootURL)
            if isReplay {
                let enabledNames = Set(session.skillCatalog.enabledSkills.map(\.name))
                if let reason = record.replayDegradeReason(
                    enabledSkillNames: enabledNames,
                    projectRootExists: nil
                ) {
                    return .degraded(reason: reason)
                }
            }
        }
        if Task.isCancelled {
            return .finished(ok: false, summary: "Stopped", plan: nil, taskID: nil)
        }

        let spawned = await session.agent.spawnScheduledTask(
            projectID: project?.id,
            summary: String(prompt.prefix(160)),
            originScheduleID: record.id
        )
        guard let taskID = spawned else {
            return .finished(
                ok: false,
                summary: "Could not create a task for this schedule.",
                plan: nil,
                taskID: nil
            )
        }
        if Task.isCancelled {
            return .finished(ok: false, summary: "Stopped", plan: nil, taskID: taskID)
        }

        let frozen = isReplay ? record.frozenWorkPlan : nil
        await session.agent.performScheduledRun(prompt: prompt, frozenPlan: frozen)
        if Task.isCancelled {
            return .finished(ok: false, summary: "Stopped", plan: nil, taskID: taskID)
        }
        if case .awaitingConfirmation = session.agent.state.phase {
            return .needsConfirmation(taskID: taskID, plan: session.agent.state.activeTask?.workPlan)
        }
        let task = session.agent.state.activeTask
        let summary = task?.events.last(where: { $0.kind == .assistantResponse })?.content
            ?? session.agent.state.lastAssistantText
            ?? "Finished"
        let ok: Bool
        if case .failed = session.agent.state.phase {
            ok = false
        } else {
            ok = true
        }
        return .finished(ok: ok, summary: String(summary.prefix(240)), plan: task?.workPlan ?? frozen, taskID: taskID)
    }
}

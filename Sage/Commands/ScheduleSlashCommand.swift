import Foundation

/// `/schedule <when> <what>` — confirm an agent recipe, independent of the current thread.
struct ScheduleSlashCommand: BuiltinSlashCommand {
    let definition = SlashCommandDefinition(
        name: "schedule",
        description: "Run Sage on a timetable",
        kind: .builtin
    )

    func handle(argument: String, host: any SlashCommandHost) -> Bool {
        guard let parsed = ScheduleCadenceParser.parseCadenceAndPrompt(argument) else {
            host.reportCommandFailure(
                "Use /schedule weekdays 9:00 followed by what Sage should do."
            )
            return true
        }
        var prompt = parsed.prompt
        var originTaskID: UUID?
        if prompt.lowercased() == "this" {
            guard let wording = host.latestUserRequestText else {
                host.reportCommandFailure(
                    "No earlier request in this chat to schedule. Write the task after the time."
                )
                return true
            }
            prompt = wording
            originTaskID = host.scheduleOriginTaskID
        }
        host.presentScheduleDraft(
            ScheduleDraft(
                cadence: parsed.cadence,
                prompt: prompt,
                projectID: host.scheduleScopeProjectID,
                scopeLabel: host.scheduleScopeLabel,
                originTaskID: originTaskID
            )
        )
        return true
    }
}

/// `/schedule-script` — open the script schedule panel in this window’s scope.
struct ScheduleScriptSlashCommand: BuiltinSlashCommand {
    let definition = SlashCommandDefinition(
        name: "schedule-script",
        description: "Run a command on a timetable",
        kind: .builtin
    )

    func handle(argument: String, host: any SlashCommandHost) -> Bool {
        host.presentScriptSchedule(prefill: argument.isEmpty ? nil : argument)
        return true
    }
}

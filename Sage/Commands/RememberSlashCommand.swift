import Foundation

/// `/remember` — identify new vs enhance (cannot skip), then show a save tip.
struct RememberSlashCommand: BuiltinSlashCommand {
    let definition = SlashCommandDefinition(
        name: "remember",
        description: "Save experience from this conversation",
        kind: .builtin
    )

    func handle(argument: String, host: any SlashCommandHost) async -> Bool {
        guard host.isModelConfigured else {
            host.reportCommandFailure(ModelClientError.notConfigured.localizedDescription)
            return false
        }
        guard await host.ensureActiveTaskForCommand() else { return false }

        guard host.usableTranscriptEventCount >= 2 else {
            host.reportCommandFailure("Nothing to remember yet — have a short conversation first.")
            return false
        }

        let note = argument.isEmpty ? nil : argument
        let display = note.map { "/\(definition.name) \($0)" } ?? "/\(definition.name)"

        guard await host.appendProtectedUserInput(display) else { return false }

        host.reportCommandThinking()
        host.scheduleExplicitRemember(userNote: note)
        return true
    }
}

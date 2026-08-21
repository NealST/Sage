import Foundation

/// `/skill-name` — activate an enabled skill by name (dynamic, not in builtins).
enum ActivateSkillSlashCommand {
    @MainActor
    static func handle(name: String, host: any SlashCommandHost) async -> Bool {
        guard let skill = host.enabledSkill(named: name) else {
            host.reportCommandFailure("Skill '\(name)' not found or not enabled.")
            return false
        }

        if host.isSkillActivated(name) {
            host.reportCommandFailure("Skill '\(name)' is already active in this session.")
            return false
        }

        let didActivate = await host.activateSkill(skill)
        if didActivate {
            host.reportCommandCompleted(
                summary: "Skill '\(name)' activated. Its instructions are now active for this session."
            )
        }
        return didActivate
    }
}

import Foundation

/// Metadata for a slash command shown in autocomplete and help.
struct SlashCommandDefinition: Identifiable, Hashable, Sendable {
    var id: String { name }

    /// Command token without the leading `/` (e.g. `"remember"`).
    let name: String
    /// Short description for autocomplete.
    let description: String
    /// Built-in app command vs dynamic skill activation.
    let kind: Kind

    enum Kind: Hashable, Sendable {
        case builtin
        case skill
    }
}

/// Parsed `/name` + optional argument (text after the command token).
struct SlashCommandInvocation: Equatable, Sendable {
    let name: String
    let argument: String
    let raw: String
}

/// Narrow surface that slash handlers use — implemented by `AgentRuntime` without exposing internals.
@MainActor
protocol SlashCommandHost: AnyObject {
    var isModelConfigured: Bool { get }

    func reportCommandFailure(_ message: String)
    func reportCommandThinking()
    func reportCommandCompleted(summary: String)

    @discardableResult
    func ensureActiveTaskForCommand() async -> Bool

    /// Count of user / assistant / toolResult events on the active task.
    var usableTranscriptEventCount: Int { get }

    @discardableResult
    func appendProtectedUserInput(_ content: String) async -> Bool

    /// Call only after a successful append so extraction sees the fresh task.
    func scheduleExplicitRemember(userNote: String?)

    func enabledSkill(named name: String) -> SkillRecord?
    func isSkillActivated(_ name: String) -> Bool

    /// Loads skill content, appends a protected event, then marks activated (rolls back on failure).
    func activateSkill(_ skill: SkillRecord) async -> Bool

    func presentScheduleDraft(_ draft: ScheduleDraft)
    func presentScriptSchedule(prefill command: String?)
    var scheduleScopeProjectID: UUID? { get }
    var scheduleScopeLabel: String { get }
    /// Most recent user request in this chat, excluding slash commands and protected lines.
    var latestUserRequestText: String? { get }
    /// Active task to store as `origin_task_id` when the user explicitly schedules this conversation.
    var scheduleOriginTaskID: UUID? { get }
}

/// Built-in slash command registered in `SlashCommandRegistry.builtins`.
@MainActor
protocol BuiltinSlashCommand {
    var definition: SlashCommandDefinition { get }
    func handle(argument: String, host: any SlashCommandHost) async -> Bool
}

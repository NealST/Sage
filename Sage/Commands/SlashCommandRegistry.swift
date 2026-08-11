import Foundation

/// Central catalog: builtin registration, autocomplete definitions, and dispatch.
@MainActor
enum SlashCommandRegistry {

    /// Single source of truth for built-in commands. Add new builtins here only.
    static let builtins: [any BuiltinSlashCommand] = [
        RememberSlashCommand(),
    ]

    /// Autocomplete / help entries: builtins first, then skills.
    static func definitions(
        skills: [(name: String, description: String)]
    ) -> [SlashCommandDefinition] {
        let builtinDefs = builtins.map(\.definition)
        let reserved = Set(builtinDefs.map { $0.name.lowercased() })
        let skillDefs = skills
            .filter { !reserved.contains($0.name.lowercased()) }
            .map {
                SlashCommandDefinition(name: $0.name, description: $0.description, kind: .skill)
            }
        return builtinDefs + skillDefs
    }

    /// Handles a slash command. Returns `nil` if input is not a known command.
    static func handle(
        _ input: String,
        host: any SlashCommandHost,
        enabledSkillNames: [String]
    ) async -> Bool? {
        guard let invocation = parse(input) else { return nil }
        let lowered = invocation.name.lowercased()

        if let builtin = builtins.first(where: {
            $0.definition.name.lowercased() == lowered
        }) {
            return await builtin.handle(argument: invocation.argument, host: host)
        }

        // Case-insensitive skill match → canonical name from the catalog.
        guard let canonical = enabledSkillNames.first(where: {
            $0.lowercased() == lowered
        }) else {
            return nil
        }
        return await ActivateSkillSlashCommand.handle(name: canonical, host: host)
    }

    /// Parses `/name` or `/name args`. Returns `nil` when not a slash invocation.
    static func parse(_ input: String) -> SlashCommandInvocation? {
        guard input.hasPrefix("/") else { return nil }
        let afterSlash = input.dropFirst()
        let name = String(afterSlash.prefix(while: { !$0.isWhitespace }))
        guard !name.isEmpty else { return nil }

        let nameEnd = input.index(input.startIndex, offsetBy: 1 + name.count)
        let argument = String(input[nameEnd...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SlashCommandInvocation(name: name, argument: argument, raw: input)
    }
}

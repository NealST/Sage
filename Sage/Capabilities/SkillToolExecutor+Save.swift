//
//  SkillToolExecutor+Save.swift
//  Sage
//

import Foundation

extension SkillToolExecutor {
    static func executeSaveSkill(argumentsJSON: String, host: SkillToolHost) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: SaveSkillToolArgs.self)
        try validateSaveSkillContent(description: args.description, body: args.body)
        switch args.action {
        case .create:
            return try await createSkillFromTool(args, host: host)

        case .enhance:
            return try await enhanceSkillFromTool(args, host: host)
        }
    }

    struct SaveSkillToolArgs: Decodable {
        let action: SaveSkillAction
        let name: String
        let description: String
        let body: String
        let scope: SkillScope?
    }

    static func validateSaveSkillContent(description: String, body: String) throws {
        guard description.count <= 1_024 else {
            throw ToolError.invalidArguments(
                "Description exceeds 1024 characters (\(description.count)). Shorten it."
            )
        }
        let bodyLines = body.components(separatedBy: "\n").count
        if bodyLines > 600 {
            throw ToolError.invalidArguments(
                "Body has \(bodyLines) lines — exceeds the recommended 500-line limit. "
                + "Move detailed reference material to separate files in references/."
            )
        }
    }

    static func createSkillFromTool(
        _ args: SaveSkillToolArgs,
        host: SkillToolHost
    ) async throws -> String {
        let scope = try resolveSaveSkillScope(args.scope, host: host)
        if host.catalogSkills.contains(where: { $0.name == args.name }) {
            throw ToolError.operationFailed(
                "Skill '\(args.name)' already exists in this workspace. Use action 'enhance' instead."
            )
        }
        let path = try await SkillWriter.createSkill(
            name: args.name,
            description: args.description,
            body: args.body,
            scope: scope,
            projectRoot: host.focusedProjectRoot
        )
        await host.broadcastSkillsCatalogChange()
        return "[OK] Created \(scope.catalogLabel) skill '\(args.name)' at \(path)"
    }

    static func enhanceSkillFromTool(
        _ args: SaveSkillToolArgs,
        host: SkillToolHost
    ) async throws -> String {
        guard let existing = host.catalogSkills.first(where: { $0.name == args.name }) else {
            let available = host.enabledSkills.map(\.name).joined(separator: ", ")
            throw ToolError.operationFailed(
                "Skill '\(args.name)' not found. Available skills: \(available.isEmpty ? "none" : available)"
            )
        }
        let path = try await SkillWriter.enhanceSkill(
            existingRecord: existing,
            description: args.description,
            body: args.body
        )
        await host.broadcastSkillsCatalogChange()
        return "[OK] Enhanced \(existing.scope.catalogLabel) skill '\(args.name)' at \(path)"
    }

    /// Resolves create scope the same way as the banner: project when focused (unless
    /// explicitly global), otherwise global only.
    static func resolveSaveSkillScope(_ scope: SkillScope?, host: SkillToolHost) throws -> SkillScope {
        switch scope {
        case nil:
            return host.focusedProjectRoot != nil ? .project : .global

        case .project:
            guard host.focusedProjectRoot != nil else {
                throw ToolError.invalidArguments(
                    "scope 'project' requires a focused project. Use 'global', or open a project first."
                )
            }
            return .project

        case .global:
            return .global
        }
    }
}

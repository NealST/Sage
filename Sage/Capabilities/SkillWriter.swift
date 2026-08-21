//
//  SkillWriter.swift
//  Sage
//
//  Writes or updates SKILL.md files for auto-generated skills.
//  All FileManager / write(to:) / trash work runs in Task.detached(.utility).
//

import Foundation

nonisolated enum SkillWriter {
    enum WriteError: LocalizedError, Sendable {
        case invalidName(String)
        case alreadyExists(String)
        case directoryCreationFailed(String)
        case writeFailed(String)
        case skillNotFound(String)
        case projectRootRequired
        case trashFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidName(let name):
                return "Invalid skill name: \(name). Must be 1-64 chars, lowercase alphanumeric and hyphens."

            case .alreadyExists(let name):
                return "Skill '\(name)' already exists. Use enhance to update it, or choose a different name."

            case .directoryCreationFailed(let path):
                return "Could not create skill directory at: \(path)"

            case .writeFailed(let path):
                return "Could not write SKILL.md at: \(path)"

            case .skillNotFound(let name):
                return "Skill '\(name)' not found in registry."

            case .projectRootRequired:
                return "A project folder is required to save a project skill."

            case .trashFailed(let path):
                return "Could not move skill to Trash: \(path)"
            }
        }
    }

    /// Creates a new skill in the global user directory or the focused project's `.sage/skills`.
    @discardableResult
    static func createSkill(
        name: String,
        description: String,
        body: String,
        scope: SkillScope = .global,
        projectRoot: URL? = nil
    ) async throws -> String {
        guard SkillMarkdown.isValidSkillName(name) else {
            throw WriteError.invalidName(name)
        }

        let path = try await Task.detached(priority: .utility) {
            let skillsRoot: URL
            do {
                skillsRoot = try SkillPaths.writableDirectory(for: scope, projectRoot: projectRoot)
            } catch SkillPathsError.projectRootRequired {
                throw WriteError.projectRootRequired
            } catch SkillPathsError.directoryCreationFailed(let path) {
                throw WriteError.directoryCreationFailed(path)
            }

            let skillDir = skillsRoot.appendingPathComponent(name, isDirectory: true)
            let skillFile = skillDir.appendingPathComponent("SKILL.md")

            if FileManager.default.fileExists(atPath: skillFile.path) {
                throw WriteError.alreadyExists(name)
            }

            do {
                try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            } catch {
                throw WriteError.directoryCreationFailed(skillDir.path)
            }

            let content = SkillMarkdown.ensureFrontmatter(
                body: body,
                name: name,
                description: description,
                source: "auto-generated"
            )

            do {
                try content.write(to: skillFile, atomically: true, encoding: .utf8)
            } catch {
                throw WriteError.writeFailed(skillFile.path)
            }
            return skillFile.path
        }.value

        await SkillRegistry.shared.invalidateCaches(forPath: path)
        return path
    }

    /// Enhances an existing skill by replacing its SKILL.md content.
    @discardableResult
    static func enhanceSkill(
        existingRecord: SkillRecord,
        description: String,
        body: String
    ) async throws -> String {
        let path = existingRecord.path
        let name = existingRecord.name
        let fallbackSource = existingRecord.provenance

        let writtenPath = try await Task.detached(priority: .utility) {
            let skillFile = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: skillFile.path) else {
                throw WriteError.skillNotFound(name)
            }

            let preservedSource = Self.readFrontmatterSource(at: skillFile) ?? fallbackSource
            let content = SkillMarkdown.ensureFrontmatter(
                body: body,
                name: name,
                description: description,
                source: preservedSource
            )

            do {
                try content.write(to: skillFile, atomically: true, encoding: .utf8)
            } catch {
                throw WriteError.writeFailed(skillFile.path)
            }
            return skillFile.path
        }.value

        await SkillRegistry.shared.invalidateCaches(forPath: writtenPath)
        return writtenPath
    }

    /// Moves a skill directory to Trash (off the caller’s actor).
    static func trashSkill(atSkillMarkdownPath path: String) async throws {
        try await Task.detached(priority: .utility) {
            let skillFile = URL(fileURLWithPath: path)
            let skillDir = skillFile.deletingLastPathComponent()
            do {
                try FileManager.default.trashItem(at: skillDir, resultingItemURL: nil)
            } catch {
                throw WriteError.trashFailed(skillDir.path)
            }
        }.value
        await SkillRegistry.shared.invalidateCaches(forPath: path)
    }

    /// Reads the frontmatter `source` value from an on-disk SKILL.md, if present.
    private static func readFrontmatterSource(at skillFile: URL) -> String? {
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let rawSource = SkillMarkdown.parseFrontmatter(text).scalars["source"]
        let value = rawSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

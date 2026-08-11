//
//  SkillWriter.swift
//  Sage
//
//  Writes or updates SKILL.md files for auto-generated skills.
//  Handles both new skill creation and enhancement of existing skills.
//

import Foundation

enum SkillWriter {
    enum WriteError: LocalizedError {
        case invalidName(String)
        case directoryCreationFailed(String)
        case writeFailed(String)
        case skillNotFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidName(let name):
                return "Invalid skill name: \(name). Must be 1-64 chars, lowercase alphanumeric and hyphens."
            case .directoryCreationFailed(let path):
                return "Could not create skill directory at: \(path)"
            case .writeFailed(let path):
                return "Could not write SKILL.md at: \(path)"
            case .skillNotFound(let name):
                return "Skill '\(name)' not found in registry."
            }
        }
    }

    /// Creates a new skill in the user's skill directory.
    ///
    /// - Parameters:
    ///   - name: Kebab-case skill name (becomes the directory name).
    ///   - description: One-sentence description for the frontmatter.
    ///   - body: Full SKILL.md content. If it doesn't include frontmatter, one will be prepended.
    /// - Returns: The file path of the created SKILL.md.
    @discardableResult
    static func createSkill(name: String, description: String, body: String) throws -> String {
        guard isValidSkillName(name) else {
            throw WriteError.invalidName(name)
        }

        let skillsRoot = userSkillsDirectory()
        let skillDir = skillsRoot.appendingPathComponent(name, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        } catch {
            throw WriteError.directoryCreationFailed(skillDir.path)
        }

        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        let content = ensureFrontmatter(body: body, name: name, description: description)

        do {
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.writeFailed(skillFile.path)
        }

        SkillRegistry.invalidateCaches()
        return skillFile.path
    }

    /// Enhances an existing skill by replacing its SKILL.md content.
    ///
    /// - Parameters:
    ///   - existingRecord: The SkillRecord to update.
    ///   - description: Updated description for the frontmatter.
    ///   - body: Complete new SKILL.md content (replaces the old file entirely).
    /// - Returns: The file path of the updated SKILL.md.
    @discardableResult
    static func enhanceSkill(
        existingRecord: SkillRecord,
        description: String,
        body: String
    ) throws -> String {
        let skillFile = URL(fileURLWithPath: existingRecord.path)
        guard FileManager.default.fileExists(atPath: skillFile.path) else {
            throw WriteError.skillNotFound(existingRecord.name)
        }

        let content = ensureFrontmatter(body: body, name: existingRecord.name, description: description)

        do {
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.writeFailed(skillFile.path)
        }

        SkillRegistry.invalidateCaches()
        return skillFile.path
    }

    // MARK: - Helpers

    /// Returns the user-level skills directory, creating it if needed.
    private static func userSkillsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let skillsDir = appSupport.appendingPathComponent("Sage/Skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        return skillsDir
    }

    /// Ensures the body has proper frontmatter with source: auto-generated.
    private static func ensureFrontmatter(body: String, name: String, description: String) -> String {
        // If body already starts with frontmatter, inject/update source field
        if body.hasPrefix("---") {
            return injectSourceField(body)
        }

        // Prepend frontmatter
        let frontmatter = """
        ---
        description: \(description)
        source: auto-generated
        ---

        """
        return frontmatter + body
    }

    /// Injects `source: auto-generated` into existing frontmatter if not present.
    private static func injectSourceField(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        guard let firstNewline = text.firstIndex(of: "\n") else { return text }

        let afterOpener = text.index(after: firstNewline)
        var cursor = afterOpener
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd].trimmingCharacters(in: .whitespaces)
            if line == "---" {
                // Found closing delimiter — check if source already exists
                let frontmatterBlock = String(text[afterOpener..<cursor])
                if frontmatterBlock.contains("source:") {
                    return text
                }
                // Insert source field before closing ---
                let before = String(text[..<cursor])
                let after = String(text[cursor...])
                return before + "source: auto-generated\n" + after
            }
            if lineEnd == text.endIndex { break }
            cursor = text.index(after: lineEnd)
        }
        return text
    }

    /// Validates a skill name (same rules as SkillRegistry).
    private static func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        guard !name.hasPrefix("-"), !name.hasSuffix("-") else { return false }
        guard !name.contains("--") else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
}

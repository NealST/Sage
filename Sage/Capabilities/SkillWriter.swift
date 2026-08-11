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
        case alreadyExists(String)
        case directoryCreationFailed(String)
        case writeFailed(String)
        case skillNotFound(String)
        case projectRootRequired

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
            }
        }
    }

    /// Creates a new skill in the global user directory or the focused project's `.sage/skills`.
    ///
    /// - Parameters:
    ///   - name: Kebab-case skill name (becomes the directory name).
    ///   - description: One-sentence description for the frontmatter.
    ///   - body: Full SKILL.md content. If it doesn't include frontmatter, one will be prepended.
    ///   - scope: Global (App Support) or project (`.sage/skills` under `projectRoot`).
    ///   - projectRoot: Required when `scope == .project`.
    /// - Returns: The file path of the created SKILL.md.
    @discardableResult
    static func createSkill(
        name: String,
        description: String,
        body: String,
        scope: SkillScope = .global,
        projectRoot: URL? = nil
    ) throws -> String {
        guard isValidSkillName(name) else {
            throw WriteError.invalidName(name)
        }

        let skillsRoot = try skillsDirectory(for: scope, projectRoot: projectRoot)
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

        let content = ensureFrontmatter(
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

        SkillRegistry.invalidateCaches()
        return skillFile.path
    }

    /// Enhances an existing skill by replacing its SKILL.md content.
    ///
    /// Preserves the existing frontmatter `source` value (hand-authored skills are
    /// not rewritten as `auto-generated`).
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

        // Prefer the live file's source so we don't stamp auto-generated onto hand-authored skills.
        let preservedSource = readFrontmatterSource(at: skillFile) ?? existingRecord.provenance
        let content = ensureFrontmatter(
            body: body,
            name: existingRecord.name,
            description: description,
            source: preservedSource
        )

        do {
            try content.write(to: skillFile, atomically: true, encoding: .utf8)
        } catch {
            throw WriteError.writeFailed(skillFile.path)
        }

        SkillRegistry.invalidateCaches()
        return skillFile.path
    }

    // MARK: - Helpers

    /// Returns the skills root directory for the given scope, creating it if needed.
    private static func skillsDirectory(for scope: SkillScope, projectRoot: URL?) throws -> URL {
        switch scope {
        case .global:
            return userSkillsDirectory()
        case .project:
            guard let projectRoot else {
                throw WriteError.projectRootRequired
            }
            let skillsDir = projectRoot.appendingPathComponent(".sage/skills", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            } catch {
                throw WriteError.directoryCreationFailed(skillsDir.path)
            }
            return skillsDir
        }
    }

    /// Returns the user-level skills directory, creating it if needed.
    private static func userSkillsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let skillsDir = appSupport.appendingPathComponent("Sage/Skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        return skillsDir
    }

    /// Ensures the body has frontmatter with authoritative `name` and `description`.
    /// When `source` is non-nil it is upserted; when nil, any existing `source` is dropped
    /// and none is added (hand-authored skills without a source stay unmarked).
    private static func ensureFrontmatter(
        body: String,
        name: String,
        description: String,
        source: String?
    ) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = frontmatterRange(trimmed) {
            return upsertFrontmatterFields(
                trimmed,
                range: range,
                name: name,
                description: description,
                source: source
            )
        }

        var lines = [
            "---",
            "name: \(name)",
            "description: \(yamlScalar(description))",
        ]
        if let source, !source.isEmpty {
            lines.append("source: \(yamlScalar(source))")
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n") + trimmed + "\n"
    }

    /// Upserts name / description into an existing frontmatter block; optionally sets source.
    private static func upsertFrontmatterFields(
        _ text: String,
        range: Range<String.Index>,
        name: String,
        description: String,
        source: String?
    ) -> String {
        let block = String(text[range])
        let markdownBody = String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Drop opening/closing --- lines for rewrite; re-add below.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeLast()
        }

        let managedKeys: Set<String> = ["name", "description", "source"]
        var kept: [String] = []
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { continue }
            if let colon = trimmedLine.firstIndex(of: ":") {
                let key = String(trimmedLine[..<colon]).trimmingCharacters(in: .whitespaces)
                if managedKeys.contains(key) { continue }
            }
            kept.append(line)
        }

        var rebuilt = ["---", "name: \(name)", "description: \(yamlScalar(description))"]
        if let source, !source.isEmpty {
            rebuilt.append("source: \(yamlScalar(source))")
        }
        rebuilt.append(contentsOf: kept)
        rebuilt.append("---")
        rebuilt.append("")
        if !markdownBody.isEmpty {
            rebuilt.append(markdownBody)
            rebuilt.append("")
        }
        return rebuilt.joined(separator: "\n")
    }

    /// Reads the frontmatter `source` value from an on-disk SKILL.md, if present.
    private static func readFrontmatterSource(at skillFile: URL) -> String? {
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8),
              let range = frontmatterRange(text) else { return nil }
        let block = String(text[range])
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            guard key == "source" else { continue }
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Locates the YAML frontmatter range (including both `---` delimiters).
    private static func frontmatterRange(_ text: String) -> Range<String.Index>? {
        guard text.hasPrefix("---") else { return nil }
        guard let firstNewline = text.firstIndex(of: "\n") else { return nil }
        let afterOpener = text.index(after: firstNewline)
        var cursor = afterOpener
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd].trimmingCharacters(in: .whitespaces)
            if line == "---" {
                let blockEnd = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                return text.startIndex..<blockEnd
            }
            if lineEnd == text.endIndex { break }
            cursor = text.index(after: lineEnd)
        }
        return nil
    }

    /// Escapes a scalar for YAML frontmatter. Flattens newlines (descriptions are
    /// one sentence) and quotes when needed so `:` / `#` cannot break parsing.
    private static func yamlScalar(_ value: String) -> String {
        let flattened = value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let needsQuoting =
            flattened.isEmpty
            || flattened.contains(where: { ":#{}[]&*!|>'\"%@`,".contains($0) })
            || flattened.hasPrefix("-")
            || flattened.hasPrefix(" ")
            || flattened.hasSuffix(" ")
            || flattened.contains("---")

        guard needsQuoting else { return flattened }

        let escaped = flattened
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Validates a skill name (same rules as SkillRegistry).
    private static func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        guard !name.hasPrefix("-"), !name.hasSuffix("-") else { return false }
        guard !name.contains("--") else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
}

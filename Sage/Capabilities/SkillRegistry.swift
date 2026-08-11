//
//  SkillRegistry.swift
//  Sage
//

import Foundation

enum SkillRegistry {
    // MARK: - Caches

    /// In-memory cache for skill bodies (keyed by SKILL.md path).
    /// Cleared on `invalidateCaches()` (called when skills are reloaded).
    private static var bodyCache: [String: String] = [:]

    /// In-memory cache for resource listings (keyed by SKILL.md path).
    private static var resourcesCache: [String: [String]] = [:]

    /// Clears all in-memory caches. Call when skills are reloaded from disk.
    static func invalidateCaches() {
        bodyCache.removeAll()
        resourcesCache.removeAll()
    }

    /// Scans global (user-level) skill locations only.
    /// App Support `Sage/Skills` and `~/.agents/skills` — never project-tree paths.
    static func scanUserSkills() -> [SkillRecord] {
        var roots: [URL] = []

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        roots.append(appSupport.appendingPathComponent("Sage/Skills", isDirectory: true))

        // User-level cross-client location (global, not tied to a project tree).
        let userAgentsSkills = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills", isDirectory: true)
        if FileManager.default.fileExists(atPath: userAgentsSkills.path) {
            roots.append(userAgentsSkills)
        }

        return scanRoots(roots, defaultSourceLabel: SkillScope.global.sourceLabel)
    }

    /// Scans project-level skill locations under the given project root.
    /// Any skill under the project tree (`.agents/skills` or `.sage/skills`) is project-scoped.
    static func scanProjectSkills(root: URL) -> [SkillRecord] {
        let roots: [URL] = [
            root.appendingPathComponent(".agents/skills", isDirectory: true),
            root.appendingPathComponent(".sage/skills", isDirectory: true),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        return scanRoots(roots, defaultSourceLabel: SkillScope.project.sourceLabel)
    }

    /// Combined scan: project skills (higher priority) + user skills.
    /// Project-level skills override user-level on name collision.
    static func scanAll(projectRoot: URL?) -> [SkillRecord] {
        let userSkills = scanUserSkills()

        guard let projectRoot else { return userSkills }

        let projectSkills = scanProjectSkills(root: projectRoot)
        guard !projectSkills.isEmpty else { return userSkills }

        // Project skills take priority — insert them first, then user skills that don't collide.
        var seen = Set<String>()
        var merged: [SkillRecord] = []
        for skill in projectSkills {
            if seen.insert(skill.name).inserted {
                merged.append(skill)
            }
        }
        for skill in userSkills {
            if seen.insert(skill.name).inserted {
                merged.append(skill)
            }
        }
        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Legacy entry point — scans user-level only (backward compat).
    static func scanDefaultLocations() -> [SkillRecord] {
        scanUserSkills()
    }

    /// Lists non-SKILL.md files in a skill's directory (bundled resources).
    static func listResources(for record: SkillRecord) -> [String] {
        if let cached = resourcesCache[record.path] {
            return cached
        }

        let skillFileURL = URL(fileURLWithPath: record.path)
        let skillDir = skillFileURL.deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(
            at: skillDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var resources: [String] = []
        let maxResources = 30
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.lastPathComponent != "SKILL.md" else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                  !isDir.boolValue else { continue }
            // Compute relative path from skill directory.
            let relativePath = fileURL.path.replacingOccurrences(
                of: skillDir.path + "/", with: ""
            )
            resources.append(relativePath)
            if resources.count >= maxResources { break }
        }
        let sorted = resources.sorted()
        resourcesCache[record.path] = sorted
        return sorted
    }

    // MARK: - Internal scanning

    private static func scanRoots(_ roots: [URL], defaultSourceLabel: String) -> [SkillRecord] {
        var records: [SkillRecord] = []
        var seen = Set<String>()

        for root in roots {
            // Only create directories for global App Support. Don't create in project repos.
            if defaultSourceLabel == SkillScope.global.sourceLabel && root.path.contains("Application Support") {
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for folder in contents {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                let skillFile = folder.appendingPathComponent("SKILL.md")
                guard FileManager.default.fileExists(atPath: skillFile.path),
                      let record = parseSkill(at: skillFile, folderName: folder.lastPathComponent, sourceLabel: defaultSourceLabel)
                else { continue }
                if seen.insert(record.name).inserted {
                    records.append(record)
                }
            }
        }

        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func readBody(for record: SkillRecord) -> String {
        if let cached = bodyCache[record.path] {
            return cached
        }
        guard let text = try? String(contentsOfFile: record.path, encoding: .utf8) else { return "" }
        let body = stripFrontmatter(text)
        bodyCache[record.path] = body
        return body
    }

    private static func parseSkill(at file: URL, folderName: String, sourceLabel: String) -> SkillRecord? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let parsed = parseFrontmatter(text)
        let name = parsed.scalars["name"] ?? folderName

        // Spec: name must match the parent directory name.
        guard name == folderName else { return nil }
        // Spec: validate name format.
        guard isValidSkillName(name) else { return nil }

        guard let description = parsed.scalars["description"], !description.isEmpty else {
            // Spec: skip skills with missing/empty description.
            return nil
        }
        let disableModel = parsed.scalars["disable-model-invocation"]?.lowercased() == "true"
        return SkillRecord(
            name: name,
            description: description,
            path: file.path,
            enabled: true,
            sourceLabel: sourceLabel,
            disableModelInvocation: disableModel,
            license: parsed.scalars["license"],
            compatibility: parsed.scalars["compatibility"],
            metadata: parsed.metadata.isEmpty ? nil : parsed.metadata,
            allowedTools: parsed.scalars["allowed-tools"],
            provenance: parsed.scalars["source"]
        )
    }

    /// Validates a skill name per the Agent Skills spec:
    /// - 1–64 characters
    /// - Only lowercase alphanumeric and hyphens
    /// - Must not start or end with a hyphen
    /// - Must not contain consecutive hyphens
    private static func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        guard !name.hasPrefix("-"), !name.hasSuffix("-") else { return false }
        guard !name.contains("--") else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    /// Finds the closing `---` of a YAML frontmatter block.
    /// Returns the range of the entire frontmatter (including both `---` delimiters)
    /// so the body can be extracted reliably even when it contains `---`.
    private static func frontmatterRange(_ text: String) -> Range<String.Index>? {
        guard text.hasPrefix("---") else { return nil }
        // Skip the opening "---\n"
        guard let firstNewline = text.firstIndex(of: "\n") else { return nil }
        let afterOpener = text.index(after: firstNewline)
        // Scan line-by-line for a line that is exactly "---"
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

    private static let recognizedKeys: Set<String> = [
        "name", "description", "disable-model-invocation",
        "license", "compatibility", "allowed-tools", "source",
    ]

    /// Parsed frontmatter result containing scalar fields and the nested metadata map.
    struct ParsedFrontmatter {
        var scalars: [String: String] = [:]
        var metadata: [String: String] = [:]
    }

    private static func parseFrontmatter(_ text: String) -> ParsedFrontmatter {
        guard let range = frontmatterRange(text) else { return ParsedFrontmatter() }
        let block = text[range]
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        var result = ParsedFrontmatter()
        var inMetadata = false

        for line in lines {
            let raw = String(line)

            // Detect indented lines under `metadata:` block.
            if inMetadata {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                // Still indented → metadata entry.
                if raw.hasPrefix("  ") || raw.hasPrefix("\t"), !trimmed.isEmpty, trimmed != "---" {
                    if let colon = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                        var value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                            value = String(value.dropFirst().dropLast())
                        }
                        if !key.isEmpty {
                            result.metadata[key] = value
                        }
                    }
                    continue
                }
                // No longer indented — exit metadata block.
                inMetadata = false
            }

            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)

            if key == "metadata" {
                // `metadata:` with no inline value starts a nested map.
                let inlineValue = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if inlineValue.isEmpty {
                    inMetadata = true
                }
                continue
            }

            guard recognizedKeys.contains(key) else { continue }
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result.scalars[key] = value
        }
        return result
    }

    private static func stripFrontmatter(_ text: String) -> String {
        guard let range = frontmatterRange(text) else { return text }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

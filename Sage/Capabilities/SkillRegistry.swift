//
//  SkillRegistry.swift
//  Sage
//

import Foundation

enum SkillRegistry {
    static func scanDefaultLocations() -> [SkillRecord] {
        var roots: [URL] = []

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        roots.append(appSupport.appendingPathComponent("Sage/Skills", isDirectory: true))

        // Bundle-adjacent project skills during development (repo .agents/skills).
        if let repoSkills = discoverRepoSkillsDirectory() {
            roots.append(repoSkills)
        }

        var records: [SkillRecord] = []
        var seen = Set<String>()

        for root in roots {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
                      let record = parseSkill(at: skillFile, folderName: folder.lastPathComponent, root: root)
                else { continue }
                if seen.insert(record.name).inserted {
                    records.append(record)
                }
            }
        }

        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func readBody(for record: SkillRecord, limit: Int = 4_000) -> String {
        guard let text = try? String(contentsOfFile: record.path, encoding: .utf8) else { return "" }
        let body = stripFrontmatter(text)
        if body.count <= limit { return body }
        return String(body.prefix(limit)) + "\n…"
    }

    private static func discoverRepoSkillsDirectory() -> URL? {
        var urls: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            Bundle.main.bundleURL,
        ]
        if let executable = Bundle.main.executableURL {
            urls.append(executable.deletingLastPathComponent())
        }

        for start in urls {
            var url = start
            for _ in 0..<10 {
                let candidate = url.appendingPathComponent(".agents/skills", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                // Xcode sometimes cwd = project root containing Sage.xcodeproj
                let projectMarker = url.appendingPathComponent("Sage.xcodeproj", isDirectory: true)
                if FileManager.default.fileExists(atPath: projectMarker.path) {
                    let nested = url.appendingPathComponent(".agents/skills", isDirectory: true)
                    if FileManager.default.fileExists(atPath: nested.path) {
                        return nested
                    }
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        return nil
    }

    private static func parseSkill(at file: URL, folderName: String, root: URL) -> SkillRecord? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let meta = parseFrontmatter(text)
        let name = meta["name"] ?? folderName
        let description = meta["description"] ?? "Skill"
        let sourceLabel: String
        if root.path.contains("Application Support") {
            sourceLabel = "Installed"
        } else {
            sourceLabel = "Project"
        }
        return SkillRecord(
            name: name,
            description: description,
            path: file.path,
            enabled: true,
            sourceLabel: sourceLabel
        )
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        guard text.hasPrefix("---") else { return [:] }
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else { return [:] }
        let block = parts[1]
        var result: [String: String] = [:]
        for line in block.split(separator: "\n") {
            let raw = String(line)
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if key == "description" || key == "name" {
                result[key] = value
            }
        }
        // description may be folded onto following lines in YAML — keep first line for MVP.
        return result
    }

    private static func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else { return text }
        return parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  SkillRegistry.swift
//  Sage
//
//  Isolated skill filesystem library: scans, body/resource caches, merge.
//  Disk I/O runs on the actor executor (off MainActor when awaited from UI).
//

import Foundation

actor SkillRegistry {
    static let shared = SkillRegistry()

    private struct BodyCacheEntry {
        var body: String
        var mtime: Date
        var lastAccess: Date
    }

    /// Listing of bundled resources under a skill directory.
    struct ResourceListing: Sendable {
        let paths: [String]
        /// True when enumeration stopped at `maxResources` and more files may exist.
        let truncated: Bool
    }

    private static let maxResources = 30
    private static let maxBodyCacheEntries = 32
    private static let maxBodyCacheCharacters = 512_000

    /// In-memory cache for skill bodies (keyed by SKILL.md path).
    private var bodyCache: [String: BodyCacheEntry] = [:]

    /// In-memory cache for resource listings (keyed by SKILL.md path).
    private var resourcesCache: [String: ResourceListing] = [:]

    /// Clears all in-memory caches. Prefer `pruneCaches` or `invalidateCaches(forPath:)` when possible.
    func invalidateCaches() {
        bodyCache.removeAll()
        resourcesCache.removeAll()
    }

    /// Drop cached body/resources for one skill path (e.g. after delete/enhance).
    func invalidateCaches(forPath path: String) {
        bodyCache.removeValue(forKey: path)
        resourcesCache.removeValue(forKey: path)
    }

    /// Keep caches only for skills that still exist after a reload.
    func pruneCaches(keepingPaths: Set<String>) {
        bodyCache = bodyCache.filter { keepingPaths.contains($0.key) }
        resourcesCache = resourcesCache.filter { keepingPaths.contains($0.key) }
    }

    /// Combined scan: project skills (higher priority) + user skills.
    func scanAll(projectRoot: URL?) -> [SkillRecord] {
        let userSkills = scanUserSkills()
        guard let projectRoot else { return userSkills }
        let projectSkills = scanProjectSkills(root: projectRoot)
        return Self.mergeSkills(project: projectSkills, user: userSkills)
    }

    /// Merge pre-scanned project + user lists (project wins on name collision).
    nonisolated static func mergeSkills(project: [SkillRecord], user: [SkillRecord]) -> [SkillRecord] {
        guard !project.isEmpty else { return user }
        var seen = Set<String>()
        var merged: [SkillRecord] = []
        for skill in project {
            if seen.insert(skill.name).inserted {
                merged.append(skill)
            }
        }
        for skill in user {
            if seen.insert(skill.name).inserted {
                merged.append(skill)
            }
        }
        return merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Scans global (user-level) skill locations only.
    func scanUserSkills() -> [SkillRecord] {
        scanRoots(SkillPaths.globalScanRoots(), scope: .global)
    }

    /// Scans project-level skill locations under the given project root.
    func scanProjectSkills(root: URL) -> [SkillRecord] {
        scanRoots(SkillPaths.projectScanRoots(root: root), scope: .project)
    }

    /// Lists non-SKILL.md files in a skill's directory (bundled resources).
    func listResources(for record: SkillRecord) -> ResourceListing {
        if let cached = resourcesCache[record.path] {
            return cached
        }

        let skillFileURL = URL(fileURLWithPath: record.path)
        let skillDir = skillFileURL.deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(
            at: skillDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ResourceListing(paths: [], truncated: false)
        }

        var resources: [String] = []
        var truncated = false
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.lastPathComponent != "SKILL.md" else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                  !isDir.boolValue else { continue }
            let dirPath = skillDir.resolvingSymlinksInPath().path
            let filePath = fileURL.resolvingSymlinksInPath().path
            let prefix = dirPath.hasSuffix("/") ? dirPath : dirPath + "/"
            let relativePath: String
            if filePath.hasPrefix(prefix) {
                relativePath = String(filePath.dropFirst(prefix.count))
            } else {
                relativePath = fileURL.lastPathComponent
            }
            if resources.count >= Self.maxResources {
                truncated = true
                break
            }
            resources.append(relativePath)
        }
        let listing = ResourceListing(paths: resources.sorted(), truncated: truncated)
        resourcesCache[record.path] = listing
        return listing
    }

    func readBody(for record: SkillRecord) -> String {
        let mtime = Self.modificationDate(atPath: record.path) ?? .distantPast
        if var entry = bodyCache[record.path], entry.mtime == mtime {
            entry.lastAccess = Date()
            bodyCache[record.path] = entry
            return entry.body
        }

        // SKILL.md changed on disk — drop stale resource listing too.
        resourcesCache.removeValue(forKey: record.path)

        guard let text = try? String(contentsOfFile: record.path, encoding: .utf8) else { return "" }
        let body = SkillMarkdown.stripFrontmatter(text)
        bodyCache[record.path] = BodyCacheEntry(body: body, mtime: mtime, lastAccess: Date())
        evictBodyCacheIfNeeded()
        return body
    }

    // MARK: - Internal scanning

    private func scanRoots(_ roots: [URL], scope: SkillScope) -> [SkillRecord] {
        var records: [SkillRecord] = []
        var seen = Set<String>()
        let sageSkillsRoot = AppSupportPaths.userSkillsDirectory(createIfNeeded: false).path

        for root in roots {
            if scope == .global, root.path.hasPrefix(sageSkillsRoot) {
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
                      let record = parseSkill(at: skillFile, folderName: folder.lastPathComponent, scope: scope)
                else { continue }
                if seen.insert(record.name).inserted {
                    records.append(record)
                }
            }
        }

        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseSkill(at file: URL, folderName: String, scope: SkillScope) -> SkillRecord? {
        // Scan only needs frontmatter — avoid loading entire skill bodies into memory.
        guard let text = readPrefixForFrontmatter(at: file) else { return nil }
        let parsed = SkillMarkdown.parseFrontmatter(text)
        let name = parsed.scalars["name"] ?? folderName

        guard name == folderName else { return nil }
        guard SkillMarkdown.isValidSkillName(name) else { return nil }

        guard let description = parsed.scalars["description"], !description.isEmpty else {
            return nil
        }
        return SkillRecord(
            name: name,
            description: description,
            path: file.path,
            enabled: true,
            scope: scope,
            license: parsed.scalars["license"],
            compatibility: parsed.scalars["compatibility"],
            metadata: parsed.metadata.isEmpty ? nil : parsed.metadata,
            allowedTools: parsed.scalars["allowed-tools"],
            provenance: parsed.scalars["source"]
        )
    }

    /// Reads enough of SKILL.md to cover YAML frontmatter without loading huge bodies.
    private func readPrefixForFrontmatter(at file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let chunk = handle.readData(ofLength: 16_384)
        guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return nil }
        // If the closing --- isn't in the first chunk, fall back to a full read
        // (malformed / unusually large frontmatter is rare).
        if SkillMarkdown.frontmatterRange(text) != nil || !text.hasPrefix("---") {
            return text
        }
        return try? String(contentsOf: file, encoding: .utf8)
    }

    private func evictBodyCacheIfNeeded() {
        func totalCharacters() -> Int {
            bodyCache.values.reduce(0) { $0 + $1.body.count }
        }

        while bodyCache.count > Self.maxBodyCacheEntries
            || totalCharacters() > Self.maxBodyCacheCharacters {
            guard let oldest = bodyCache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
                break
            }
            bodyCache.removeValue(forKey: oldest.key)
        }
    }

    private static func modificationDate(atPath path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }
}

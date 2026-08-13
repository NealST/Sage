//
//  SkillCatalog.swift
//  Sage
//
//  Per-window skills catalog (enable flags, scan, prompt appendix).
//  MCP connections live on CapabilityStore (shared hub).
//

import Foundation

@MainActor
@Observable
final class SkillCatalog {
    private(set) var skills: [SkillRecord] = []

    private let store: SkillStateStore
    private let skillMatcher = SkillMatcher()
    /// Serializes enablement flush / delete so a stale merge cannot resurrect removed keys.
    private var stateWriteChain: Task<Void, Never>?
    /// Short-lived local matcher cache (normalized query → result).
    private var matchCache: [String: MatchCacheEntry] = [:]
    private let matchCacheTTL: TimeInterval = 120

    private struct MatchCacheEntry {
        let names: [String]
        let deferred: Bool
        let cachedAt: Date
    }

    /// Project root used for Finder “Open Folder” and last reload.
    private(set) var currentProjectRoot: URL?

    init(store: SkillStateStore) {
        self.store = store
    }

    /// Updates Finder/project context without rescanning (shared AppState reload already applied).
    func noteProjectRoot(_ root: URL?) {
        currentProjectRoot = root
    }

    var enabledSkills: [SkillRecord] {
        skills.filter(\.enabled)
    }

    /// Apply an already-scanned list (shared scan across sessions).
    func applyScanned(_ scanned: [SkillRecord], enablement: [String: Bool], projectRoot: URL?) {
        currentProjectRoot = projectRoot
        skills = scanned.map { skill in
            var copy = skill
            if let enabled = Self.enabledFlag(for: skill, in: enablement) {
                copy.enabled = enabled
            }
            return copy
        }
        matchCache.removeAll()
    }

    /// Reload from disk for this catalog's scope only.
    func reloadSkills(projectRoot: URL? = nil) async {
        let scanned = await SkillRegistry.shared.scanAll(projectRoot: projectRoot)
        let state = await store.load()
        applyScanned(scanned, enablement: state, projectRoot: projectRoot)
        await SkillRegistry.shared.pruneCaches(keepingPaths: Set(skills.map(\.path)))
    }

    func setSkillEnabled(_ skill: SkillRecord, enabled: Bool) {
        guard let index = skills.firstIndex(where: { $0.path == skill.path }) else { return }
        skills[index].enabled = enabled
        enqueueStateWrite { [weak self] in
            await self?.flushSkillEnablement()
        }
    }

    /// Legacy name-based toggle for callers that only have a name in a single-scope catalog.
    func setSkillEnabled(named name: String, enabled: Bool) {
        guard let skill = skills.first(where: { $0.name == name }) else { return }
        setSkillEnabled(skill, enabled: enabled)
    }

    func flushSkillEnablement() async {
        var map: [String: Bool] = [:]
        for skill in skills {
            map[skill.path] = skill.enabled
        }
        await store.merge(map)
    }

    func refreshSkillEnablementFromDisk() async {
        let state = await store.load()
        skills = skills.map { skill in
            var copy = skill
            if let enabled = Self.enabledFlag(for: skill, in: state) {
                copy.enabled = enabled
            }
            return copy
        }
    }

    func loadSkillEnablementFromDisk() async -> [String: Bool] {
        await store.load()
    }

    private func enqueueStateWrite(_ work: @escaping @MainActor () async -> Void) {
        let previous = stateWriteChain
        stateWriteChain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    func deleteSkill(_ skill: SkillRecord) async throws {
        let path = skill.path
        let name = skill.name

        // Serialize against enablement flushes. `trashSkill` awaits a detached
        // utility task, so FileManager work does not occupy the main thread.
        let previous = stateWriteChain
        let write = Task { @MainActor in
            await previous?.value
            try await SkillWriter.trashSkill(atSkillMarkdownPath: path)
            self.skills.removeAll { $0.path == path }
            await self.store.remove(keys: [path, name])
        }
        stateWriteChain = Task { @MainActor in
            _ = try? await write.value
        }
        try await write.value
    }

    /// Path-first lookup with legacy name-key fallback for older skills-state.json files.
    private static func enabledFlag(for skill: SkillRecord, in map: [String: Bool]) -> Bool? {
        if let enabled = map[skill.path] { return enabled }
        return map[skill.name]
    }

    struct SkillAppendixResult: Sendable {
        let text: String
        let needsLoadSkillTool: Bool
        let recommendedSkills: [String]
        let deferredToCloud: Bool
    }

    func skillsPromptAppendix(
        for userMessage: String,
        skipMatching: Bool = false
    ) async -> SkillAppendixResult {
        let active = enabledSkills
        guard !active.isEmpty else {
            return SkillAppendixResult(
                text: "",
                needsLoadSkillTool: false,
                recommendedSkills: [],
                deferredToCloud: false
            )
        }

        let recommended: [String]
        let deferred: Bool
        if skipMatching {
            recommended = []
            deferred = false
        } else {
            let cacheKey = Self.normalizedMatchKey(userMessage)
            if let hit = matchCache[cacheKey],
               Date().timeIntervalSince(hit.cachedAt) < matchCacheTTL {
                recommended = hit.names
                deferred = hit.deferred
            } else {
                let matchResult = await skillMatcher.match(
                    userMessage: userMessage,
                    skills: active
                )
                switch matchResult {
                case .resolved(let names):
                    recommended = names
                    deferred = false
                case .deferred:
                    recommended = []
                    deferred = true
                }
                matchCache[cacheKey] = MatchCacheEntry(
                    names: recommended,
                    deferred: deferred,
                    cachedAt: Date()
                )
            }
        }

        let excludeFromCatalog: Set<String>
        if recommended.count == 1 {
            excludeFromCatalog = Set(recommended)
        } else {
            excludeFromCatalog = []
        }
        let catalogSkills = active.filter { !excludeFromCatalog.contains($0.name) }

        var lines: [String] = []
        if !catalogSkills.isEmpty {
            lines.append("")
            lines.append("## Available Skills")
            lines.append("Use the `load_skill` tool to activate a skill's full instructions when relevant to the user's request.")
            lines.append("Activate at most one skill at a time for a given step of work.")
            lines.append("")

            for skill in catalogSkills {
                var entry = "- **\(skill.name)**: \(skill.description)"
                if let compat = skill.compatibility {
                    entry += " _(requires: \(compat))_"
                }
                lines.append(entry)
            }
            lines.append("")
        }

        return SkillAppendixResult(
            text: lines.joined(separator: "\n"),
            needsLoadSkillTool: true,
            recommendedSkills: recommended,
            deferredToCloud: deferred
        )
    }

    func loadSkillBody(name: String) async -> String? {
        guard let skill = skills.first(where: { $0.name == name && $0.enabled }) else {
            return nil
        }
        return await SkillRegistry.shared.readBody(for: skill)
    }

    private static func normalizedMatchKey(_ message: String) -> String {
        message
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }
}

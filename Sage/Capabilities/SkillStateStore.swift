//
//  SkillStateStore.swift
//  Sage
//
//  Persists skill enablement flags (skills-state.json).
//

import Foundation

actor SkillStateStore {
    private let fileURL: URL

    init(fileURL: URL = AppSupportPaths.skillStateURL()) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load() -> [String: Bool] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(SkillStateSnapshot.self, from: data)
        else {
            return [:]
        }
        return snapshot.enabled
    }

    func save(_ enabled: [String: Bool]) {
        let snapshot = SkillStateSnapshot(enabled: enabled)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Merge enable flags into the on-disk map so partial catalogs cannot wipe other scopes.
    func merge(_ updates: [String: Bool]) {
        var map = load()
        for (key, enabled) in updates {
            map[key] = enabled
        }
        save(map)
    }

    /// Drops enablement keys after a skill is deleted (path and optional legacy name key).
    func remove(keys: [String]) {
        guard !keys.isEmpty else { return }
        var map = load()
        var changed = false
        for key in keys where map.removeValue(forKey: key) != nil {
            changed = true
        }
        if changed {
            save(map)
        }
    }
}

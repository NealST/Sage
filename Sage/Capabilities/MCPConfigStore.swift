//
//  MCPConfigStore.swift
//  Sage
//

import Foundation

actor MCPConfigStore {
    private let fileURL: URL
    private let skillStateURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("mcp.json")
        skillStateURL = dir.appendingPathComponent("skills-state.json")
    }

    func loadServers() -> [MCPServerConfig] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(MCPFileSnapshot.self, from: data)
        else {
            return []
        }
        return snapshot.mcpServers
    }

    func saveServers(_ servers: [MCPServerConfig]) {
        let snapshot = MCPFileSnapshot(mcpServers: servers)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func loadSkillState() -> [String: Bool] {
        guard let data = try? Data(contentsOf: skillStateURL),
              let snapshot = try? JSONDecoder().decode(SkillStateSnapshot.self, from: data)
        else {
            return [:]
        }
        return snapshot.enabled
    }

    func saveSkillState(_ enabled: [String: Bool]) {
        let snapshot = SkillStateSnapshot(enabled: enabled)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: skillStateURL, options: [.atomic])
    }
}

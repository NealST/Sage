//
//  MCPConfigStore.swift
//  Sage
//
//  Persists MCP server configs (mcp.json). Skill enablement lives in SkillStateStore.
//

import Foundation

actor MCPConfigStore {
    private let fileURL: URL

    init(fileURL: URL = AppSupportPaths.mcpConfigURL()) {
        self.fileURL = fileURL
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
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
}

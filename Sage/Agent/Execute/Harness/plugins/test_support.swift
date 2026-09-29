//
//  test_support.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/test_support.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Fixture writers are faithful. `load_plugins_config` waits on Config.
//

import Foundation

public let OPENAI_API_CURATED_MARKETPLACE_NAME = "openai-api-curated"
public let TEST_CURATED_PLUGIN_SHA = "0123456789abcdef0123456789abcdef01234567"
public let CONFIG_TOML_FILE = "config.toml"

public func writeFile(_ path: URL, contents: String) throws {
    try FileManager.default.createDirectory(
        at: path.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: path, atomically: true, encoding: .utf8)
}

public func writeCuratedPlugin(root: URL, pluginName: String) throws {
    let pluginRoot = root.appendingPathComponent("plugins").appendingPathComponent(pluginName)
    try writeFile(
        pluginRoot.appendingPathComponent(".codex-plugin/plugin.json"),
        contents: """
        {
          "name": "\(pluginName)",
          "description": "Plugin that includes skills, MCP servers, and app connectors"
        }
        """
    )
    try writeFile(
        pluginRoot.appendingPathComponent("skills/SKILL.md"),
        contents: "---\nname: sample\ndescription: sample\n---\n"
    )
    try writeFile(
        pluginRoot.appendingPathComponent(".mcp.json"),
        contents: """
        {
          "mcpServers": {
            "sample-docs": {
              "type": "http",
              "url": "https://sample.example/mcp"
            }
          }
        }
        """
    )
    try writeFile(
        pluginRoot.appendingPathComponent(".app.json"),
        contents: """
        {
          "apps": {
            "calendar": {
              "id": "connector_calendar"
            }
          }
        }
        """
    )
}

public func writeOpenaiApiCuratedMarketplace(root: URL, pluginNames: [String]) throws {
    let plugins = pluginNames.map { pluginName in
        """
            {
              "name": "\(pluginName)",
              "source": {
                "source": "local",
                "path": "./plugins/\(pluginName)"
              }
            }
        """
    }.joined(separator: ",\n")
    try writeFile(
        root.appendingPathComponent(".agents/plugins/api_marketplace.json"),
        contents: """
        {
          "name": "\(OPENAI_API_CURATED_MARKETPLACE_NAME)",
          "plugins": [
        \(plugins)
          ]
        }
        """
    )
    for pluginName in pluginNames {
        try writeCuratedPlugin(root: root, pluginName: pluginName)
    }
}

public func writeCuratedPluginSha(_ codexHome: URL) throws {
    try writeCuratedPluginSha(codexHome, sha: TEST_CURATED_PLUGIN_SHA)
}

public func writeCuratedPluginSha(_ codexHome: URL, sha: String) throws {
    try writeFile(
        codexHome.appendingPathComponent(".tmp/plugins.sha"),
        contents: "\(sha)\n"
    )
}

public func writePluginsFeatureConfig(_ codexHome: URL) throws {
    try writeFile(
        codexHome.appendingPathComponent(CONFIG_TOML_FILE),
        contents: """
        [features]
        plugins = true
        """
    )
}

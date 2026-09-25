//
//  plugin_namespace.swift
//  CodexUtils
//
//  Port of codex-rs/utils/plugins/src/plugin_namespace.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolve plugin namespace from skill file paths by walking ancestors for
//  `plugin.json`. Upstream uses `codex_exec_server::EnvironmentAccess` for
//  sandboxed async file access; Sage uses Foundation `FileManager` directly
//  since plugin resolution runs on the host (not in a sandbox). The async
//  `plugin_namespace_for_root_uri` is adapted to use `FileManager`.
//

import Foundation

public let agentPluginManifestRelativePath = "plugin.json"
/// Published Agent Plugins v1 manifest schema.
public let agentPluginSchemaURI =
    "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
public let supportedAgentPluginSchemaURIs: [String] = [agentPluginSchemaURI]
public let agentPluginSchemaPrefix = "https://agent-plugins.org/schemas/"

public enum AgentPluginSchemaStatus: Equatable, Sendable {
    case supported
    case unsupported
    case unrelated
}

public func agentPluginSchemaStatus(contents: String) -> AgentPluginSchemaStatus {
    guard let data = contents.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let schema = json["$schema"] as? String
    else {
        return .unrelated
    }
    if supportedAgentPluginSchemaURIs.contains(schema) {
        return .supported
    } else if schema.hasPrefix(agentPluginSchemaPrefix) {
        return .unsupported
    } else {
        return .unrelated
    }
}

/// Finds the first matching plugin manifest path under `pluginRoot`.
///
/// Precedence: `plugin.json` at root (only if it declares a recognized
/// `$schema`), then the discoverable legacy paths in order.
public func findPluginManifestPath(pluginRoot: String) -> String? {
    let fm = FileManager.default

    // Try the root-level agent manifest first.
    let agentManifestPath = (pluginRoot as NSString).appendingPathComponent(
        agentPluginManifestRelativePath
    )
    if let attrs = try? fm.attributesOfItem(atPath: agentManifestPath),
       let type = attrs[.type] as? FileAttributeType
    {
        if type == .typeSymbolicLink || type != .typeRegular {
            return nil
        }
        if let contents = try? String(contentsOfFile: agentManifestPath, encoding: .utf8),
           agentPluginSchemaStatus(contents: contents) != .unrelated
        {
            return agentManifestPath
        }
    }

    // Walk discoverable legacy paths.
    for relativePath in discoverablePluginManifestPaths {
        let manifestPath = (pluginRoot as NSString).appendingPathComponent(relativePath)
        let manifestParent = (manifestPath as NSString).deletingLastPathComponent

        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: manifestParent, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return nil }
        } else {
            continue
        }

        if let attrs = try? fm.attributesOfItem(atPath: manifestPath),
           let type = attrs[.type] as? FileAttributeType
        {
            if type == .typeRegular {
                return manifestPath
            } else {
                return nil
            }
        }
    }
    return nil
}

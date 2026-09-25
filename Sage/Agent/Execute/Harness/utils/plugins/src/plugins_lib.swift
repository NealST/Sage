//
//  plugins_lib.swift
//  CodexUtils
//
//  Port of codex-rs/utils/plugins/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Plugin path resolution and shared types. Upstream re-exports from
//  `codex_exec_server_protocol::DISCOVERABLE_PLUGIN_MANIFEST_PATHS` and
//  `plugin_namespace` (async fs resolution via `EnvironmentAccess`).
//  Sage does not have `codex-exec-server`; the discoverable manifest paths
//  constant is inlined here and the async `plugin_namespace_for_root_uri`
//  function is omitted (it will be adapted when MCP plugin support lands).
//
//  R4a: upstream `lib.rs` → `plugins_lib.swift` (basename dedup).
//

import Foundation

// MARK: - Discoverable manifest paths (inlined from codex_exec_server_protocol)

/// Ordered list of relative paths where a plugin manifest may be found.
/// First match wins. Matches upstream `DISCOVERABLE_PLUGIN_MANIFEST_PATHS`.
public let discoverablePluginManifestPaths: [String] = [
    ".codex-plugin/plugin.json",
    ".claude-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
]

// MARK: - Skill discovery mode

public enum SkillDiscoveryMode: Equatable, Hashable, Sendable {
    case recursive
    case directChildren
}

// MARK: - Plugin identity

/// The local identifier and optional remote identifier for a plugin.
public struct PluginIdentity: Equatable, Hashable, Sendable {
    public var pluginId: String
    public var remotePluginId: String?

    public init(pluginId: String, remotePluginId: String? = nil) {
        self.pluginId = pluginId
        self.remotePluginId = remotePluginId
    }
}

// MARK: - Plugin skill root

public struct PluginSkillRoot: Equatable, Hashable, Sendable {
    public var path: AbsolutePathBuf
    public var pluginIdentity: PluginIdentity
    public var pluginNamespace: String
    public var pluginRoot: AbsolutePathBuf
    public var discoveryMode: SkillDiscoveryMode

    public init(
        path: AbsolutePathBuf,
        pluginIdentity: PluginIdentity,
        pluginNamespace: String,
        pluginRoot: AbsolutePathBuf,
        discoveryMode: SkillDiscoveryMode
    ) {
        self.path = path
        self.pluginIdentity = pluginIdentity
        self.pluginNamespace = pluginNamespace
        self.pluginRoot = pluginRoot
        self.discoveryMode = discoveryMode
    }
}

// MARK: - Metadata directory constants

/// Directory containing private plugin metadata.
private let pluginMetadataDir = ".codex-plugin"
/// Directory containing commands converted into skills during plugin installation.
private let migratedCommandSkillsDir = "migrated-command-skills"

/// Returns the install-time command migration output directory for a plugin.
public func migratedCommandSkillsRoot(pluginRoot: AbsolutePathBuf) -> AbsolutePathBuf {
    pluginRoot.join(pluginMetadataDir).join(migratedCommandSkillsDir)
}
